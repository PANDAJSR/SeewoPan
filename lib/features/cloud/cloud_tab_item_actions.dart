part of 'cloud_tab.dart';

enum _ItemMenuAction {
  select,
  download,
  share,
  move,
  rename,
  copyName,
  copyDownloadUrl,
  delete,
}

extension _CloudTabItemActionsExtension on _CloudTabState {
  Future<void> _showItemContextMenu(Offset position, DriveMaterial item) async {
    if (item.isVirtual) {
      return;
    }

    final selected = await showMenu<_ItemMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(
          value: _ItemMenuAction.select,
          child: Text('选择'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _ItemMenuAction.rename,
          child: Text('重命名'),
        ),
        const PopupMenuItem(
          value: _ItemMenuAction.move,
          child: Text('移动到...'),
        ),
        if (!item.isFolder)
          const PopupMenuItem(
            value: _ItemMenuAction.download,
            child: Text('下载'),
          ),
        const PopupMenuItem(
          value: _ItemMenuAction.share,
          child: Text('分享...'),
        ),
        const PopupMenuItem(
          value: _ItemMenuAction.copyName,
          child: Text('复制文件名'),
        ),
        if (!item.isFolder)
          const PopupMenuItem(
            value: _ItemMenuAction.copyDownloadUrl,
            child: Text('复制下载链接'),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _ItemMenuAction.delete,
          child: Text(item.isFolder ? '删除文件夹' : '删除文件'),
        ),
      ],
    );

    if (selected == null || !mounted) {
      return;
    }

