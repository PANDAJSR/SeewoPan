class DriveMaterial {
  const DriveMaterial({
    required this.id,
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
    final name = _pick(item, ['name', 'fileName'])?.toString();

    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      throw const FormatException('Invalid material item.');
    }

    final typeValue = _pick(item, ['type', 'materialType'])?.toString();
    final isFolder = _pick(item, ['isFolder']) == true ||
        typeValue?.toLowerCase() == 'folder';

    return DriveMaterial(
      id: id,
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
      isFolder: isFolder,
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
}
