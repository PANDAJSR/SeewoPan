import 'package:file_icon/file_icon.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/models/drive_material.dart';
import '../../shared/pinco_api_client.dart';
import '../transfer/upload_task_manager.dart';

part 'cloud_tab_loading.dart';
part 'cloud_tab_item_actions.dart';
part 'cloud_tab_dialogs_and_format.dart';

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
}
