import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_icon/file_icon.dart';

import '../transfer/upload_task_manager.dart';
import '../../shared/models/drive_material.dart';
import '../../shared/pinco_api_client.dart';

class CloudTab extends StatefulWidget {
  const CloudTab({
    super.key,
    required this.cookie,
    required this.isLoadingCookie,
    required this.apiClient,
    required this.onUploadFiles,
    required this.onOpenTransferTab,
  });

  final String cookie;
  final bool isLoadingCookie;
  final PincoApiClient apiClient;
  final Future<void> Function(List<UploadSourceFile> files) onUploadFiles;
  final VoidCallback onOpenTransferTab;

  @override
  State<CloudTab> createState() => _CloudTabState();
}

class _CloudTabState extends State<CloudTab> {
  bool _isLoading = false;
  String? _error;
  List<DriveMaterial> _materials = const [];
  List<_FolderEntry> _folderPath = const [];

  @override
  void initState() {
    super.initState();
    _tryLoadIfReady();
  }

  @override
  void didUpdateWidget(covariant CloudTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cookie != widget.cookie) {
      _materials = const [];
      _error = null;
      _folderPath = const [];
      _tryLoadIfReady();
    }
  }

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

  @override
  Widget build(BuildContext context) {
    if (widget.isLoadingCookie) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.cookie.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('请先到“我的”选项卡填写并保存 Cookie。'),
        ),
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _loadMaterials(forceRefresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text(
                  '云盘文件',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  onPressed: _isLoading ? null : _pickAndUploadFiles,
                  icon: const Icon(Icons.file_upload_outlined),
                  tooltip: '上传文件',
                ),
                IconButton(
                  onPressed: _isLoading ? null : _createFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  tooltip: '新建文件夹',
                ),
                IconButton(
                  onPressed: _isLoading
                      ? null
                      : () => _loadMaterials(forceRefresh: true),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  tooltip: '刷新',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildFolderPath(context),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
            if (!_isLoading && _materials.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: Text('当前目录暂无文件。')),
              ),
            ..._materials.map(
              (item) => Card(
                clipBehavior: Clip.antiAlias,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (details) =>
                      _showItemContextMenu(details.globalPosition, item),
                  onLongPressStart: (details) =>
                      _showItemContextMenu(details.globalPosition, item),
                  child: ListTile(
                    leading: item.isFolder
                        ? const Icon(Icons.folder_outlined)
                        : FileIcon(item.name, size: 24),
                    title: Text(item.name),
                    subtitle: Text(_buildSubtitle(item)),
                    trailing: item.isFolder
                        ? const Icon(Icons.chevron_right_rounded)
                        : null,
                    onTap: () => _handleItemTap(item),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildSubtitle(DriveMaterial item) {
    final parts = <String>[];
    if (!item.isFolder) {
      parts.add(_formatBytes(item.size));
    }
    if (item.updatedAt?.isNotEmpty == true) {
      parts.add('更新于 ${_formatUpdatedAt(item.updatedAt!)}');
    }
    return parts.join(' · ');
  }

  String _formatUpdatedAt(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return raw;
    }

    final parsed = _parseDateTime(normalized);
    if (parsed == null) {
      return raw;
    }

    final local = parsed.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  DateTime? _parseDateTime(String value) {
    final direct = DateTime.tryParse(value);
    if (direct != null) {
      return direct;
    }

    final timestamp = int.tryParse(value);
    if (timestamp == null) {
      return null;
    }

    final length = value.startsWith('-') ? value.length - 1 : value.length;
    if (length <= 10) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    }
    if (length == 12) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp * 10);
    }
    if (length == 13) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    if (length == 16) {
      return DateTime.fromMicrosecondsSinceEpoch(timestamp);
    }
    if (length == 19) {
      return DateTime.fromMicrosecondsSinceEpoch(timestamp ~/ 1000);
    }
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  String get _currentFolderId =>
      _folderPath.isEmpty ? '0' : _folderPath.last.folderId;

  Widget _buildFolderPath(BuildContext context) {
    final pathLabels = <String>['根目录', ..._folderPath.map((e) => e.name)];
    return Row(
      children: [
        IconButton(
          onPressed: _folderPath.isNotEmpty && !_isLoading ? _goBack : null,
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回上级',
        ),
        Expanded(
          child: Text(
            pathLabels.join(' / '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Future<void> _goBack() async {
    if (_folderPath.isEmpty || _isLoading) {
      return;
    }

    setState(() {
      _folderPath = _folderPath.sublist(0, _folderPath.length - 1);
    });
    await _loadMaterials();
  }

  Future<void> _handleItemTap(DriveMaterial item) async {
    if (_isLoading) {
      return;
    }

    if (item.isFolder) {
      setState(() {
        _folderPath = [
          ..._folderPath,
          _FolderEntry(folderId: item.folderId, name: item.name),
        ];
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
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || !mounted) {
      return;
    }

    final files = result.files
        .where((file) => file.bytes != null && file.bytes!.isNotEmpty)
        .map(
          (file) => UploadSourceFile(
            name: file.name,
            bytes: file.bytes!,
            parentFolderId: _currentFolderId,
          ),
        )
        .toList(growable: false);

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

  Future<String?> _showRenameDialog(String initialName) async {
    var renamed = initialName;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('重命名'),
          content: TextFormField(
            initialValue: initialName,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '新名称',
              hintText: '请输入新名称',
            ),
            onChanged: (value) => renamed = value,
            onFieldSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(renamed.trim()),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showCreateFolderDialog() async {
    var folderName = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('新建文件夹'),
          content: TextFormField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '文件夹名称',
              hintText: '请输入文件夹名称',
            ),
            onChanged: (value) => folderName = value,
            onFieldSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(folderName.trim()),
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    const units = ['KB', 'MB', 'GB', 'TB'];
    double value = bytes / 1024;
    var unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }

    return '${value.toStringAsFixed(2)} ${units[unitIndex]}';
  }
}

enum _ItemMenuAction {
  rename,
  copyName,
  copyDownloadUrl,
}

class _FolderEntry {
  const _FolderEntry({
    required this.folderId,
    required this.name,
  });

  final String folderId;
  final String name;
}
