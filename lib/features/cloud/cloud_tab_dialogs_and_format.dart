part of 'cloud_tab.dart';

class _FolderEntry {
  const _FolderEntry({
    required this.folderId,
    required this.name,
    this.tagName = _driveMaterialsTagName,
  });

  final String folderId;
  final String name;
  final String tagName;
}

class _MoveTargetFolderResult {
  const _MoveTargetFolderResult({
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

  Future<_MoveTargetFolderResult?> _showMoveTargetFolderDialog({
    required List<_FolderEntry> initialPath,
    Set<String> blockedFolderIds = const <String>{},
  }) {
    final blocked = blockedFolderIds;
    var path = List<_FolderEntry>.from(initialPath);
    var loading = false;
    var hasLoaded = false;
    String? errorText;
    List<DriveMaterial> childFolders = const [];

    Future<void> loadFolders(StateSetter setDialogState) async {
      setDialogState(() {
        loading = true;
        errorText = null;
      });

      try {
        final folderId = path.isEmpty ? '0' : path.last.folderId;
        final folders = await widget.apiClient.getMaterials(
          cookie: widget.cookie.trim(),
          folderId: folderId,
          tagName: 'folder',
          forceRefresh: true,
        );

        if (!mounted) {
          return;
        }

        setDialogState(() {
          loading = false;
          hasLoaded = true;
          childFolders = folders.where((item) => item.isFolder).toList();
        });
      } catch (error) {
        setDialogState(() {
          loading = false;
          hasLoaded = true;
          errorText = '加载目录失败：$error';
        });
      }
    }

    return showDialog<_MoveTargetFolderResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            if (!loading && !hasLoaded) {
              loadFolders(setDialogState);
            }

            final currentFolderId = path.isEmpty ? '0' : path.last.folderId;
            final currentFolderName = path.isEmpty ? '根目录' : path.last.name;
            final canSubmit = !loading && !blocked.contains(currentFolderId);
            final pathLabels = <String>['根目录', ...path.map((e) => e.name)];

            return AlertDialog(
              title: const Text('选择目标目录'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前目录：${pathLabels.join(' / ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: loading || path.isEmpty
                              ? null
                              : () {
                                  setDialogState(() {
                                    path = path.sublist(0, path.length - 1);
                                    hasLoaded = false;
                                    childFolders = const [];
                                  });
                                },
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('上级'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: loading || path.isEmpty
                              ? null
                              : () {
                                  setDialogState(() {
                                    path = const [];
                                    hasLoaded = false;
                                    childFolders = const [];
                                  });
                                },
                          icon: const Icon(Icons.home_outlined),
                          label: const Text('根目录'),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: loading
                              ? null
                              : () => loadFolders(setDialogState),
                          tooltip: '刷新目录',
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: Theme.of(dialogContext)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: Theme.of(dialogContext).colorScheme.error,
                            ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (loading)
                      const SizedBox(
                        height: 180,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (childFolders.isEmpty)
                      const SizedBox(
                        height: 120,
                        child: Center(child: Text('此目录下暂无子文件夹。')),
                      )
                    else
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: childFolders.length,
                            itemBuilder: (context, index) {
                              final folder = childFolders[index];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.folder_outlined),
                                title: Text(folder.name),
                                trailing:
                                    const Icon(Icons.chevron_right_rounded),
                                onTap: () {
                                  setDialogState(() {
                                    path = [
                                      ...path,
                                      _FolderEntry(
                                        folderId: folder.id,
                                        name: folder.name,
                                      ),
                                    ];
                                    hasLoaded = false;
                                    childFolders = const [];
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    if (!canSubmit) ...[
                      const SizedBox(height: 8),
                      const Text('不能将文件夹移动到自身目录。'),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: canSubmit
                      ? () {
                          Navigator.of(dialogContext).pop(
                            _MoveTargetFolderResult(
                              folderId: currentFolderId,
                              name: currentFolderName,
                            ),
                          );
                        }
                      : null,
                  child: const Text('移动到此处'),
                ),
              ],
            );
          },
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
