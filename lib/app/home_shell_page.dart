import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/cloud/cloud_tab.dart';
import '../features/profile/profile_tab.dart';
import '../features/transfer/transfer_tab.dart';
import '../features/transfer/upload_task_manager.dart';
import '../shared/pinco_api_client.dart';

class HomeShellPage extends StatefulWidget {
  const HomeShellPage({super.key});

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  static const _cookieStorageKey = 'seewopan.cookie';
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
  ];

  final PincoApiClient _apiClient = PincoApiClient();
  late final UploadTaskManager _uploadTaskManager =
      UploadTaskManager(apiClient: _apiClient);

  int _selectedIndex = 0;
  bool _isLoadingCookie = true;
  bool _isSavingCookie = false;
  String _cookie = '';

  @override
  void initState() {
    super.initState();
    _loadCookie();
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
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _loadCookie() async {
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString(_cookieStorageKey) ?? '';

    if (!mounted) {
      return;
    }

    setState(() {
      _cookie = cookie;
      _isLoadingCookie = false;
    });
    _uploadTaskManager.updateCookie(cookie);
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
