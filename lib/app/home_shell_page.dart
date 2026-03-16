import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/cloud/cloud_tab.dart';
import '../features/profile/profile_tab.dart';
import '../features/settings/settings_tab.dart';
import '../features/transfer/transfer_tab.dart';
import '../features/transfer/upload_task_manager.dart';
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

  int _selectedIndex = 0;
  bool _isLoadingCookie = true;
  bool _isSavingCookie = false;
  String _cookie = '';
  int _maxConcurrentUploads = 3;

  @override
  void initState() {
    super.initState();
    _loadLocalSettings();
  }

  @override
  void dispose() {
    _uploadTaskManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

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
            Expanded(child: _buildContent()),
          ],
        ),
      );
    }

    return Scaffold(
      body: _buildContent(),
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
    switch (_selectedIndex) {
      case 0:
        return CloudTab(
          cookie: _cookie,
          isLoadingCookie: _isLoadingCookie,
          apiClient: _apiClient,
          onUploadFiles: _uploadTaskManager.enqueueFiles,
          onOpenTransferTab: () => _onSelect(1),
        );
      case 1:
        return TransferTab(taskManager: _uploadTaskManager);
      case 2:
        return ProfileTab(
          initialCookie: _cookie,
          isLoadingCookie: _isLoadingCookie,
          isSavingCookie: _isSavingCookie,
          onSaveCookie: _saveCookie,
          apiClient: _apiClient,
        );
      case 3:
        return SettingsTab(
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          maxConcurrentUploads: _maxConcurrentUploads,
          onMaxConcurrentUploadsChanged: _saveMaxConcurrentUploads,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _loadLocalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString(_cookieStorageKey) ?? '';
    final maxConcurrentUploads = prefs.getInt(_maxConcurrentUploadsStorageKey);
    final normalizedUploads = (maxConcurrentUploads ?? 3).clamp(1, 10);

    if (!mounted) {
      return;
    }

    setState(() {
      _cookie = cookie;
      _maxConcurrentUploads = normalizedUploads;
      _isLoadingCookie = false;
    });
    _uploadTaskManager.updateCookie(cookie);
    _uploadTaskManager.updateMaxConcurrentUploads(normalizedUploads);
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
