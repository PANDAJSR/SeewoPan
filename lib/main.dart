import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
  bool _isLoadingUserInfo = false;
  String? _userDisplayName;
  String? _userInfoError;

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
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: hasCookie && !_isLoadingUserInfo ? _fetchUserInfo : null,
              icon: _isLoadingUserInfo
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_search_outlined),
              label: Text(_isLoadingUserInfo ? '获取中...' : '获取用户信息'),
            ),
            const SizedBox(height: 12),
            if (_userDisplayName != null)
              Text(
                '用户名：$_userDisplayName',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            if (_userInfoError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _userInfoError!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
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

  Future<void> _fetchUserInfo() async {
    setState(() {
      _isLoadingUserInfo = true;
      _userInfoError = null;
    });

    final cookie = _cookieController.text.trim();

    try {
      final uri = Uri.parse(
        'https://pinco.seewo.com/teacher/api.json?actionName=GetV1UsersInfo',
      );

      final response = await http.post(
        uri,
        headers: {
          'Accept': '*/*',
          'Content-Type': 'application/json;charset=UTF-8',
          'x-language': 'zh_CHS',
          'x-server': 'default',
          'Cookie': cookie,
        },
        body: jsonEncode(<String, dynamic>{}),
      );

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected response format.');
      }

      final statusCode = decoded['statusCode'];
      if (statusCode != 0) {
        final message = decoded['message']?.toString() ?? '接口返回错误';
        throw Exception(message);
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Missing user data.');
      }

      final nickName = data['nickName']?.toString().trim();
      final realName = data['realName']?.toString().trim();
      final username = data['username']?.toString().trim();

      final displayName = [nickName, realName, username]
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .join(' / ');

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingUserInfo = false;
        _userDisplayName = displayName.isEmpty ? null : displayName;
        _userInfoError = displayName.isEmpty ? '未获取到用户名字段。' : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingUserInfo = false;
        _userDisplayName = null;
        _userInfoError = '获取失败：$error';
      });
    }
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
