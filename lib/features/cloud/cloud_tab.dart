import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_icon/file_icon.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/models/drive_material.dart';
import '../../shared/pinco_api_client.dart';
import '../transfer/upload_task_manager.dart';

part 'cloud_tab_loading.dart';
part 'cloud_tab_item_actions.dart';
part 'cloud_tab_item_share.dart';
part 'cloud_tab_dialogs_and_format.dart';
part 'cloud_tab_selection.dart';
part 'cloud_tab_sorting.dart';

class CloudTab extends StatefulWidget {
  const CloudTab({
    super.key,
    required this.cookie,
    required this.isLoadingCookie,
    required this.apiClient,
    required this.onUploadFiles,
    required this.onDownloadMaterials,
    required this.onOpenTransferTab,
    this.enableExternalDrop = true,
  });

  final String cookie;
  final bool isLoadingCookie;
  final PincoApiClient apiClient;
  final Future<void> Function(List<UploadSourceFile> files) onUploadFiles;
  final Future<int> Function(List<DriveMaterial> materials) onDownloadMaterials;
  final VoidCallback onOpenTransferTab;
  final bool enableExternalDrop;

  @override
  State<CloudTab> createState() => _CloudTabState();
}

class _CloudTabState extends State<CloudTab> {
  static const Duration _searchDebounceDuration = Duration(milliseconds: 400);

