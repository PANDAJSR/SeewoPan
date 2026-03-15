import 'package:flutter/material.dart';

import '../../shared/models/user_profile.dart';
import '../../shared/pinco_api_client.dart';

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

  bool _cookieSaved = false;
  bool _isLoadingUserInfo = false;
  String? _error;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _syncCookieFromProps();
    _maybeAutoFetchUserInfo();
  }

  @override
  void didUpdateWidget(covariant ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCookie != widget.initialCookie) {
      _syncCookieFromProps();
      _resetProfile();
      _maybeAutoFetchUserInfo();
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
    });

    _maybeAutoFetchUserInfo();
  }

  Future<void> _fetchUserInfo() async {
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
      final profile = await widget.apiClient.getUserInfo(cookie);

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

  void _maybeAutoFetchUserInfo() {
    if (_isLoadingUserInfo) {
      return;
    }

    if (_cookieController.text.trim().isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isLoadingUserInfo || _profile != null) {
        return;
      }
      _fetchUserInfo();
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
            FilledButton.icon(
              onPressed:
                  hasCookie && !_isLoadingUserInfo ? _fetchUserInfo : null,
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
            const Divider(height: 28),
            Text('Cookie 设置', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '修改后请重新保存，再点击“获取用户信息”刷新上方资料。',
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
                if (_cookieSaved || _profile != null) {
                  setState(() {
                    _cookieSaved = false;
                    _resetProfile();
                  });
                }
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
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
