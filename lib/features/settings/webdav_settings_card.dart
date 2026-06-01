import 'package:flutter/material.dart';

import '../webdav/webdav_settings.dart';

class WebDavSettingsCard extends StatefulWidget {
  const WebDavSettingsCard({
    super.key,
    required this.settings,
    required this.isRunning,
    required this.isBusy,
    required this.uri,
    required this.errorMessage,
    required this.onStart,
    required this.onStop,
    required this.onSettingsChanged,
  });

  final WebDavSettings settings;
  final bool isRunning;
  final bool isBusy;
  final Uri? uri;
  final String? errorMessage;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final ValueChanged<WebDavSettings> onSettingsChanged;

  @override
  State<WebDavSettingsCard> createState() => _WebDavSettingsCardState();
}

class _WebDavSettingsCardState extends State<WebDavSettingsCard> {
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(text: '${widget.settings.port}');
    _usernameController = TextEditingController(text: widget.settings.username);
    _passwordController = TextEditingController(text: widget.settings.password);
  }

  @override
  void didUpdateWidget(covariant WebDavSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_portController, '${widget.settings.port}');
    _syncController(_usernameController, widget.settings.username);
    _syncController(_passwordController, widget.settings.password);
  }

  @override
  void dispose() {
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uriText = widget.uri?.toString() ?? '未启动';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WebDAV 代理', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              uriText,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '端口',
                border: OutlineInputBorder(),
              ),
              onChanged: _onPortChanged,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                widget.onSettingsChanged(
                  widget.settings.copyWith(username: value.trim()),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                widget.onSettingsChanged(
                  widget.settings.copyWith(password: value),
                );
              },
            ),
            if (widget.errorMessage?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                widget.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed:
                      widget.isBusy || widget.isRunning ? null : widget.onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('启动'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      widget.isBusy || !widget.isRunning ? null : widget.onStop,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '使用系统文件管理器或支持 WebDAV 的客户端连接本地地址。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void _onPortChanged(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 1 || parsed > 65535) {
      return;
    }
    widget.onSettingsChanged(widget.settings.copyWith(port: parsed));
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.text = value;
  }
}
