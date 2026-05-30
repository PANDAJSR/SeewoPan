import 'package:flutter/material.dart';

import '../../shared/models/drive_materials_capacity.dart';
import '../../shared/models/user_profile.dart';
import '../../shared/pinco_api_client.dart';
import 'sign_in_page.dart';

part 'profile_tab_capacity.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({
    super.key,
    required this.initialCookie,
    required this.isLoadingCookie,
    required this.isSavingCookie,
    required this.onSaveCookie,
    required this.apiClient,
  });

  final String initialCookie;
  final bool isLoadingCookie;
  final bool isSavingCookie;
  final Future<void> Function(String value) onSaveCookie;
  final PincoApiClient apiClient;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final TextEditingController _cookieController = TextEditingController();

  bool _showCookieEditor = false;
  bool _isCookieObscured = true;
  bool _cookieSaved = false;
  bool _isLoadingUserInfo = false;
  bool _isLoadingCapacity = false;
  String? _error;
  String? _capacityError;
  UserProfile? _profile;
  DriveMaterialsCapacity? _capacity;

  @override
  void initState() {
    super.initState();
    _syncCookieFromProps();
    _maybeAutoFetchOverview();
  }

  @override
  void didUpdateWidget(covariant ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCookie != widget.initialCookie) {
      _syncCookieFromProps();
      _resetProfile();
      _resetCapacity();
      _maybeAutoFetchOverview();
    }
  }

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  void _syncCookieFromProps() {
    _cookieController.text = widget.initialCookie;
    _cookieSaved = widget.initialCookie.trim().isNotEmpty;
  }

  Future<void> _saveCookie() async {
    final value = _cookieController.text.trim();
    await widget.onSaveCookie(value);
    if (!mounted) {
      return;
    }

    setState(() {
      _cookieSaved = value.isNotEmpty;
      _error = null;
      _resetProfile();
      _resetCapacity();
    });

    _maybeAutoFetchOverview();
  }

  Future<void> _fetchUserInfo({bool forceRefresh = false}) async {
    final cookie = _cookieController.text.trim();
    if (cookie.isEmpty) {
      setState(() {
        _error = '请先填写 Cookie。';
      });
      return;
    }

    setState(() {
      _isLoadingUserInfo = true;
      _error = null;
    });

    try {
      final profile = await widget.apiClient.getUserInfo(
        cookie,
        forceRefresh: forceRefresh,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingUserInfo = false;
        _profile = profile;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingUserInfo = false;
        _profile = null;
        _error = '获取失败：$error';
      });
    }
  }

  void _resetProfile() {
    _profile = null;
  }

  Future<void> _fetchOverview({bool forceRefresh = false}) async {
    await Future.wait<void>([
      _fetchUserInfo(forceRefresh: forceRefresh),
      _fetchCapacity(forceRefresh: forceRefresh),
    ]);
  }

  void _maybeAutoFetchOverview() {
    if (_isLoadingUserInfo || _isLoadingCapacity) {
      return;
    }

    if (_cookieController.text.trim().isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isLoadingUserInfo || _isLoadingCapacity) {
        return;
      }
      if (_profile != null && _capacity != null) {
        return;
      }
      _fetchOverview();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoadingCookie) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasCookie = _cookieController.text.trim().isNotEmpty;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_profile != null) _ProfileCard(profile: _profile!),
            if (_profile == null)
              Text(
                hasCookie
                    ? '已检测到 Cookie，将自动获取用户资料，也可手动刷新。'
                    : '当前未设置 Cookie，请先填写并保存。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 16),
            _CapacityCard(
              capacity: _capacity,
              isLoading: _isLoadingCapacity,
              error: _capacityError,
              segments: _buildUsageSegments(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        hasCookie && !_isLoadingUserInfo && !_isLoadingCapacity
                            ? () => _fetchOverview(forceRefresh: true)
                            : null,
                    icon: (_isLoadingUserInfo || _isLoadingCapacity)
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_search_outlined),
                    label: Text(
                      (_isLoadingUserInfo || _isLoadingCapacity)
                          ? '获取中...'
                          : '刷新资料',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: hasCookie
                        ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => SignInPage(
                                    cookie: _cookieController.text.trim()),
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: const Text('每日签到'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 28),
            Text('Cookie 设置', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '默认不展示 Cookie 输入框，点击“设置 Cookie”后再编辑并保存。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showCookieEditor = !_showCookieEditor;
                    });
                  },
                  icon: Icon(
                    _showCookieEditor
                        ? Icons.keyboard_arrow_up
                        : Icons.edit_outlined,
                  ),
                  label: Text(_showCookieEditor ? '收起 Cookie 设置' : '设置 Cookie'),
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
            if (_showCookieEditor) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _cookieController,
                obscureText: _isCookieObscured,
                maxLines: 1,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: '请输入 Cookie',
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _isCookieObscured = !_isCookieObscured;
                      });
                    },
                    icon: Icon(
                      _isCookieObscured
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    tooltip: _isCookieObscured ? '显示 Cookie' : '隐藏 Cookie',
                  ),
                ),
                onChanged: (_) {
                  if (_cookieSaved || _profile != null || _capacity != null) {
                    setState(() {
                      _cookieSaved = false;
                      _resetProfile();
                      _resetCapacity();
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: widget.isSavingCookie ? null : _saveCookie,
                icon: widget.isSavingCookie
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(widget.isSavingCookie ? '保存中...' : '保存 Cookie'),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
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
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: profile.photoUrl?.isNotEmpty == true
                  ? NetworkImage(profile.photoUrl!)
                  : null,
              child: profile.photoUrl?.isNotEmpty == true
                  ? null
                  : const Icon(Icons.person),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (profile.realName != null &&
                      profile.realName!.isNotEmpty &&
                      profile.realName != profile.displayName)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '姓名：${profile.realName}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  if (profile.username != null && profile.username!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '账号：${profile.username}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  if (profile.schoolName != null &&
                      profile.schoolName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '学校：${profile.schoolName}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
