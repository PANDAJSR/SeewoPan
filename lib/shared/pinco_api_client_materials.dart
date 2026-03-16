part of 'pinco_api_client.dart';

class DriveLinkShareResult {
  const DriveLinkShareResult({
    required this.shareId,
    this.password,
  });

  final String shareId;
  final String? password;

  String get shareUrl => '${PincoApiClient._baseUrl}/s/$shareId';
}

extension PincoApiClientMaterialsExtension on PincoApiClient {
  Future<DriveMaterialsCapacity> getDriveMaterialsCapacity({
    required String cookie,
    int type = 1,
    bool forceRefresh = false,
  }) async {
    final normalizedCookie = cookie.trim();
    final cacheKey = '$normalizedCookie::$type';
    if (!forceRefresh) {
      final cached = _materialsCapacityCache[cacheKey];
      if (cached != null) {
        return cached;
      }
    }

    final data = await _postAction(
      actionName: 'GetV1DriveMaterialsCapacity',
      cookie: normalizedCookie,
      payload: <String, dynamic>{'type': type},
    );

    if (data is! Map<String, dynamic>) {
      throw const FormatException('Missing drive materials capacity data.');
    }

    final capacity = DriveMaterialsCapacity.fromApi(data);
    _materialsCapacityCache[cacheKey] = capacity;
    return capacity;
  }

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
    String keyword = '',
    int page = 0,
    int size = 50,
    bool forceRefresh = false,
  }) async {
    return getMaterials(
      cookie: cookie,
      folderId: '0',
      keyword: keyword,
      page: page,
      size: size,
      forceRefresh: forceRefresh,
    );
  }

  Future<List<DriveMaterial>> getMaterials({
    required String cookie,
    required String folderId,
    String keyword = '',
    int page = 0,
    int size = 50,
    String tagName = 'resource,folder',
    bool forceRefresh = false,
  }) async {
    final normalizedCookie = cookie.trim();
    final normalizedKeyword = keyword.trim();
    final cacheKey =
        '$normalizedCookie::$folderId::$page::$size::$tagName::$normalizedKeyword';
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
        'keyword': normalizedKeyword,
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
    return '${PincoApiClient._baseUrl}/server-main/api/v1/drive/materials/download'
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
    _materialsCapacityCache.clear();
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
    _materialsCapacityCache.clear();
  }

  Future<void> moveMaterials({
    required String cookie,
    required List<String> materialIds,
    required String targetFolderId,
  }) async {
    final normalizedCookie = cookie.trim();
    final normalizedMaterialIds = materialIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final normalizedTargetFolderId = targetFolderId.trim();

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
    if (normalizedTargetFolderId.isEmpty) {
      throw ArgumentError.value(
        targetFolderId,
        'targetFolderId',
        'Target folder ID cannot be empty.',
      );
    }

    await _postAction(
      actionName: 'PutV1DriveMaterialsLocations',
      cookie: normalizedCookie,
      payload: <String, dynamic>{
        'resIdList': normalizedMaterialIds,
        'targetFolderId': normalizedTargetFolderId,
      },
    );

    _materialsCache.clear();
    _materialsCapacityCache.clear();
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
    _materialsCapacityCache.clear();
    return folderId;
  }

  Future<DriveLinkShareResult> createDriveLinkShare({
    required String cookie,
    required String resId,
    required int minutes,
    required int shareType,
  }) async {
    final normalizedCookie = cookie.trim();
    final normalizedResId = resId.trim();

    if (normalizedCookie.isEmpty) {
      throw ArgumentError.value(cookie, 'cookie', 'Cookie cannot be empty.');
    }
    if (normalizedResId.isEmpty) {
      throw ArgumentError.value(resId, 'resId', 'Resource ID cannot be empty.');
    }
    if (minutes <= 0 && minutes != -1) {
      throw ArgumentError.value(
        minutes,
        'minutes',
        'Minutes must be positive or -1.',
      );
    }
    if (shareType != 0 && shareType != 1) {
      throw ArgumentError.value(
        shareType,
        'shareType',
        'Share type must be 0 (public) or 1 (private).',
      );
    }

    final data = await _postAction(
      actionName: 'PostV1DriveLinkShare',
      cookie: normalizedCookie,
      payload: <String, dynamic>{
        'resId': normalizedResId,
        'minutes': minutes,
        'shareType': shareType,
      },
    );

    if (data is! Map<String, dynamic>) {
      throw const FormatException('Missing share data.');
    }

    final shareId = _pick(data, ['shareId', 'id'])?.toString().trim();
    if (shareId == null || shareId.isEmpty) {
      throw const FormatException('Missing share id.');
    }

    final passwordRaw = _pick(data, ['password', 'pwd'])?.toString();
    final password = passwordRaw == null || passwordRaw.trim().isEmpty
        ? null
        : passwordRaw.trim();

    return DriveLinkShareResult(
      shareId: shareId,
      password: password,
    );
  }
}
