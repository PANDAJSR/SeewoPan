part of 'pinco_api_client.dart';

extension PincoApiClientUploadExtension on PincoApiClient {
  Future<UploadFileResult> uploadFileBytes({
    required String cookie,
    required Uint8List bytes,
    required String fileName,
    String parentFolderId = '0',
    String? mimeType,
    UploadProgressCallback? onProgress,
  }) async {
    final totalWatch = Stopwatch()..start();
    final normalizedCookie = cookie.trim();
    final normalizedName = fileName.trim();
    final normalizedParentFolderId = parentFolderId.trim();

    if (normalizedCookie.isEmpty) {
      throw ArgumentError.value(cookie, 'cookie', 'Cookie cannot be empty.');
    }
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'File cannot be empty.');
    }
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
          fileName, 'fileName', 'File name cannot be empty.');
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

    final digest = md5.convert(bytes);
    final fileMd5 = digest.toString();
    final fileSize = bytes.lengthInBytes;
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
      cookie: normalizedCookie,
      payload: <String, dynamic>{
        'fileMd5': fileMd5,
        'fileSize': fileSize,
        'fileName': normalizedName,
        'mimeType': resolvedMimeType,
      },
    );

    final matchExists = _toBool(
      _pick(matchResponse,
          ['matched', 'exists', 'alreadyExist', 'isExist', 'hit']),
    );
    final matchedUrl =
        _pick(matchResponse, ['downloadUrl', 'url', 'accessUrl'])?.toString();
    final matchedKey = _pick(matchResponse, ['fileKey', 'key'])?.toString();

    if (matchExists &&
        matchedUrl != null &&
        matchedKey != null &&
        matchedKey.isNotEmpty) {
      reportProgress(progress: 1);
      totalWatch.stop();
      final metrics = _buildUploadMetrics(
        fileSizeBytes: fileSize,
        totalElapsed: totalWatch.elapsed,
        uploadElapsed: Duration.zero,
      );
      return UploadFileResult(
        deduplicated: true,
        id: _pick(matchResponse, ['id', 'materialId', 'fileId'])?.toString(),
        name: normalizedName,
        size: fileSize,
        mimeType: resolvedMimeType,
        fileMd5: fileMd5,
        fileKey: matchedKey,
        authDownloadUrl: matchedUrl,
        downloadUrl: matchedUrl,
        message: 'File matched existing content; skipped upload.',
        metrics: metrics,
      );
    }

    reportProgress(progress: 0.18);

    final suffix = _extWithoutDot(normalizedName).isEmpty
        ? 'bin'
        : _extWithoutDot(normalizedName);
    final policyResponse = await _postAction(
      actionName: 'PostV3CstoreUploadPolicy',
      cookie: normalizedCookie,
      payload: <String, dynamic>{'keySuffix': suffix},
    );
    final policy = _normalizeUploadPolicy(policyResponse, normalizedName);

    final missing = <String>[];
    if (!_hasValue(policy.fields['policy'])) {
      missing.add('policy');
    }
    if (!_hasValue(policy.fields['Signature']) &&
        !_hasValue(policy.fields['signature'])) {
      missing.add('Signature/signature');
    }
    if (!_hasValue(policy.fields['OSSAccessKeyId']) &&
        !_hasValue(policy.fields['accessKeyId'])) {
      missing.add('OSSAccessKeyId/accessKeyId');
    }
    if (!_hasValue(policy.fields['key'])) {
      missing.add('key');
    }
    if (missing.isNotEmpty) {
      throw FormatException(
        'PostV3CstoreUploadPolicy missing required upload fields: ${missing.join(', ')}',
      );
    }

    reportProgress(progress: 0.28);

    final uploadWatch = Stopwatch()..start();
    await _uploadToOss(
      host: policy.host,
      fields: policy.fields,
      headers: policy.headers,
      bytes: bytes,
      fileName: normalizedName,
      mimeType: resolvedMimeType,
      chunkSizeBytes: PincoApiClient._uploadChunkSizeBytes,
      onProgress: onProgress == null
          ? null
          : (sent, total) {
              final normalizedTotal = total <= 0 ? fileSize : total;
              final uploadProgress = normalizedTotal <= 0
                  ? 0.0
                  : (sent / normalizedTotal).clamp(0.0, 1.0).toDouble();
              final staged = 0.28 + uploadProgress * 0.67;
              onProgress(
                UploadProgress(
                  sentBytes: sent,
                  totalBytes: normalizedTotal,
                  elapsed: uploadWatch.elapsed,
                  estimatedProgress: staged,
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
      'name': normalizedName,
      'parentFolderId': normalizedParentFolderId,
      'size': fileSize,
      'mimeType': resolvedMimeType,
    };

    final commitResponse = await _postAction(
      actionName: 'PostV1DriveMaterialsCstoreWay',
      cookie: normalizedCookie,
      payload: commitPayload,
    );

    final materialId =
        _pick(commitResponse, ['id', 'materialId', 'fileId'])?.toString();
    final authDownloadUrl =
        _pick(commitResponse, ['downloadUrl', 'url', 'accessUrl'])?.toString();
    final committedDownloadUrl =
        authDownloadUrl ?? commitPayload['downloadUrl']?.toString();
    final committedFileKey =
        (_pick(commitResponse, ['fileKey', 'key'])?.toString() ??
            commitPayload['fileKey'].toString());

    _materialsCache.clear();

    totalWatch.stop();
    reportProgress(progress: 1);
    final metrics = _buildUploadMetrics(
      fileSizeBytes: fileSize,
      totalElapsed: totalWatch.elapsed,
      uploadElapsed: uploadWatch.elapsed,
    );

    return UploadFileResult(
      deduplicated: false,
      id: materialId,
      name: normalizedName,
      size: fileSize,
      mimeType: resolvedMimeType,
      fileMd5: fileMd5,
      fileKey: committedFileKey,
      authDownloadUrl: authDownloadUrl,
      downloadUrl: committedDownloadUrl,
      metrics: metrics,
    );
  }

  Future<void> _uploadToOss({
    required String host,
    required Map<String, dynamic> fields,
    required Map<String, dynamic> headers,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required int chunkSizeBytes,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData();

    const preferredOrder = <String>[
      'OSSAccessKeyId',
      'accessKeyId',
      'policy',
      'Signature',
      'signature',
      'key',
      'callback',
      'success_action_status',
      'x:appid',
      'x:sessionid',
      'x:bucketid',
      'x-oss-forbid-overwrite',
    ];

    final appended = <String>{};

    for (final field in preferredOrder) {
      final value = fields[field];
      if (_hasValue(value)) {
        formData.fields.add(MapEntry(field, value.toString()));
        appended.add(field);
      }
    }

    for (final entry in fields.entries) {
      if (appended.contains(entry.key)) {
        continue;
      }
      if (_hasValue(entry.value)) {
        formData.fields.add(MapEntry(entry.key, entry.value.toString()));
      }
    }

    formData.files.add(
      MapEntry(
        'file',
        MultipartFile.fromStream(
          () => _chunkedByteStream(bytes, chunkSizeBytes),
          bytes.lengthInBytes,
          filename: fileName,
          contentType: DioMediaType.parse(mimeType),
        ),
      ),
    );

    final requestHeaders = <String, dynamic>{
      'Accept': '*/*',
      'Origin': PincoApiClient._origin,
      'Referer': '${PincoApiClient._baseUrl}/',
      ...headers,
    };

    requestHeaders.removeWhere((key, value) {
      if (value == null) {
        return true;
      }
      return key.toLowerCase() == 'content-type';
    });

    final response = await _dioClient.post<dynamic>(
      host,
      data: formData,
      options:
          Options(headers: requestHeaders, responseType: ResponseType.plain),
      onSendProgress: onProgress,
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw Exception('OSS upload failed ($statusCode)');
    }
  }

  Stream<List<int>> _chunkedByteStream(
      Uint8List bytes, int chunkSizeBytes) async* {
    final normalizedChunkSize =
        chunkSizeBytes <= 0 ? 64 * 1024 : chunkSizeBytes;
    var offset = 0;
    while (offset < bytes.lengthInBytes) {
      final end = min(offset + normalizedChunkSize, bytes.lengthInBytes);
      yield Uint8List.sublistView(bytes, offset, end);
      offset = end;
    }
  }

  UploadMetrics _buildUploadMetrics({
    required int fileSizeBytes,
    required Duration totalElapsed,
    required Duration uploadElapsed,
  }) {
    final uploadSeconds = uploadElapsed.inMilliseconds / 1000;
    final uploadSpeedBps =
        uploadSeconds > 0 ? fileSizeBytes / uploadSeconds : 0.0;
    return UploadMetrics(
      fileSizeBytes: fileSizeBytes,
      totalElapsed: totalElapsed,
      uploadElapsed: uploadElapsed,
      uploadSpeedBps: uploadSpeedBps,
    );
  }

  String _guessMimeType(String fileName) {
    return lookupMimeType(fileName) ?? 'application/octet-stream';
  }

  String _buildFileKey(String fileName, String keyPrefix) {
    final prefix = _ensureTrailingSlash(
        keyPrefix.trim().isEmpty ? 'seewo-pinco-private/' : keyPrefix);
    final now = DateTime.now().millisecondsSinceEpoch;
    final randomPart = PincoApiClient._random
        .nextInt(1 << 32)
        .toRadixString(16)
        .padLeft(8, '0');
    final ext = _extWithoutDot(fileName);
    if (ext.isEmpty) {
      return '$prefix$now-$randomPart';
    }
    return '$prefix$now-$randomPart.$ext';
  }

  String _extWithoutDot(String fileName) {
    final normalized = fileName.trim();
    final lastDot = normalized.lastIndexOf('.');
    if (lastDot < 0 || lastDot == normalized.length - 1) {
      return '';
    }
    return normalized.substring(lastDot + 1).toLowerCase();
  }

  String _ensureTrailingSlash(String value) {
    if (value.endsWith('/')) {
      return value;
    }
    return '$value/';
  }
}
