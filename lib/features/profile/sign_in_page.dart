import 'package:flutter/foundation.dart';
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
  String? _error;

  static const String _signInUrl =
      'https://easinote.seewo.com/extend/app/dailysign';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      final controller = WebViewController();

      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (!kIsWeb && defaultTargetPlatform != TargetPlatform.macOS) {
        await controller.setBackgroundColor(Colors.white);
      }

      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('Page started: $url');
            if (!mounted) {
              return;
            }
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            debugPrint('Page finished: $url');
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebResourceError: ${error.description}');
          },
        ),
      );

      if (!mounted) {
        return;
      }
      setState(() => _controller = controller);

      await _setCookies();
      await controller.loadRequest(Uri.parse(_signInUrl));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = error.toString();
      });
    }
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
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('每日签到'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: controller == null
                ? null
                : () {
                    _setCookies().then((_) => controller.reload());
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? Center(child: Text('加载签到页失败：$_error'))
                : controller == null
                    ? const Center(child: CircularProgressIndicator())
                    : WebViewWidget(controller: controller),
          ),
        ],
      ),
    );
  }
}