  bool _isLoading = false;
  String? _error;
  List<DriveMaterial> _materials = const [];
  List<_FolderEntry> _folderPath = const [];
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  String _searchKeyword = '';
  bool _isSearchBarVisible = false;
  bool _isSelectionMode = false;
  Set<String> _selectedMaterialIds = <String>{};
  bool _isDragHovering = false;
  _MaterialSortOption _sortOption = _MaterialSortOption.nameAsc;

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
      _searchKeyword = '';
      _searchController.clear();
      _searchDebounceTimer?.cancel();
      _isSearchBarVisible = false;
      _isSelectionMode = false;
      _selectedMaterialIds = <String>{};
      _tryLoadIfReady();
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounceDuration, () {
      if (!mounted || !_isSearchBarVisible || _isLoading) {
        return;
      }
      unawaited(_applySearch());
    });
  }

  Future<void> _toggleSearchBar() async {
    _searchDebounceTimer?.cancel();

    if (_isSearchBarVisible) {
      setState(() {
        _isSearchBarVisible = false;
      });
      await _clearSearch();
      return;
    }

    setState(() {
      _isSearchBarVisible = true;
    });
  }

  Future<void> _applySearch() async {
    final normalizedKeyword = _searchController.text.trim();
    if (_searchKeyword == normalizedKeyword && _error == null) {
      return;
    }

    setState(() {
      _searchKeyword = normalizedKeyword;
      _isSelectionMode = false;
      _selectedMaterialIds = <String>{};
    });
    await _loadMaterials(forceRefresh: true);
  }

  Future<void> _clearSearch() async {
    if (_searchKeyword.isEmpty && _searchController.text.trim().isEmpty) {
      return;
    }

    _searchController.clear();
    setState(() {
      _searchKeyword = '';
      _isSelectionMode = false;
      _selectedMaterialIds = <String>{};
    });
    await _loadMaterials(forceRefresh: true);
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
      child: DropTarget(
        enable: widget.enableExternalDrop,
        onDragEntered: (_) {
          if (_isDragHovering || !mounted) {
            return;
          }
          setState(() {
            _isDragHovering = true;
          });
        },
        onDragExited: (_) {
          if (!_isDragHovering || !mounted) {
            return;
          }
          setState(() {
            _isDragHovering = false;
          });
        },
        onDragDone: (details) {
          if (_isDragHovering && mounted) {
            setState(() {
              _isDragHovering = false;
            });
          }
          unawaited(_handleDroppedFiles(details.files));
        },
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () => _loadMaterials(forceRefresh: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Text(
                        _isSelectionMode ? '已选择 $_selectedCount 项' : '云盘文件',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Spacer(),
                      if (_isSelectionMode)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: _isLoading || _selectedCount == 0
                                  ? null
                                  : _createFolderWithSelectedItems,
                              icon:
                                  const Icon(Icons.create_new_folder_outlined),
                              tooltip: '用所选项目新建文件夹',
                            ),
                            IconButton(
                              onPressed: _isLoading || _selectedCount == 0
                                  ? null
                                  : _moveSelectedItems,
                              icon: const Icon(Icons.drive_file_move_outline),
                              tooltip: '移动所选',
                            ),
                            IconButton(
                              onPressed: _isLoading || _selectedCount == 0
                                  ? null
                                  : _downloadSelectedItems,
                              icon: const Icon(Icons.download_outlined),
                              tooltip: '下载所选',
                            ),
                            IconButton(
                              onPressed: _isLoading || _selectedCount == 0
                                  ? null
                                  : _deleteSelectedItems,
                              icon: const Icon(Icons.delete_outline),
                              tooltip: '删除所选',
                            ),
                          ],
                        )
                      else ...[
                        PopupMenuButton<_MaterialSortOption>(
                          tooltip: '排序方式',
                          icon: const Icon(Icons.sort_rounded),
                          onSelected: _handleSortOptionChanged,
                          itemBuilder: (context) {
                            return _MaterialSortOption.values
                                .map(
                                  (option) =>
                                      CheckedPopupMenuItem<_MaterialSortOption>(
                                    value: option,
                                    checked: option == _sortOption,
                                    child: Text(option.label),
                                  ),
                                )
                                .toList(growable: false);
                          },
                        ),
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
                      ],
                      IconButton(
                        onPressed: _toggleSearchBar,
                        icon: Icon(
                          _isSearchBarVisible
                              ? Icons.search_off_rounded
                              : Icons.search_rounded,
                        ),
                        tooltip: _isSearchBarVisible ? '收起搜索' : '搜索',
                      ),
                      IconButton(
                        onPressed: _isLoading || _materials.isEmpty
                            ? null
                            : (_isSelectionMode
                                ? _exitSelectionMode
                                : _enterSelectionMode),
                        icon: Icon(
                          _isSelectionMode
                              ? Icons.close_fullscreen_rounded
                              : Icons.checklist_rounded,
                        ),
                        tooltip: _isSelectionMode ? '退出多选' : '多选',
                      ),
                      IconButton(
                        onPressed: _isLoading
                            ? null
                            : () => _loadMaterials(forceRefresh: true),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        tooltip: '刷新',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildFolderPath(context),
                  const SizedBox(height: 8),
                  if (_isSearchBarVisible) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            enabled: !_isLoading,
                            onChanged: (_) => _onSearchChanged(),
                            onSubmitted: (_) => _applySearch(),
                            decoration: InputDecoration(
                              hintText: '搜索当前目录文件',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchKeyword.isEmpty &&
                                      _searchController.text.trim().isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed:
                                          _isLoading ? null : _clearSearch,
                                      tooltip: '清空搜索',
                                      icon: const Icon(Icons.clear_rounded),
                                    ),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: _isLoading ? null : _applySearch,
                          icon: const Icon(Icons.search),
                          label: const Text('搜索'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
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
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Center(
                        child: Text(
                          _searchKeyword.isEmpty ? '当前目录暂无文件。' : '未找到匹配文件。',
                        ),
                      ),
                    ),
                  ..._materials.map(
                    (item) => Card(
                      clipBehavior: Clip.antiAlias,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onSecondaryTapDown: _isSelectionMode
                            ? null
                            : (details) => _showItemContextMenu(
                                  details.globalPosition,
                                  item,
                                ),
                        onLongPressStart: _isSelectionMode
                            ? null
                            : (details) => _showItemContextMenu(
                                  details.globalPosition,
                                  item,
                                ),
                        child: ListTile(
                          leading: item.isFolder
                              ? const Icon(Icons.folder_outlined)
                              : FileIcon(item.name, size: 24),
                          title: Text(item.name),
                          subtitle: Text(_buildSubtitle(item)),
                          trailing: _isSelectionMode
                              ? Checkbox(
                                  value: _selectedMaterialIds.contains(item.id),
                                  onChanged: _isLoading
                                      ? null
                                      : (_) =>
                                          _toggleMaterialSelection(item.id),
                                )
                              : (item.isFolder
                                  ? const Icon(Icons.chevron_right_rounded)
                                  : null),
                          onTap: () => _handleItemTap(item),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isDragHovering && widget.enableExternalDrop)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.08),
                    alignment: Alignment.center,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Text('松开以上传到当前文件夹'),
                      ),
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
