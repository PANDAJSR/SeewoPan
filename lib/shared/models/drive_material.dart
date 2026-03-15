class DriveMaterial {
  const DriveMaterial({
    required this.id,
    required this.folderId,
    required this.name,
    required this.size,
    required this.mimeType,
    this.fileKey,
    this.downloadUrl,
    this.createdAt,
    this.updatedAt,
    this.isFolder = false,
  });

  final String id;
  final String folderId;
  final String name;
  final int size;
  final String mimeType;
  final String? fileKey;
  final String? downloadUrl;
  final String? createdAt;
  final String? updatedAt;
  final bool isFolder;

  factory DriveMaterial.fromApi(Map<String, dynamic> item) {
    final id = _pick(item, ['id', 'materialId', 'fileId', 'resId'])?.toString();
    final folderId =
        _pick(item, ['folderId', 'id', 'materialId', 'fileId', 'resId'])
            ?.toString();
    final name = _pick(item, ['name', 'fileName'])?.toString();

    if (id == null ||
        id.isEmpty ||
        folderId == null ||
        folderId.isEmpty ||
        name == null ||
        name.isEmpty) {
      throw const FormatException('Invalid material item.');
    }

    return DriveMaterial(
      id: id,
      folderId: folderId,
      name: name,
      size: _toInt(_pick(item, ['size', 'fileSize'])),
      mimeType:
          _pick(item, ['mimeType', 'contentType', 'type'])?.toString() ?? '-',
      fileKey: _pick(item, ['fileKey', 'key'])?.toString(),
      downloadUrl: _pick(item, ['downloadUrl', 'url', 'accessUrl'])?.toString(),
      createdAt:
          _pick(item, ['createdAt', 'createTime', 'gmtCreate'])?.toString(),
      updatedAt:
          _pick(item, ['updatedAt', 'updateTime', 'gmtModified'])?.toString(),
      isFolder: _detectIsFolder(item),
    );
  }

  static dynamic _pick(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        return map[key];
      }
    }
    return null;
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _detectIsFolder(Map<String, dynamic> item) {
    final fileFlag = _pick(item, ['file', 'isFile']);
    if (fileFlag is bool) {
      return !fileFlag;
    }

    final folderFlag = _pick(item, ['folder', 'isFolder']);
    if (folderFlag is bool) {
      return folderFlag;
    }

    final mimeValue = _pick(item, ['mimeType', 'type', 'materialType']);
    if (mimeValue is String) {
      final mime = mimeValue.trim().toLowerCase();
      if (mime == 'folder' || mime == 'directory' || mime == 'dir') {
        return true;
      }
      if (mime == 'resource' || mime == 'file') {
        return false;
      }
      if (mime.contains('folder')) {
        return true;
      }
      if (mime.contains('/')) {
        return false;
      }
    }

    if (mimeValue is num) {
      if (mimeValue == 9) {
        return true;
      }
      if (mimeValue == 99) {
        return false;
      }
    }

    final typeTag = _toInt(_pick(item, ['typeTag']));
    if (typeTag == 1) {
      return true;
    }
    if (typeTag == 255) {
      return false;
    }

    return false;
  }
}
