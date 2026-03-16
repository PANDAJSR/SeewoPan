part of 'cloud_tab.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _CloudTabSelectionExtension on _CloudTabState {
  int get _selectedCount => _selectedMaterialIds.length;

  void _enterSelectionMode({DriveMaterial? initialItem}) {
    if (_isLoading || _materials.isEmpty) {
      return;
    }

    setState(() {
      _isSelectionMode = true;
      if (initialItem != null) {
        _selectedMaterialIds = <String>{
          ..._selectedMaterialIds,
          initialItem.id
        };
      }
    });
  }

  void _exitSelectionMode() {
    if (!_isSelectionMode) {
      return;
    }

    setState(() {
      _isSelectionMode = false;
      _selectedMaterialIds = <String>{};
    });
  }

  void _toggleMaterialSelection(String materialId) {
    if (!_isSelectionMode) {
      return;
    }

    setState(() {
      if (_selectedMaterialIds.contains(materialId)) {
        _selectedMaterialIds = Set<String>.from(_selectedMaterialIds)
          ..remove(materialId);
      } else {
        _selectedMaterialIds = Set<String>.from(_selectedMaterialIds)
          ..add(materialId);
      }
      if (_selectedMaterialIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _syncSelectionAfterReload(List<DriveMaterial> materials) {
    final availableIds = materials.map((item) => item.id).toSet();
    final retained = _selectedMaterialIds.where(availableIds.contains).toSet();

    _selectedMaterialIds = retained;
    if (retained.isEmpty) {
      _isSelectionMode = false;
    }
  }
}
