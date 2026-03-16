class DriveMaterialsCapacity {
  const DriveMaterialsCapacity({
    required this.capacity,
    required this.used,
    required this.usedDetail,
  });

  final int capacity;
  final int used;
  final List<DriveAppUsage> usedDetail;

  factory DriveMaterialsCapacity.fromApi(Map<String, dynamic> raw) {
    final details = (raw['usedDetail'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(DriveAppUsage.fromApi)
        .toList(growable: false);

    return DriveMaterialsCapacity(
      capacity: _parseInt(raw['capacity']),
      used: _parseInt(raw['used']),
      usedDetail: details,
    );
  }
}

class DriveAppUsage {
  const DriveAppUsage({
    required this.appCode,
    required this.appName,
    required this.totalUsed,
  });

  final String appCode;
  final String appName;
  final int totalUsed;

  factory DriveAppUsage.fromApi(Map<String, dynamic> raw) {
    return DriveAppUsage(
      appCode: raw['appCode']?.toString() ?? '',
      appName: raw['appName']?.toString() ?? '',
      totalUsed: _parseInt(raw['totalUsed']),
    );
  }

  String get displayName {
    final normalizedName = appName.trim();
    if (normalizedName.isNotEmpty) {
      return normalizedName;
    }
    final normalizedCode = appCode.trim();
    if (normalizedCode.isNotEmpty) {
      return normalizedCode;
    }
    return '未知应用';
  }
}

int _parseInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
