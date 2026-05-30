import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.cookie});

  final String cookie;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _loadingProgress = 0;

  static const String _signInUrl =
      'https://easinote.seewo.com/extend/app/dailysign';

  @override
  void initState() {
    super.initState();
    _initWebViewController();
  }

  Future<void> _initWebViewController() async {
    final controller = WebViewController();

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

    await controller.setBackgroundColor(Colors.white);

    await controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (int progress) {
          setState(() {
            _loadingProgress = progress / 100;
          });
        },
        onPageStarted: (String url) {
          debugPrint('Page started: $url');
        },
        onPageFinished: (String url) {
          setState(() {
            _isLoading = false;
          });
          debugPrint('Page finished: $url');
        },
        onWebResourceError: (WebResourceError error) {
          debugPrint('WebResourceError: ${error.description}');
        },
      ),
    );

    if (mounted) {
      setState(() {
        _controller = controller;
      });
    }

    await controller.loadRequest(Uri.parse(_signInUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('每日签到'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            const LinearProgressIndicator(),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}

class _SignInPageState extends State<SignInPage> {
  WebViewController? _controller;
  bool _isLoading = true;
  double _loadingProgress = 0;
  String? _error;

  static const String _signInUrl =
      'https://easinote.seewo.com/extend/app/dailysign';

  @override
  void initState() {
    super.initState();
    _initWebViewController();
  }

  Future<void> _initWebViewController() async {
    try {
      final controller = WebViewController();

      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

      if (!Platform.isMacOS) {
        await controller.setBackgroundColor(Colors.white);
      }

      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (!mounted) {
              return;
            }
            setState(() {
              _loadingProgress = progress / 100;
            });
          },
          onPageStarted: (String url) {
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = false;
            });
            unawaited(_injectCookie());
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebResourceError: ${error.description}');
          },
        ),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _controller = controller;
      });

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

  Future<void> _injectCookie() async {
    if (widget.cookie.isEmpty) return;

    final controller = _controller;
    if (controller == null) {
      return;
    }

    final cookieParts = widget.cookie.split(';').where((c) => c.isNotEmpty);
    for (final part in cookieParts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      final eqIndex = trimmed.indexOf('=');
      if (eqIndex <= 0) continue;

      final name = trimmed.substring(0, eqIndex).trim();
      final value = trimmed.substring(eqIndex + 1).trim();

      await controller.runJavaScript(
        "document.cookie = \"$name=$value; path=/; domain=.seewo.com\";",
      );
    }

    await controller.runJavaScript(
      "document.cookie = \"x-auth-app=EasiNoteAndroid; path=/; domain=.seewo.com\";",
    );
    await controller.runJavaScript(
      "document.cookie = \"app_version=2.1.52.1; path=/; domain=.seewo.com\";",
    );
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
            onPressed: controller == null ? null : () => controller.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            LinearProgressIndicator(
              value: _loadingProgress > 0 ? _loadingProgress : null,
            ),
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
