import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models/drive_material.dart';
import 'models/user_profile.dart';

class PincoApiClient {
  PincoApiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static final _random = Random();
  static const String _baseUrl = 'https://pinco.seewo.com';

  final http.Client _httpClient;
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
