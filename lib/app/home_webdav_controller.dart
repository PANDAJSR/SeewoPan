import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/webdav/seewo_webdav_server.dart';
import '../features/webdav/webdav_settings.dart';
import '../shared/pinco_api_client.dart';

class HomeWebDavController extends ChangeNotifier {
  HomeWebDavController({required PincoApiClient apiClient})
      : _server = SeewoWebDavServer(apiClient: apiClient);

  static const _portStorageKey = 'seewopan.webdav.port';
  static const _usernameStorageKey = 'seewopan.webdav.username';
  static const _passwordStorageKey = 'seewopan.webdav.password';

  final SeewoWebDavServer _server;
  WebDavSettings settings = WebDavSettings.defaults;
  bool isBusy = false;
  String? errorMessage;
  String _cookie = '';

  bool get isRunning => _server.isRunning;

  Uri? get uri => _server.uri;

  Future<void> loadFromPrefs(SharedPreferences prefs) async {
    settings = WebDavSettings(
      port: (prefs.getInt(_portStorageKey) ?? WebDavSettings.defaults.port)
          .clamp(1, 65535),
      username: prefs.getString(_usernameStorageKey) ??
          WebDavSettings.defaults.username,
      password: prefs.getString(_passwordStorageKey) ??
          WebDavSettings.defaults.password,
    );
    notifyListeners();
  }

  void updateCookie(String cookie) {
    _cookie = cookie;
    _server.updateCookie(cookie);
  }

  Future<void> saveSettings(WebDavSettings value) async {
    final normalized = WebDavSettings(
      port: value.port.clamp(1, 65535),
      username: value.username.trim(),
      password: value.password,
    );
    settings = normalized;
    errorMessage = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_portStorageKey, normalized.port);
    await prefs.setString(_usernameStorageKey, normalized.username);
    await prefs.setString(_passwordStorageKey, normalized.password);

    if (_server.isRunning) {
      await _runBusy(
        () => _server.start(settings: settings, cookie: _cookie),
        failurePrefix: '重启失败',
      );
    }
  }

  Future<void> start() {
    return _runBusy(
      () => _server.start(settings: settings, cookie: _cookie),
      failurePrefix: '启动失败',
    );
  }

  Future<void> stop() {
    return _runBusy(_server.stop, failurePrefix: '停止失败');
  }

  Future<void> _runBusy(
    Future<void> Function() action, {
    required String failurePrefix,
  }) async {
    if (isBusy) {
      return;
    }
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = '$failurePrefix：$error';
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_server.stop());
    super.dispose();
  }
}
