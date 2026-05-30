import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.cookie});

  final String cookie;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  WebViewController? _controller;
  bool _isLoading = true;

  static const String _signInUrl =
      'https://easinote.seewo.com/extend/app/dailysign';

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 16; PJX110 Build/UKQ1.231108.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/121.0.6167.71 MQQBrowser/6.2 TBS/048447 Mobile Safari/537.36 ENApp/2.1.52.1 NativeVersion/47';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final controller = WebViewController();

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    try {
      await controller.setBackgroundColor(Colors.white);
    } catch (_) {}
    await controller.setUserAgent(_userAgent);

    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (String url) {
          debugPrint('Page started: $url');
          setState(() => _isLoading = true);
        },
        onPageFinished: (String url) {
          debugPrint('Page finished: $url');
          setState(() => _isLoading = false);
        },
        onWebResourceError: (WebResourceError error) {
          debugPrint('WebResourceError: ${error.description}');
        },
      ),
    );

    if (mounted) {
      setState(() => _controller = controller);
    }

    await _setCookies();
    await controller.loadRequest(Uri.parse(_signInUrl));
  }

  Future<void> _setCookies() async {
    final cookieManager = WebViewCookieManager();

    final cookies = <String, String>{
      'x-auth-app': 'EasiNoteAndroid',
      'app_version': '2.1.52.1',
      'client_channel': 'oppo',
    };

    if (widget.cookie.isNotEmpty) {
      final parts = widget.cookie.split(';');
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final eqIdx = trimmed.indexOf('=');
        if (eqIdx <= 0) continue;
        final name = trimmed.substring(0, eqIdx).trim();
        final value = trimmed.substring(eqIdx + 1).trim();
        if (name == 'x-auth-token' || name == 'x-token') {
          cookies[name] = value;
        }
      }
    }

    for (final entry in cookies.entries) {
      final cookie = WebViewCookie(
        name: entry.key,
        value: entry.value,
        domain: '.seewo.com',
        path: '/',
      );
      debugPrint('Setting cookie: ${entry.key}');
      await cookieManager.setCookie(cookie);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('每日签到'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _controller == null
                ? null
                : () {
                    _setCookies().then((_) => _controller!.reload());
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          Expanded(
            child: _controller != null
                ? WebViewWidget(controller: _controller!)
                : const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}
