part of 'cloud_tab.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _CloudTabLoadingExtension on _CloudTabState {
  Future<void> _tryLoadIfReady() async {
    if (widget.isLoadingCookie || widget.cookie.trim().isEmpty || _isLoading) {
      return;
    }
    await _loadMaterials();
  }

  Future<void> _loadMaterials({bool forceRefresh = false}) async {
    final folderId = _currentFolderId;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await widget.apiClient.getMaterials(
        cookie: widget.cookie.trim(),
        folderId: folderId,
        forceRefresh: forceRefresh,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _materials = items;
        _syncSelectionAfterReload(items);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _error = '加载文件列表失败：$error';
      });
    }
  }

  String get _currentFolderId =>
      _folderPath.isEmpty ? '0' : _folderPath.last.folderId;

  Future<void> _goBack() async {
    if (_folderPath.isEmpty || _isLoading) {
      return;
    }

    setState(() {
      _folderPath = _folderPath.sublist(0, _folderPath.length - 1);
      _isSelectionMode = false;
      _selectedMaterialIds = <String>{};
    });
    await _loadMaterials();
  }

  Future<void> _handleItemTap(DriveMaterial item) async {
    if (_isLoading) {
      return;
    }

    if (_isSelectionMode) {
      _toggleMaterialSelection(item.id);
      return;
    }

    if (item.isFolder) {
      setState(() {
        _folderPath = [
          ..._folderPath,
          _FolderEntry(folderId: item.folderId, name: item.name),
        ];
        _isSelectionMode = false;
        _selectedMaterialIds = <String>{};
      });
      await _loadMaterials();
      return;
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('文件预览功能开发中。')),
    );
  }

  Future<void> _pickAndUploadFiles() async {
    List<XFile> selectedFiles = const [];
    try {
      selectedFiles = await openFiles();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开文件选择器失败：$error')),
      );
      return;
    }

    if (selectedFiles.isEmpty || !mounted) {
      return;
    }

    final files = <UploadSourceFile>[];
    for (final file in selectedFiles) {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        continue;
      }
      files.add(
        UploadSourceFile(
          name: file.name,
          bytes: bytes,
          parentFolderId: _currentFolderId,
        ),
      );
    }
    if (!mounted) {
      return;
    }

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未读取到文件内容，请重试。')),
      );
      return;
    }

    await widget.onUploadFiles(files);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加 ${files.length} 个上传任务。')),
    );
    widget.onOpenTransferTab();
  }
}
