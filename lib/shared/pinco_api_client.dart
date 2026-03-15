import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'models/drive_material.dart';
import 'models/user_profile.dart';

typedef UploadProgressCallback = void Function(UploadProgress progress);

class UploadProgress {
  const UploadProgress({
    required this.sentBytes,
    required this.totalBytes,
    required this.elapsed,
  });

  final int sentBytes;
  final int totalBytes;
  final Duration elapsed;

  double get progress {
    if (totalBytes <= 0) {
      return 0;
    }
    return sentBytes / totalBytes;
  }

  double get speedBps {
    final seconds = elapsed.inMilliseconds / 1000;
    if (seconds <= 0) {
      return 0;
    }
    return sentBytes / seconds;
  }
}

class UploadMetrics {
  const UploadMetrics({
    required this.fileSizeBytes,
    required this.totalElapsed,
    required this.uploadElapsed,
    required this.uploadSpeedBps,
  });

  final int fileSizeBytes;
  final Duration totalElapsed;
  final Duration uploadElapsed;
  final double uploadSpeedBps;
}

class UploadFileResult {
  const UploadFileResult({
    required this.deduplicated,
    required this.name,
    required this.size,
    required this.mimeType,
    required this.fileMd5,
    required this.fileKey,
    required this.metrics,
    this.id,
    this.authDownloadUrl,
    this.downloadUrl,
    this.message,
  });

  final bool deduplicated;
  final String? id;
  final String name;
  final int size;
  final String mimeType;
  final String fileMd5;
  final String fileKey;
  final String? authDownloadUrl;
  final String? downloadUrl;
  final String? message;
  final UploadMetrics metrics;
}

class PincoApiClient {
  PincoApiClient({http.Client? httpClient, Dio? dioClient})
      : _httpClient = httpClient ?? http.Client(),
        _dioClient = dioClient ?? Dio();

  static final _random = Random();
  static const String _baseUrl = 'https://pinco.seewo.com';
  static const String _origin = _baseUrl;
  static const String _referer =
      'https://pinco.seewo.com/teacher/main/drive/resource';
  static const String _defaultOssHost =
      'https://cstore-private.oss-cn-hangzhou.aliyuncs.com';
  static const String _defaultCdnBase =
      'https://cstore-pri-pinco-bs.seewo.com/';

  final http.Client _httpClient;
  final Dio _dioClient;
  final Map<String, UserProfile> _userProfileCache = <String, UserProfile>{};
  final Map<String, List<DriveMaterial>> _materialsCache =
      <String, List<DriveMaterial>>{};

  Future<UserProfile> getUserInfo(
    String cookie, {
    bool forceRefresh = false,
  }) async {
    final normalizedCookie = cookie.trim();
    if (!forceRefresh) {
      final cached = _userProfileCache[normalizedCookie];
      if (cached != null) {
        return cached;
      }
    }

    final data = await _postAction(
      actionName: 'GetV1UsersInfo',
      cookie: normalizedCookie,
      payload: <String, dynamic>{},
    );

    if (data is! Map<String, dynamic>) {
      throw const FormatException('Missing user data.');
    }

    final profile = UserProfile.fromApi(data);
    _userProfileCache[normalizedCookie] = profile;
    return profile;
  }

  Future<List<DriveMaterial>> getRootMaterials({
    required String cookie,
    int page = 0,
    int size = 50,
    bool forceRefresh = false,
  }) async {
    return getMaterials(
      cookie: cookie,
      folderId: '0',
      page: page,
      size: size,
      forceRefresh: forceRefresh,
    );
  }

  Future<List<DriveMaterial>> getMaterials({
    required String cookie,
    required String folderId,
    int page = 0,
    int size = 50,
    String tagName = 'resource,folder',
    bool forceRefresh = false,
  }) async {
    final normalizedCookie = cookie.trim();
    final cacheKey = '$normalizedCookie::$folderId::$page::$size::$tagName';
    if (!forceRefresh) {
      final cached = _materialsCache[cacheKey];
      if (cached != null) {
        return cached;
      }
    }

    final data = await _postAction(
      actionName: 'GetV1DriveMaterials',
      cookie: normalizedCookie,
      payload: <String, dynamic>{
        'keyword': '',
        'size': size,
        'tagName': tagName,
        'page': page,
        'folderId': folderId,
      },
    );

    final rawList = _extractList(data);
    final materials = rawList
        .whereType<Map<String, dynamic>>()
        .map(DriveMaterial.fromApi)
        .toList(growable: false);
    _materialsCache[cacheKey] = materials;
    return materials;
  }

  String buildMaterialDownloadUrl(String materialId) {
    return '$_baseUrl/server-main/api/v1/drive/materials/download'
        '?resId=${Uri.encodeQueryComponent(materialId)}';
  }

