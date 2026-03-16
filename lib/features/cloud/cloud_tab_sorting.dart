part of 'cloud_tab.dart';

// ignore_for_file: invalid_use_of_protected_member

enum _MaterialSortOption {
  nameAsc,
  nameDesc,
  sizeAsc,
  sizeDesc,
  updatedAtDesc,
  updatedAtAsc,
}

extension _MaterialSortOptionLabels on _MaterialSortOption {
  String get label {
    switch (this) {
      case _MaterialSortOption.nameAsc:
        return '按名称（升序）';
      case _MaterialSortOption.nameDesc:
        return '按名称（降序）';
      case _MaterialSortOption.sizeAsc:
        return '按大小（升序）';
      case _MaterialSortOption.sizeDesc:
        return '按大小（降序）';
      case _MaterialSortOption.updatedAtDesc:
        return '按修改日期（最新）';
      case _MaterialSortOption.updatedAtAsc:
        return '按修改日期（最旧）';
    }
  }
}

extension _CloudTabSortingExtension on _CloudTabState {
  void _handleSortOptionChanged(_MaterialSortOption option) {
    if (_sortOption == option) {
      return;
    }

    setState(() {
      _sortOption = option;
      _materials = _sortMaterials(_materials);
    });
  }

  List<DriveMaterial> _sortMaterials(List<DriveMaterial> source) {
    final sorted = List<DriveMaterial>.from(source);
    sorted.sort(_compareMaterial);
    return sorted;
  }

  int _compareMaterial(DriveMaterial left, DriveMaterial right) {
    final folderFirst = _compareFolder(left, right);
    if (folderFirst != 0) {
      return folderFirst;
    }

    late final int result;
    switch (_sortOption) {
      case _MaterialSortOption.nameAsc:
        result = _compareName(left, right);
      case _MaterialSortOption.nameDesc:
        result = _compareName(right, left);
      case _MaterialSortOption.sizeAsc:
        result = left.size.compareTo(right.size);
      case _MaterialSortOption.sizeDesc:
        result = right.size.compareTo(left.size);
      case _MaterialSortOption.updatedAtDesc:
        result = _compareUpdatedAt(right, left);
      case _MaterialSortOption.updatedAtAsc:
        result = _compareUpdatedAt(left, right);
    }

    if (result != 0) {
      return result;
    }
    return _compareName(left, right);
  }

  int _compareFolder(DriveMaterial left, DriveMaterial right) {
    if (left.isFolder == right.isFolder) {
      return 0;
    }
    return left.isFolder ? -1 : 1;
  }

  int _compareName(DriveMaterial left, DriveMaterial right) {
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  }

  int _compareUpdatedAt(DriveMaterial left, DriveMaterial right) {
    final leftTime = _resolveUpdatedTime(left);
    final rightTime = _resolveUpdatedTime(right);
    if (leftTime == null && rightTime == null) {
      return 0;
    }
    if (leftTime == null) {
      return 1;
    }
    if (rightTime == null) {
      return -1;
    }
    return leftTime.compareTo(rightTime);
  }

  DateTime? _resolveUpdatedTime(DriveMaterial item) {
    final updated = item.updatedAt?.trim();
    if (updated != null && updated.isNotEmpty) {
      final parsed = _parseDateTime(updated);
      if (parsed != null) {
        return parsed;
      }
    }

    final created = item.createdAt?.trim();
    if (created != null && created.isNotEmpty) {
      return _parseDateTime(created);
    }

    return null;
  }
}
