import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models/drive_material.dart';
import 'models/user_profile.dart';

class PincoApiClient {
  PincoApiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static final _random = Random();

  final http.Client _httpClient;

  Future<UserProfile> getUserInfo(String cookie) async {
    final data = await _postAction(
      actionName: 'GetV1UsersInfo',
      cookie: cookie,
      payload: <String, dynamic>{},
    );

    if (data is! Map<String, dynamic>) {
      throw const FormatException('Missing user data.');
    }

    return UserProfile.fromApi(data);
  }

  Future<List<DriveMaterial>> getRootMaterials({
    required String cookie,
    int page = 0,
    int size = 50,
  }) async {
    final data = await _postAction(
      actionName: 'GetV1DriveMaterials',
      cookie: cookie,
      payload: <String, dynamic>{
        'keyword': '',
        'size': size,
        'tagName': 'resource',
        'page': page,
        'folderId': '0',
      },
    );

    final rawList = _extractList(data);
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(DriveMaterial.fromApi)
        .toList(growable: false);
  }

  Future<dynamic> _postAction({
    required String actionName,
    required String cookie,
    required Map<String, dynamic> payload,
  }) async {
    final uri = Uri.parse(
      'https://pinco.seewo.com/teacher/api.json?actionName=$actionName',
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
        'Origin': 'https://pinco.seewo.com',
        'Referer': 'https://pinco.seewo.com/teacher/main/drive/resource',
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

  dynamic _pick(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        return map[key];
      }
    }
    return null;
  }

  String _randomTraceId() {
    final millis = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final randomPart =
        _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '$millis$randomPart';
  }
}
