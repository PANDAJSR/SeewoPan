import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/cloud/cloud_tab.dart';
import '../features/profile/profile_tab.dart';
import '../features/settings/settings_tab.dart';
import '../features/transfer/download_task_manager.dart';
import '../features/transfer/transfer_tab.dart';
import '../features/transfer/upload_task_manager.dart';
import '../shared/default_download_directory.dart';
import '../shared/pinco_api_client.dart';

class HomeShellPage extends StatefulWidget {
  const HomeShellPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  static const _cookieStorageKey = 'seewopan.cookie';
  static const _maxConcurrentUploadsStorageKey =
      'seewopan.max_concurrent_uploads';
  static const _maxConcurrentDownloadsStorageKey =
      'seewopan.max_concurrent_downloads';
  static const _downloadDirectoryStorageKey = 'seewopan.download_directory';
  static const List<_NavItem> _items = [
    _NavItem(
        label: '云盘', icon: Icons.cloud_outlined, selectedIcon: Icons.cloud),
    _NavItem(
      label: '传输',
      icon: Icons.swap_horiz_outlined,
      selectedIcon: Icons.swap_horiz,
    ),
    _NavItem(
        label: '我的', icon: Icons.person_outline, selectedIcon: Icons.person),
    _NavItem(
      label: '设置',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];

  final PincoApiClient _apiClient = PincoApiClient();
  late final UploadTaskManager _uploadTaskManager =
      UploadTaskManager(apiClient: _apiClient);
  late final DownloadTaskManager _downloadTaskManager =
      DownloadTaskManager(apiClient: _apiClient);

  int _selectedIndex = 0;
  bool _isLoadingCookie = true;
  bool _isSavingCookie = false;
  String _cookie = '';
  int _maxConcurrentUploads = 3;
  int _maxConcurrentDownloads = 3;
  String _downloadDirectory = '';

  @override
  void initState() {
    super.initState();
    _loadLocalSettings();
  }

  @override
  void dispose() {
    _uploadTaskManager.dispose();
    _downloadTaskManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final content = _buildContent();

    if (isLandscape) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onSelect,
              labelType: NavigationRailLabelType.all,
              destinations: _items
                  .map(
                    (item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: Text(item.label),
                    ),
                  )
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      body: content,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onSelect,
        destinations: _items
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }

  void _onSelect(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildContent() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        CloudTab(
          cookie: _cookie,
          isLoadingCookie: _isLoadingCookie,
          apiClient: _apiClient,
          onUploadFiles: _uploadTaskManager.enqueueFiles,
          onDownloadMaterials: _downloadTaskManager.enqueueMaterials,
          onOpenTransferTab: () => _onSelect(1),
        ),
        TransferTab(
          uploadTaskManager: _uploadTaskManager,
          downloadTaskManager: _downloadTaskManager,
        ),
        ProfileTab(
          initialCookie: _cookie,
          isLoadingCookie: _isLoadingCookie,
          isSavingCookie: _isSavingCookie,
          onSaveCookie: _saveCookie,
          apiClient: _apiClient,
        ),
        SettingsTab(
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          maxConcurrentUploads: _maxConcurrentUploads,
          onMaxConcurrentUploadsChanged: _saveMaxConcurrentUploads,
          maxConcurrentDownloads: _maxConcurrentDownloads,
          onMaxConcurrentDownloadsChanged: _saveMaxConcurrentDownloads,
          downloadDirectory: _downloadDirectory,
          onSelectDownloadDirectory: _selectDownloadDirectory,
          onResetDownloadDirectory: _resetDownloadDirectory,
        ),
      ],
    );
  }

  Future<void> _loadLocalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString(_cookieStorageKey) ?? '';
    final maxConcurrentUploads = prefs.getInt(_maxConcurrentUploadsStorageKey);
    final maxConcurrentDownloads =
        prefs.getInt(_maxConcurrentDownloadsStorageKey);
    final storedDownloadDirectory =
        prefs.getString(_downloadDirectoryStorageKey)?.trim() ?? '';
    final normalizedDownloadDirectory = storedDownloadDirectory;
    final normalizedUploads = (maxConcurrentUploads ?? 3).clamp(1, 10);
    final normalizedDownloads = (maxConcurrentDownloads ?? 3).clamp(1, 10);

    if (!mounted) {
      return;
    }

    setState(() {
      _cookie = cookie;
      _maxConcurrentUploads = normalizedUploads;
      _maxConcurrentDownloads = normalizedDownloads;
      _downloadDirectory = normalizedDownloadDirectory;
      _isLoadingCookie = false;
    });
    _uploadTaskManager.updateCookie(cookie);
    _uploadTaskManager.updateMaxConcurrentUploads(normalizedUploads);
    _downloadTaskManager.updateCookie(cookie);
    _downloadTaskManager.updateMaxConcurrentDownloads(normalizedDownloads);
    _downloadTaskManager.updateDownloadDirectory(normalizedDownloadDirectory);

    if (storedDownloadDirectory.isEmpty) {
      unawaited(_initializeDefaultDownloadDirectory());
    }
  }

  Future<void> _initializeDefaultDownloadDirectory() async {
    final defaultDownloadDirectory =
        await resolveDefaultDownloadDirectoryPath();
    final normalized = defaultDownloadDirectory.trim();
    if (normalized.isEmpty ||
        !mounted ||
        _downloadDirectory.trim().isNotEmpty) {
      return;
    }
    await _saveDownloadDirectory(normalized);
  }

  Future<void> _saveCookie(String value) async {
    setState(() {
      _isSavingCookie = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookieStorageKey, value);

    if (!mounted) {
      return;
    }

    setState(() {
      _cookie = value;
      _isSavingCookie = false;
    });
    _uploadTaskManager.updateCookie(value);
    _downloadTaskManager.updateCookie(value);
  }

  Future<void> _saveMaxConcurrentUploads(int value) async {
    final normalized = value.clamp(1, 10);
    if (normalized == _maxConcurrentUploads) {
      return;
    }

    setState(() {
      _maxConcurrentUploads = normalized;
    });
    _uploadTaskManager.updateMaxConcurrentUploads(normalized);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxConcurrentUploadsStorageKey, normalized);
  }

  Future<void> _saveMaxConcurrentDownloads(int value) async {
    final normalized = value.clamp(1, 10);
    if (normalized == _maxConcurrentDownloads) {
      return;
    }

    setState(() {
      _maxConcurrentDownloads = normalized;
    });
    _downloadTaskManager.updateMaxConcurrentDownloads(normalized);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxConcurrentDownloadsStorageKey, normalized);
  }

  Future<void> _selectDownloadDirectory() async {
    final initialDirectory =
        _downloadDirectory.trim().isEmpty ? null : _downloadDirectory;
    final selected = await getDirectoryPath(
      initialDirectory: initialDirectory,
    );

    if (selected == null || selected.trim().isEmpty || !mounted) {
      return;
    }
    await _saveDownloadDirectory(selected.trim());
  }

  Future<void> _resetDownloadDirectory() async {
    final defaultPath = await resolveDefaultDownloadDirectoryPath();
    await _saveDownloadDirectory(defaultPath.trim());
  }

  Future<void> _saveDownloadDirectory(String value) async {
    final normalized = value.trim();
    if (normalized == _downloadDirectory) {
      return;
    }

    setState(() {
      _downloadDirectory = normalized;
    });
    _downloadTaskManager.updateDownloadDirectory(normalized);

    final prefs = await SharedPreferences.getInstance();
    if (normalized.isEmpty) {
      await prefs.remove(_downloadDirectoryStorageKey);
      return;
    }
    await prefs.setString(_downloadDirectoryStorageKey, normalized);
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