    switch (selected) {
      case _ItemMenuAction.select:
        _enterSelectionMode(initialItem: item);
        break;
      case _ItemMenuAction.rename:
        await _renameItem(item);
        break;
      case _ItemMenuAction.move:
        await _moveItems([item]);
        break;
      case _ItemMenuAction.download:
        await _downloadItems([item]);
        break;
      case _ItemMenuAction.share:
        await _shareItem(item);
        break;
      case _ItemMenuAction.copyName:
        await _copyText(item.name, '已复制文件名');
        break;
      case _ItemMenuAction.copyDownloadUrl:
        final downloadUrl = _buildDownloadUrl(item);
        if (downloadUrl == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到可用下载链接。')),
          );
          return;
        }
        await _copyText(downloadUrl, '已复制下载链接');
        break;
      case _ItemMenuAction.delete:
        await _deleteItem(item);
        break;
    }
  }

  Future<void> _downloadSelectedItems() async {
    if (_selectedMaterialIds.isEmpty || _isLoading) {
      return;
    }

    final selectedItems = _materials
        .where((item) => _selectedMaterialIds.contains(item.id))
        .toList(growable: false);
    if (selectedItems.isEmpty) {
      _exitSelectionMode();
      return;
    }
    await _downloadItems(selectedItems);
  }

  Future<void> _downloadItems(List<DriveMaterial> items) async {
    if (items.isEmpty || !mounted) {
      return;
    }

    final files = items.where((item) => !item.isFolder).toList(growable: false);
    final skippedCount = items.length - files.length;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件夹暂不支持直接下载，请先进入文件夹选择文件。')),
      );
      return;
    }

    final addedCount = await widget.onDownloadMaterials(files);
    if (!mounted) {
      return;
    }

    final canceledCount = files.length - addedCount;
    final fragments = <String>[];
    if (addedCount > 0) {
      fragments.add('已添加 $addedCount 个下载任务');
    }
    if (skippedCount > 0) {
      fragments.add('已跳过 $skippedCount 个文件夹');
    }
    if (canceledCount > 0) {
      fragments.add('已取消 $canceledCount 个重名文件');
    }
    final message = fragments.isEmpty ? '未添加下载任务。' : '${fragments.join('，')}。';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    if (addedCount > 0) {
      widget.onOpenTransferTab();
    }
  }

  String? _buildDownloadUrl(DriveMaterial item) {
    final rawDownloadUrl = item.downloadUrl?.trim();
    if (rawDownloadUrl != null && rawDownloadUrl.isNotEmpty) {
      return rawDownloadUrl;
    }

    if (item.id.trim().isEmpty) {
      return null;
    }

    return widget.apiClient.buildMaterialDownloadUrl(item.id);
  }

  Future<void> _copyText(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _renameItem(DriveMaterial item) async {
    if (item.isVirtual) {
      return;
    }

    final renamed = await _showRenameDialog(item.name);
    if (renamed == null || !mounted) {
      return;
    }

    final currentName = item.name.trim();
    final newName = renamed.trim();
    if (newName == currentName) {
      return;
    }

    try {
      await widget.apiClient.renameMaterial(
        cookie: widget.cookie,
        materialId: item.id,
        name: newName,
      );

      if (!mounted) {
        return;
      }

      await _loadMaterials(forceRefresh: true);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('重命名成功。')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重命名失败：$error')),
      );
    }
  }

  Future<void> _createFolder() async {
    final folderName = await _showCreateFolderDialog();
    if (folderName == null || !mounted) {
      return;
    }

    final normalizedName = folderName.trim();
    if (normalizedName.isEmpty) {
      return;
    }

    try {
      await widget.apiClient.createFolder(
        cookie: widget.cookie,
        name: normalizedName,
        parentFolderId: _currentFolderId,
      );

      if (!mounted) {
        return;
      }
      await _loadMaterials(forceRefresh: true);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件夹创建成功。')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新建文件夹失败：$error')),
      );
    }
  }

  Future<void> _deleteItem(DriveMaterial item) async {
    if (item.isVirtual) {
      return;
    }

    final confirmed = await _showDeleteConfirmDialog(item);
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await widget.apiClient.deleteMaterials(
        cookie: widget.cookie,
        materialIds: [item.id],
      );

      if (!mounted) {
        return;
      }
      await _loadMaterials(forceRefresh: true);
      if (!mounted) {
        return;
      }
      _selectedMaterialIds = <String>{};
      _isSelectionMode = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(item.isFolder ? '文件夹已删除。' : '文件已删除。')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$error')),
      );
    }
  }

  Future<void> _deleteSelectedItems() async {
    if (_selectedMaterialIds.isEmpty || _isLoading) {
      return;
    }

    final selectedIds = _materials
        .where((item) => _selectedMaterialIds.contains(item.id))
        .where((item) => !item.isVirtual)
        .map((item) => item.id)
        .toList(growable: false);
    if (selectedIds.isEmpty) {
      _exitSelectionMode();
      return;
    }

    final confirmed = await _showBatchDeleteConfirmDialog(selectedIds.length);
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await widget.apiClient.deleteMaterials(
        cookie: widget.cookie,
        materialIds: selectedIds,
      );

      if (!mounted) {
        return;
      }
      await _loadMaterials(forceRefresh: true);
      if (!mounted) {
        return;
      }
      _selectedMaterialIds = <String>{};
      _isSelectionMode = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 ${selectedIds.length} 项。')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量删除失败：$error')),
      );
    }
  }

  Future<void> _moveSelectedItems() async {
    if (_selectedMaterialIds.isEmpty || _isLoading) {
      return;
    }

    final selectedItems = _materials
        .where((item) => _selectedMaterialIds.contains(item.id))
        .where((item) => !item.isVirtual)
        .toList(growable: false);
    if (selectedItems.isEmpty) {
      _exitSelectionMode();
      return;
    }

    await _moveItems(selectedItems);
  }

  Future<void> _createFolderWithSelectedItems() async {
    if (_selectedMaterialIds.isEmpty || _isLoading) {
      return;
    }

    final selectedItems = _materials
        .where((item) => _selectedMaterialIds.contains(item.id))
        .where((item) => !item.isVirtual)
        .toList(growable: false);
    if (selectedItems.isEmpty) {
      _exitSelectionMode();
      return;
    }

    final folderName = await _showCreateFolderDialog();
    if (folderName == null || !mounted) {
      return;
    }

    final normalizedName = folderName.trim();
    if (normalizedName.isEmpty) {
      return;
    }

    final materialIds = selectedItems
        .map((item) => item.id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (materialIds.isEmpty) {
      return;
    }

    try {
      final newFolderId = await widget.apiClient.createFolder(
        cookie: widget.cookie,
        name: normalizedName,
        parentFolderId: _currentFolderId,
      );

      await widget.apiClient.moveMaterials(
        cookie: widget.cookie,
        materialIds: materialIds,
        targetFolderId: newFolderId,
      );

      if (!mounted) {
        return;
      }
      await _loadMaterials(forceRefresh: true);
      if (!mounted) {
        return;
      }

      _selectedMaterialIds = <String>{};
      _isSelectionMode = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已新建文件夹「$normalizedName」，并移动 ${materialIds.length} 项。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('用所选项目新建文件夹失败：$error')),
      );
    }
  }

  Future<void> _moveItems(List<DriveMaterial> items) async {
    final movableItems =
        items.where((item) => !item.isVirtual).toList(growable: false);
    if (movableItems.isEmpty || _isLoading) {
      return;
    }

    final blockedFolderIds = movableItems
        .where((item) => item.isFolder)
        .map((item) => item.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final target = await _showMoveTargetFolderDialog(
      initialPath: _folderPath,
      blockedFolderIds: blockedFolderIds,
    );
    if (target == null || !mounted) {
      return;
    }

    final sourceFolderId = _currentFolderId;
    if (target.folderId == sourceFolderId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目标目录与当前目录一致，无需移动。')),
      );
      return;
    }

    final materialIds = movableItems
        .map((item) => item.id)
        .where((id) => id.trim().isNotEmpty)
        .toList();
    if (materialIds.isEmpty) {
      return;
    }

    try {
      await widget.apiClient.moveMaterials(
        cookie: widget.cookie,
        materialIds: materialIds,
        targetFolderId: target.folderId,
      );

      if (!mounted) {
        return;
      }
      await _loadMaterials(forceRefresh: true);
      if (!mounted) {
        return;
      }

      _selectedMaterialIds = <String>{};
      _isSelectionMode = false;
      final movedCount = materialIds.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已移动 $movedCount 项到「${target.name}」。'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移动失败：$error')),
      );
    }
  }
}