  Future<void> renameMaterial({
    required String cookie,
    required String materialId,
    required String name,
  }) async {
    final normalizedCookie = cookie.trim();
    final normalizedMaterialId = materialId.trim();
    final normalizedName = name.trim();

    if (normalizedCookie.isEmpty) {
      throw ArgumentError.value(cookie, 'cookie', 'Cookie cannot be empty.');
    }
    if (normalizedMaterialId.isEmpty) {
      throw ArgumentError.value(
        materialId,
        'materialId',
        'Material ID cannot be empty.',
      );
    }
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Name cannot be empty.');
    }

    final data = await _postAction(
      actionName: 'PutV1DriveMaterialsByMaterialIdName',
      cookie: normalizedCookie,
      payload: <String, dynamic>{
        'materialId': normalizedMaterialId,
        'name': normalizedName,
      },
    );

    if (data == false) {
      throw const FormatException('Rename request failed.');
    }

    _materialsCache.clear();
  }

  Future<void> deleteMaterials({
    required String cookie,
    required List<String> materialIds,
  }) async {
    final normalizedCookie = cookie.trim();
    final normalizedMaterialIds = materialIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    if (normalizedCookie.isEmpty) {
      throw ArgumentError.value(cookie, 'cookie', 'Cookie cannot be empty.');
    }
    if (normalizedMaterialIds.isEmpty) {
      throw ArgumentError.value(
        materialIds,
        'materialIds',
        'Material IDs cannot be empty.',
      );
    }

    await _postAction(
      actionName: 'DeleteV1DriveMaterials',
      cookie: normalizedCookie,
      payload: <String, dynamic>{'resIds': normalizedMaterialIds},
    );

    _materialsCache.clear();
  }

  Future<String> createFolder({
    required String cookie,
    required String name,
    String parentFolderId = '0',
  }) async {
    final normalizedCookie = cookie.trim();
    final normalizedName = name.trim();
    final normalizedParentFolderId = parentFolderId.trim();

    if (normalizedCookie.isEmpty) {
      throw ArgumentError.value(cookie, 'cookie', 'Cookie cannot be empty.');
    }
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Folder name cannot be empty.');
    }
    if (normalizedParentFolderId.isEmpty) {
      throw ArgumentError.value(
        parentFolderId,
        'parentFolderId',
        'Parent folder ID cannot be empty.',
      );
    }

    final data = await _postAction(
      actionName: 'PostV1DriveMaterialsFolders',
      cookie: normalizedCookie,
      payload: <String, dynamic>{
        'name': normalizedName,
        'parentFolderId': normalizedParentFolderId,
      },
    );

    if (data is! Map<String, dynamic>) {
      throw const FormatException('Missing folder data.');
    }

    final folderId =
        _pick(data, ['id', 'folderId', 'resId'])?.toString().trim();
    if (folderId == null || folderId.isEmpty) {
      throw const FormatException('Missing folder id.');
    }

    _materialsCache.clear();
    return folderId;
  }

  Future<UploadFileResult> uploadFileBytes({
    required String cookie,
    required Uint8List bytes,
    required String fileName,
    String parentFolderId = '0',
    String? mimeType,
    UploadProgressCallback? onProgress,
  }) async {
    final totalStart = DateTime.now();
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
      final totalElapsed = DateTime.now().difference(totalStart);
      final metrics = _buildUploadMetrics(
        fileSizeBytes: fileSize,
        totalElapsed: totalElapsed,
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

    final uploadWatch = Stopwatch()..start();
    await _uploadToOss(
      host: policy.host,
      fields: policy.fields,
      headers: policy.headers,
      bytes: bytes,
      fileName: normalizedName,
      mimeType: resolvedMimeType,
      onProgress: onProgress == null
          ? null
          : (sent, total) {
              onProgress(
                UploadProgress(
                  sentBytes: sent,
                  totalBytes: total <= 0 ? fileSize : total,
                  elapsed: uploadWatch.elapsed,
                ),
              );
            },
    );
    uploadWatch.stop();

    final commitPayload = <String, dynamic>{
      'fileSize': fileSize,
      'downloadUrl': policy.downloadUrl ??
          '${_ensureTrailingSlash(_defaultCdnBase)}${policy.key}',
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

    final totalElapsed = DateTime.now().difference(totalStart);
    final metrics = _buildUploadMetrics(
      fileSizeBytes: fileSize,
      totalElapsed: totalElapsed,
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
        MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(mimeType),
        ),
      ),
    );

    final requestHeaders = <String, dynamic>{
      'Accept': '*/*',
      'Origin': _origin,
      'Referer': '$_baseUrl/',
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

  Future<dynamic> _postAction({
    required String actionName,
    required String cookie,
    required Map<String, dynamic> payload,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/teacher/api.json?actionName=$actionName',
    );

    final response = await _httpClient.post(
      uri,
      headers: {
        'Accept': '*/*',
        'Content-Type': 'application/json;charset=UTF-8',
        'x-language': 'zh_CHS',
        'x-server': 'default',
        'x-csrf-token': 'undefined',
        'x-req-traceid': _randomTraceId(),
        'Origin': _origin,
        'Referer': _referer,
        'Cookie': cookie,
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected response format.');
    }

    return _unwrapApiData(decoded);
  }

  dynamic _unwrapApiData(Map<String, dynamic> raw) {
    final code = _pick(raw, ['statusCode', 'code', 'errno']);
    if (code != null) {
      final parsed = int.tryParse(code.toString());
      if (parsed != null && !{0, 1, 200}.contains(parsed)) {
        final message =
            _pick(raw, ['message', 'msg', 'error', 'errorMsg'])?.toString() ??
                '接口返回错误';
        throw Exception(message);
      }
    }

    final success = _pick(raw, ['success', 'ok']);
    if (success == false) {
      final message =
          _pick(raw, ['message', 'msg', 'error', 'errorMsg'])?.toString() ??
              '接口返回失败';
      throw Exception(message);
    }

    return _pick(raw, ['data', 'result']) ?? raw;
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) {
      return data;
    }

    if (data is! Map<String, dynamic>) {
      return const [];
    }

    final list = _pick(data, ['list', 'records', 'items', 'rows', 'content']);
    if (list is List) {
      return list;
    }

    return const [];
  }

  dynamic _pick(dynamic source, List<String> keys) {
    if (source is! Map<String, dynamic>) {
      return null;
    }
    for (final key in keys) {
      if (source.containsKey(key) && source[key] != null) {
        return source[key];
      }
    }
    return null;
  }

  bool _toBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' ||
          normalized == 'true' ||
          normalized == 'yes' ||
          normalized == 'y';
    }
    return false;
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

  _NormalizedUploadPolicy _normalizeUploadPolicy(
      dynamic payload, String fileName) {
    var policyData =
        _pickObject(payload, ['policyData', 'uploadPolicy', 'data', 'result']);
    if (policyData.isEmpty) {
      policyData = _coerceMap(payload);
    }
    if (policyData.isEmpty && payload is List) {
      for (final item in payload) {
        final map = _coerceMap(item);
        if (map.isNotEmpty) {
          policyData = map;
          break;
        }
      }
    }
    final policyList = policyData['policyList'];
    Map<String, dynamic>? policyEntry;
    if (policyList is List) {
      for (final item in policyList) {
        final map = _coerceMap(item);
        if (map.isNotEmpty) {
          policyEntry = map;
          break;
        }
      }
    }
    if (policyEntry == null && payload is List) {
      for (final item in payload) {
        final map = _coerceMap(item);
        if (map.isNotEmpty) {
          policyEntry = map;
          break;
        }
      }
    }

    final formLike = <String, dynamic>{
      ..._collectScalarFields(
        _pickObject(policyData, ['form', 'formData', 'fields']),
      ),
      ..._keyValueArrayToObject(policyEntry?['formFields']),
    };

    final headerLike = _keyValueArrayToObject(policyEntry?['headerFields']);
    final genericUrl = _pick(policyData, ['url'])?.toString();
    final hostCandidate =
        _pick(policyEntry, ['uploadUrl', 'host', 'uploadHost', 'endpoint'])
                ?.toString() ??
            _pick(policyData, ['host', 'uploadHost', 'endpoint', 'uploadUrl'])
                ?.toString();

    final host = hostCandidate ??
        (_isOssEndpoint(genericUrl) ? genericUrl! : _defaultOssHost);

    final keyPrefix = _pick(policyData, ['keyPrefix', 'prefix'])?.toString() ??
        'seewo-pinco-private/';
    final pickedKey = _pick(policyEntry, ['fileKey', 'key'])?.toString() ??
        _pick(policyData, ['key', 'fileKey'])?.toString() ??
        formLike['key']?.toString();
    final key = pickedKey?.trim().isNotEmpty == true
        ? pickedKey!.trim()
        : _buildFileKey(fileName, keyPrefix);

    final downloadUrl =
        _pick(policyEntry, ['downloadUrl', 'accessUrl'])?.toString() ??
            _pick(policyData, ['downloadUrl', 'accessUrl'])?.toString() ??
            (_isOssEndpoint(genericUrl) ? null : genericUrl);

    final fields = <String, dynamic>{...formLike};
    fields['key'] = fields['key'] ?? key;
    fields['OSSAccessKeyId'] = fields['OSSAccessKeyId'] ??
        _pick(policyEntry, ['OSSAccessKeyId', 'accessKeyId']) ??
        _pick(policyData, ['OSSAccessKeyId', 'accessKeyId']);
    fields['policy'] = fields['policy'] ??
        _pick(policyEntry, ['policy']) ??
        _pick(policyData, ['policy']);
    fields['Signature'] = fields['Signature'] ??
        fields['signature'] ??
        _pick(policyEntry, ['Signature', 'signature']) ??
        _pick(policyData, ['Signature', 'signature']);
    fields['callback'] = fields['callback'] ??
        _pick(policyEntry, ['callback']) ??
        _pick(policyData, ['callback']);
    fields['x:appid'] = fields['x:appid'] ??
        _pick(policyEntry, ['x:appid']) ??
        _pick(policyData, ['x:appid', 'appId']);
    fields['x:sessionid'] = fields['x:sessionid'] ??
        _pick(policyEntry, ['x:sessionid']) ??
        _pick(policyData, ['x:sessionid']);
    fields['x:bucketid'] = fields['x:bucketid'] ??
        _pick(policyEntry, ['x:bucketid']) ??
        _pick(policyData, ['x:bucketid']);
    fields['x-oss-forbid-overwrite'] = fields['x-oss-forbid-overwrite'] ??
        _pick(policyEntry, ['x-oss-forbid-overwrite']) ??
        _pick(policyData, ['x-oss-forbid-overwrite']);

    if (!_hasValue(fields['success_action_status']) &&
        _hasValue(fields['successActionStatus'])) {
      fields['success_action_status'] = fields['successActionStatus'];
    }
    if (!_hasValue(fields['success_action_status'])) {
      fields['success_action_status'] = '200';
    }
    if (!_hasValue(fields['Signature']) && _hasValue(fields['signature'])) {
      fields['Signature'] = fields['signature'];
    }
    if (!_hasValue(fields['signature']) && _hasValue(fields['Signature'])) {
      fields['signature'] = fields['Signature'];
    }
    if (!_hasValue(fields['OSSAccessKeyId']) &&
        _hasValue(fields['accessKeyId'])) {
      fields['OSSAccessKeyId'] = fields['accessKeyId'];
    }

    return _NormalizedUploadPolicy(
      host: host,
      key: fields['key'].toString(),
      downloadUrl: downloadUrl,
      fields: fields,
      headers: headerLike,
    );
  }

  String _guessMimeType(String fileName) {
    return lookupMimeType(fileName) ?? 'application/octet-stream';
  }

  String _buildFileKey(String fileName, String keyPrefix) {
    final prefix = _ensureTrailingSlash(
        keyPrefix.trim().isEmpty ? 'seewo-pinco-private/' : keyPrefix);
    final now = DateTime.now().millisecondsSinceEpoch;
    final randomPart =
        _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
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

  bool _isOssEndpoint(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    return RegExp(r'(aliyuncs\.com|oss-)').hasMatch(value);
  }

  bool _hasValue(dynamic value) {
    if (value == null) {
      return false;
    }
    if (value is String) {
      return value.trim().isNotEmpty;
    }
    return true;
  }

  Map<String, dynamic> _pickObject(dynamic source, List<String> keys) {
    for (final key in keys) {
      final value = _pick(source, [key]);
      final map = _coerceMap(value);
      if (map.isNotEmpty) {
        return map;
      }
    }
    return const <String, dynamic>{};
  }

  Map<String, dynamic> _collectScalarFields(Map<String, dynamic> source) {
    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is String || value is num || value is bool) {
        result[entry.key] = value;
      }
    }
    return result;
  }

  Map<String, dynamic> _keyValueArrayToObject(dynamic source) {
    if (source is! List) {
      return const <String, dynamic>{};
    }

    final result = <String, dynamic>{};
    for (final item in source) {
      final map = _coerceMap(item);
      if (map.isEmpty) {
        continue;
      }
      final key = _pick(map, ['name', 'key', 'field'])?.toString().trim();
      final value = _pick(map, ['value', 'val', 'content']);
      if (key == null || key.isEmpty || value == null) {
        continue;
      }
      result[key] = value;
    }
    return result;
  }

  Map<String, dynamic> _coerceMap(dynamic source) {
    if (source is Map<String, dynamic>) {
      return source;
    }
    if (source is Map) {
      return source.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  String _randomTraceId() {
    final millis = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final randomPart =
        _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '$millis$randomPart';
  }
}

class _NormalizedUploadPolicy {
  const _NormalizedUploadPolicy({
    required this.host,
    required this.key,
    required this.downloadUrl,
    required this.fields,
    required this.headers,
  });

  final String host;
  final String key;
  final String? downloadUrl;
  final Map<String, dynamic> fields;
  final Map<String, dynamic> headers;
}
