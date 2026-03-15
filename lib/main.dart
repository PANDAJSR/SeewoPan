import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SeewoPan',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeShellPage(),
    );
  }
}

class HomeShellPage extends StatefulWidget {
  const HomeShellPage({super.key});

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  int _selectedIndex = 0;

  static const _cookieStorageKey = 'seewopan.cookie';
  final TextEditingController _cookieController = TextEditingController();
  bool _isLoadingCookie = true;
  bool _isSavingCookie = false;
  bool _cookieSaved = false;

  static const List<_NavItem> _items = [
    _NavItem(
      label: '云盘',
      icon: Icons.cloud_outlined,
      selectedIcon: Icons.cloud,
    ),
    _NavItem(
      label: '传输',
      icon: Icons.swap_horiz_outlined,
      selectedIcon: Icons.swap_horiz,
    ),
    _NavItem(
      label: '我的',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadCookie();
  }

  @override
  void dispose() {
    _cookieController.dispose();
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
        return const _PlaceholderPage(title: '云盘');
      case 1:
        return const _PlaceholderPage(title: '传输');
      case 2:
        return _buildProfilePage();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildProfilePage() {
    if (_isLoadingCookie) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasCookie = _cookieController.text.trim().isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cookie 设置',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              hasCookie ? '已检测到 Cookie，可在下方修改并保存。' : '当前未设置 Cookie，请先填写并保存。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cookieController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '请输入 Cookie',
              ),
              onChanged: (_) {
                if (_cookieSaved) {
                  setState(() {
                    _cookieSaved = false;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _isSavingCookie ? null : _saveCookie,
                  icon: _isSavingCookie
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_isSavingCookie ? '保存中...' : '保存 Cookie'),
                ),
                const SizedBox(width: 12),
                if (_cookieSaved)
                  Text(
                    '已保存',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadCookie() async {
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString(_cookieStorageKey) ?? '';
    if (!mounted) {
      return;
    }

    setState(() {
      _cookieController.text = cookie;
      _cookieSaved = cookie.trim().isNotEmpty;
      _isLoadingCookie = false;
    });
  }

  Future<void> _saveCookie() async {
    setState(() {
      _isSavingCookie = true;
    });

    final value = _cookieController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookieStorageKey, value);

    if (!mounted) {
      return;
    }

    setState(() {
      _isSavingCookie = false;
      _cookieSaved = value.isNotEmpty;
    });
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

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$title 页面开发中',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
