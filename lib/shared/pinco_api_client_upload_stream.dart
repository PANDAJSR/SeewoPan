part of 'pinco_api_client.dart';

extension PincoApiClientUploadStreamExtension on PincoApiClient {
  Future<UploadFileResult> uploadFileStream({
    required String cookie,
    required Stream<List<int>> stream,
    required String fileName,
    required String parentFolderId,
    int? contentLength,
    String? mimeType,
    CancelToken? cancelToken,
    UploadProgressCallback? onProgress,
  }) async {
    final totalWatch = Stopwatch()..start();
    final normalizedCookie = cookie.trim();
    final normalizedName = fileName.trim();
    final normalizedParentFolderId = parentFolderId.trim();

    if (normalizedCookie.isEmpty) {
      throw ArgumentError.value(cookie, 'cookie', 'Cookie cannot be empty.');
    }
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        fileName,
        'fileName',
        'File name cannot be empty.',
      );
    }
    if (normalizedParentFolderId.isEmpty) {
      throw ArgumentError.value(
        parentFolderId,
        'parentFolderId',
        'Parent folder ID cannot be empty.',
      );
    }

    final resolvedMimeType = mimeType?.trim().isNotEmpty == true
        ? mimeType!.trim()
        : _guessMimeType(normalizedName);
    final stagedFile = await _stageUploadStream(
      stream: stream,
      fileName: normalizedName,
      expectedLength: contentLength,
      onProgress: onProgress,
      totalWatch: totalWatch,
    );

    try {
      final result = await _uploadPreparedFile(
        cookie: normalizedCookie,
        filePath: stagedFile.path,
        fileName: normalizedName,
        parentFolderId: normalizedParentFolderId,
        fileSize: stagedFile.size,
        fileMd5: stagedFile.md5,
        mimeType: resolvedMimeType,
        totalWatch: totalWatch,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
      return result;
    } finally {
      try {
        await File(stagedFile.path).delete();
      } catch (_) {
        // Best effort cleanup only.
      }
    }
  }

  Future<_StagedUploadFile> _stageUploadStream({
    required Stream<List<int>> stream,
    required String fileName,
    required int? expectedLength,
    required Stopwatch totalWatch,
    UploadProgressCallback? onProgress,
  }) async {
    final tempDirectory = Directory.systemTemp;
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final tempFile = File(
      '${tempDirectory.path}/seewopan-webdav-'
      '${DateTime.now().microsecondsSinceEpoch}-$safeName',
    );
    final output = _DigestSink();
    final input = md5.startChunkedConversion(output);
    final fileSink = tempFile.openWrite();
    var received = 0;

    try {
      await for (final chunk in stream) {
        received += chunk.length;
        input.add(chunk);
        fileSink.add(chunk);
        final total = expectedLength != null && expectedLength > 0
            ? expectedLength
            : received;
        onProgress?.call(
          UploadProgress(
            sentBytes: received,
            totalBytes: total,
            elapsed: totalWatch.elapsed,
            estimatedProgress: 0.02,
          ),
        );
      }
      await fileSink.close();
      input.close();
    } catch (_) {
      await fileSink.close();
      input.close();
      try {
        await tempFile.delete();
      } catch (_) {}
      rethrow;
    }

    if (expectedLength != null &&
        expectedLength >= 0 &&
        expectedLength != received) {
      try {
        await tempFile.delete();
      } catch (_) {}
      throw const FormatException('Upload stream length mismatch.');
    }

    return _StagedUploadFile(
      path: tempFile.path,
      size: received,
      md5: output.digest.toString(),
    );
  }

  Future<UploadFileResult> _uploadPreparedFile({
    required String cookie,
    required String filePath,
    required String fileName,
    required String parentFolderId,
    required int fileSize,
    required String fileMd5,
    required String mimeType,
    required Stopwatch totalWatch,
    CancelToken? cancelToken,
    UploadProgressCallback? onProgress,
  }) async {
    var stagedProgress = 0.0;

    void reportProgress({
      required double progress,
      int? sentBytes,
      Duration? elapsed,
    }) {
      if (onProgress == null) {
        return;
      }
      final clampedProgress = progress.clamp(0.0, 1.0).toDouble();
      if (clampedProgress < stagedProgress) {
        return;
      }
      stagedProgress = clampedProgress;
      final estimatedSentBytes =
          sentBytes ?? (fileSize * clampedProgress).round().clamp(0, fileSize);
      onProgress(
        UploadProgress(
          sentBytes: estimatedSentBytes,
          totalBytes: fileSize,
          elapsed: elapsed ?? totalWatch.elapsed,
          estimatedProgress: clampedProgress,
        ),
      );
    }

    reportProgress(progress: 0.08);

    final matchResponse = await _postAction(
      actionName: 'PostV1DriveMaterialsMatch',
      cookie: cookie,
      payload: <String, dynamic>{
        'fileMd5': fileMd5,
        'fileSize': fileSize,
        'fileName': fileName,
        'mimeType': mimeType,
      },
    );

    final matchExists = _toBool(
      _pick(matchResponse, [
        'matched',
        'exists',
        'alreadyExist',
        'isExist',
        'hit',
      ]),
    );
    final matchedUrl =
        _pick(matchResponse, ['downloadUrl', 'url', 'accessUrl'])?.toString();
    final matchedKey = _pick(matchResponse, ['fileKey', 'key'])?.toString();

    if (matchExists &&
        matchedUrl != null &&
        matchedKey != null &&
        matchedKey.isNotEmpty) {
      totalWatch.stop();
      reportProgress(progress: 1);
      return UploadFileResult(
        deduplicated: true,
        id: _pick(matchResponse, ['id', 'materialId', 'fileId'])?.toString(),
        name: fileName,
        size: fileSize,
        mimeType: mimeType,
        fileMd5: fileMd5,
        fileKey: matchedKey,
        authDownloadUrl: matchedUrl,
        downloadUrl: matchedUrl,
        message: 'File matched existing content; skipped upload.',
        metrics: _buildUploadMetrics(
          fileSizeBytes: fileSize,
          totalElapsed: totalWatch.elapsed,
          uploadElapsed: Duration.zero,
        ),
      );
    }

    reportProgress(progress: 0.18);

    final suffix =
        _extWithoutDot(fileName).isEmpty ? 'bin' : _extWithoutDot(fileName);
    final policyResponse = await _postAction(
      actionName: 'PostV3CstoreUploadPolicy',
      cookie: cookie,
      payload: <String, dynamic>{'keySuffix': suffix},
    );
    final policy = _normalizeUploadPolicy(policyResponse, fileName);

    final uploadWatch = Stopwatch()..start();
    await _uploadFilePathToOss(
      host: policy.host,
      fields: policy.fields,
      headers: policy.headers,
      filePath: filePath,
      fileName: fileName,
      mimeType: mimeType,
      cancelToken: cancelToken,
      onProgress: onProgress == null
          ? null
          : (sent, total) {
              final normalizedTotal = total <= 0 ? fileSize : total;
              final uploadProgress = normalizedTotal <= 0
                  ? 1.0
                  : (sent / normalizedTotal).clamp(0.0, 1.0).toDouble();
              onProgress(
                UploadProgress(
                  sentBytes: sent,
                  totalBytes: normalizedTotal,
                  elapsed: uploadWatch.elapsed,
                  estimatedProgress: 0.28 + uploadProgress * 0.67,
                ),
              );
            },
    );
    uploadWatch.stop();
    reportProgress(progress: 0.95, elapsed: uploadWatch.elapsed);

    final commitPayload = <String, dynamic>{
      'fileSize': fileSize,
      'downloadUrl': policy.downloadUrl ??
          '${_ensureTrailingSlash(PincoApiClient._defaultCdnBase)}${policy.key}',
      'fileKey': policy.key,
      'fileMd5': fileMd5,
      'name': fileName,
      'parentFolderId': parentFolderId,
      'size': fileSize,
      'mimeType': mimeType,
    };

    final commitResponse = await _postAction(
      actionName: 'PostV1DriveMaterialsCstoreWay',
      cookie: cookie,
      payload: commitPayload,
    );

    _materialsCache.clear();
    _materialsCapacityCache.clear();

    totalWatch.stop();
    reportProgress(progress: 1);
    return UploadFileResult(
      deduplicated: false,
      id: _pick(commitResponse, ['id', 'materialId', 'fileId'])?.toString(),
      name: fileName,
      size: fileSize,
      mimeType: mimeType,
      fileMd5: fileMd5,
      fileKey: _pick(commitResponse, ['fileKey', 'key'])?.toString() ??
          commitPayload['fileKey'].toString(),
      authDownloadUrl:
          _pick(commitResponse, ['downloadUrl', 'url', 'accessUrl'])
              ?.toString(),
      downloadUrl: _pick(commitResponse, ['downloadUrl', 'url', 'accessUrl'])
              ?.toString() ??
          commitPayload['downloadUrl']?.toString(),
      metrics: _buildUploadMetrics(
        fileSizeBytes: fileSize,
        totalElapsed: totalWatch.elapsed,
        uploadElapsed: uploadWatch.elapsed,
      ),
    );
  }
}

class _StagedUploadFile {
  const _StagedUploadFile({
    required this.path,
    required this.size,
    required this.md5,
  });

  final String path;
  final int size;
  final String md5;
}

class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get digest {
    final value = _digest;
    if (value == null) {
      throw StateError('Digest has not been completed.');
    }
    return value;
  }

  @override
  void add(Digest data) {
    _digest = data;
  }

  @override
  void close() {}
}
