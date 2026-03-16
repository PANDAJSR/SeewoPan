part of 'cloud_tab.dart';

class _FolderEntry {
  const _FolderEntry({
    required this.folderId,
    required this.name,
  });

  final String folderId;
  final String name;
}

extension _CloudTabDialogsAndFormatExtension on _CloudTabState {
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

  Future<bool?> _showDeleteConfirmDialog(DriveMaterial item) {
    final itemType = item.isFolder ? '文件夹' : '文件';
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('删除$itemType'),
          content: Text('确认删除「${item.name}」吗？此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showBatchDeleteConfirmDialog(int count) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('批量删除'),
          content: Text('确认删除已选择的 $count 项吗？此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              child: const Text('删除'),
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
