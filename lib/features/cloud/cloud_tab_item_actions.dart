part of 'cloud_tab.dart';

enum _ItemMenuAction {
  rename,
  copyName,
  copyDownloadUrl,
  delete,
}

extension _CloudTabItemActionsExtension on _CloudTabState {
  Future<void> _showItemContextMenu(Offset position, DriveMaterial item) async {
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
          value: _ItemMenuAction.rename,
          child: Text('重命名'),
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
      case _ItemMenuAction.rename:
        await _renameItem(item);
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
}
