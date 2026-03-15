import 'package:flutter/material.dart';

import '../../shared/models/drive_material.dart';
import '../../shared/pinco_api_client.dart';

class CloudTab extends StatefulWidget {
  const CloudTab({
    super.key,
    required this.cookie,
    required this.isLoadingCookie,
    required this.apiClient,
  });

  final String cookie;
  final bool isLoadingCookie;
  final PincoApiClient apiClient;

  @override
  State<CloudTab> createState() => _CloudTabState();
}

class _CloudTabState extends State<CloudTab> {
  bool _isLoading = false;
  String? _error;
  List<DriveMaterial> _materials = const [];

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
      _tryLoadIfReady();
    }
  }

  Future<void> _tryLoadIfReady() async {
    if (widget.isLoadingCookie || widget.cookie.trim().isEmpty || _isLoading) {
      return;
    }
    await _loadMaterials();
  }

  Future<void> _loadMaterials() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await widget.apiClient.getRootMaterials(
        cookie: widget.cookie.trim(),
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
        onRefresh: _loadMaterials,
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
                  onPressed: _isLoading ? null : _loadMaterials,
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
                child: ListTile(
                  leading: Icon(
                    item.isFolder
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                  ),
                  title: Text(item.name),
                  subtitle: Text(_buildSubtitle(item)),
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
    if (item.mimeType.isNotEmpty && item.mimeType != '-') {
      parts.add(item.mimeType);
    }
    if (item.updatedAt?.isNotEmpty == true) {
      parts.add('更新于 ${item.updatedAt}');
    }
    return parts.join(' · ');
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
