part of 'home_shell_page.dart';

extension _HomeShellDownloads on _HomeShellPageState {
  Future<void> _selectDownloadDirectory() async {
    final initialDirectory =
        _downloadDirectory.trim().isEmpty ? null : _downloadDirectory;
    final selected = await getDirectoryPath(initialDirectory: initialDirectory);

    if (selected == null || selected.trim().isEmpty || !mounted) {
      return;
    }
    await _saveDownloadDirectory(selected.trim());
  }

  Future<void> _resetDownloadDirectory() async {
    final defaultPath = await resolveDefaultDownloadDirectoryPath();
    await _saveDownloadDirectory(defaultPath.trim());
  }

  Future<int> _enqueueDownloadMaterials(List<DriveMaterial> materials) async {
    if (materials.isEmpty || !mounted) {
      return 0;
    }

    final isReady = await _ensureDownloadDirectoryReady(interactive: true);
    if (!mounted) {
      return 0;
    }
    if (!isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未授予下载目录权限，已取消下载入队。')),
      );
      return 0;
    }

    final resolvedMaterials = await _resolveDownloadNameConflicts(materials);
    if (!mounted || resolvedMaterials.isEmpty) {
      return 0;
    }

    await _downloadTaskManager.enqueueMaterials(resolvedMaterials);
    return resolvedMaterials.length;
  }

  Future<bool> _ensureDownloadDirectoryReady({
    required bool interactive,
  }) async {
    final current = _downloadDirectory.trim();
    if (current.isNotEmpty) {
      final writable = await _isWritableDirectory(current);
      if (writable) {
        return true;
      }
    }

    if (!interactive || !mounted) {
      return false;
    }

    final fallback = await resolveDefaultDownloadDirectoryPath();
    final initialDirectory = current.isNotEmpty
        ? current
        : (fallback.trim().isEmpty ? null : fallback.trim());
    final selected = await getDirectoryPath(initialDirectory: initialDirectory);
    final normalized = selected?.trim() ?? '';
    if (normalized.isEmpty || !mounted) {
      return false;
    }

    await _saveDownloadDirectory(normalized);
    return _isWritableDirectory(normalized);
  }

  Future<bool> _isWritableDirectory(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return false;
    }

    try {
      final directory = Directory(normalized);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final probe = File(p.join(directory.path, '.seewopan_write_probe'));
      await probe.writeAsString('ok', flush: true);
      if (await probe.exists()) {
        await probe.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<DriveMaterial>> _resolveDownloadNameConflicts(
    List<DriveMaterial> materials,
  ) async {
    final resolved = <DriveMaterial>[];
    final plannedPaths = <String>{};
    for (final material in materials) {
      final targetName = await _resolveDownloadTargetName(
        originalName: material.name,
        plannedPaths: plannedPaths,
      );
      if (targetName == null) {
        continue;
      }

      final targetPath = p.join(_downloadDirectory, targetName);
      plannedPaths.add(targetPath);
      if (targetName == material.name) {
        resolved.add(material);
        continue;
      }

      resolved.add(
        DriveMaterial(
          id: material.id,
          folderId: material.folderId,
          name: targetName,
          size: material.size,
          mimeType: material.mimeType,
          fileKey: material.fileKey,
          downloadUrl: material.downloadUrl,
          createdAt: material.createdAt,
          updatedAt: material.updatedAt,
          isFolder: material.isFolder,
        ),
      );
    }
    return resolved;
  }

  Future<String?> _resolveDownloadTargetName({
    required String originalName,
    required Set<String> plannedPaths,
  }) async {
    final sanitizedOriginal = _sanitizeDownloadFileName(originalName);
    final defaultPath = p.join(_downloadDirectory, sanitizedOriginal);
    final hasConflict =
        plannedPaths.contains(defaultPath) || await File(defaultPath).exists();
    if (!hasConflict) {
      return sanitizedOriginal;
    }
    if (!mounted) {
      return null;
    }

    final action =
        await _showDuplicateDownloadDialog(fileName: sanitizedOriginal);
    if (!mounted ||
        action == null ||
        action == _DuplicateDownloadAction.cancel) {
      return null;
    }
    if (action == _DuplicateDownloadAction.overwrite) {
      return sanitizedOriginal;
    }

    return _pickUniqueDownloadName(
      baseName: sanitizedOriginal,
      plannedPaths: plannedPaths,
    );
  }

  Future<String> _pickUniqueDownloadName({
    required String baseName,
    required Set<String> plannedPaths,
  }) async {
    final ext = p.extension(baseName);
    final stem = ext.isEmpty
        ? baseName
        : baseName.substring(0, baseName.length - ext.length);
    var index = 1;
    while (true) {
      final candidate = '$stem - $index$ext';
      final candidatePath = p.join(_downloadDirectory, candidate);
      final exists = plannedPaths.contains(candidatePath) ||
          await File(candidatePath).exists();
      if (!exists) {
        return candidate;
      }
      index += 1;
    }
  }

  String _sanitizeDownloadFileName(String fileName) {
    final normalizedName =
        fileName.trim().isEmpty ? 'unnamed' : fileName.trim();
    return normalizedName
        .replaceAll('\\', '_')
        .replaceAll('/', '_')
        .replaceAll(':', '_')
        .replaceAll('*', '_')
        .replaceAll('?', '_')
        .replaceAll('"', '_')
        .replaceAll('<', '_')
        .replaceAll('>', '_')
        .replaceAll('|', '_');
  }

  Future<_DuplicateDownloadAction?> _showDuplicateDownloadDialog({
    required String fileName,
  }) {
    return showDialog<_DuplicateDownloadAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('发现同名文件'),
          content: Text('文件「$fileName」已存在，请选择处理方式。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _DuplicateDownloadAction.cancel,
              ),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _DuplicateDownloadAction.overwrite,
              ),
              child: const Text('覆盖'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _DuplicateDownloadAction.keepBoth,
              ),
              child: const Text('同时保留'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveDownloadDirectory(String value) async {
    final normalized = value.trim();
    if (normalized == _downloadDirectory) {
      return;
    }

    _setDownloadDirectory(normalized);

    final prefs = await SharedPreferences.getInstance();
    if (normalized.isEmpty) {
      await prefs.remove(_HomeShellPageState._downloadDirectoryStorageKey);
      return;
    }
    await prefs.setString(
      _HomeShellPageState._downloadDirectoryStorageKey,
      normalized,
    );
  }
}

enum _DuplicateDownloadAction {
  keepBoth,
  overwrite,
  cancel,
}
