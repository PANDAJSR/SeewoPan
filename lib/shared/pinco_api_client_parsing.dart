part of 'pinco_api_client.dart';

extension PincoApiClientParsingExtension on PincoApiClient {
  Future<dynamic> _postAction({
    required String actionName,
    required String cookie,
    required Map<String, dynamic> payload,
  }) async {
    final uri = Uri.parse(
      '${PincoApiClient._baseUrl}/teacher/api.json?actionName=$actionName',
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
        'Origin': PincoApiClient._origin,
        'Referer': PincoApiClient._referer,
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
        (_isOssEndpoint(genericUrl)
            ? genericUrl!
            : PincoApiClient._defaultOssHost);

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
    final randomPart = PincoApiClient._random
        .nextInt(1 << 32)
        .toRadixString(16)
        .padLeft(8, '0');
    return '$millis$randomPart';
  }
}
