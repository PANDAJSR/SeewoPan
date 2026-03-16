import 'package:flutter/material.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.maxConcurrentUploads,
    required this.onMaxConcurrentUploadsChanged,
    required this.maxConcurrentDownloads,
    required this.onMaxConcurrentDownloadsChanged,
    required this.downloadDirectory,
    required this.onSelectDownloadDirectory,
    required this.onResetDownloadDirectory,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final int maxConcurrentUploads;
  final ValueChanged<int> onMaxConcurrentUploadsChanged;
  final int maxConcurrentDownloads;
  final ValueChanged<int> onMaxConcurrentDownloadsChanged;
  final String downloadDirectory;
  final Future<void> Function() onSelectDownloadDirectory;
  final Future<void> Function() onResetDownloadDirectory;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '设置',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      '主题模式',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('跟随系统（默认）'),
                    value: ThemeMode.system,
                    groupValue: themeMode,
                    onChanged: (value) {
                      if (value != null) {
                        onThemeModeChanged(value);
                      }
                    },
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('浅色模式'),
                    value: ThemeMode.light,
                    groupValue: themeMode,
                    onChanged: (value) {
                      if (value != null) {
                        onThemeModeChanged(value);
                      }
                    },
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('深色模式'),
                    value: ThemeMode.dark,
                    groupValue: themeMode,
                    onChanged: (value) {
                      if (value != null) {
                        onThemeModeChanged(value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ConcurrentTaskCard(
            title: '同时最大上传任务数',
            value: maxConcurrentUploads,
            onChanged: onMaxConcurrentUploadsChanged,
            description: '范围 1-10，默认 3。修改后会立即应用到后续排队任务。',
          ),
          const SizedBox(height: 12),
          _ConcurrentTaskCard(
            title: '同时最大下载任务数',
            value: maxConcurrentDownloads,
            onChanged: onMaxConcurrentDownloadsChanged,
            description: '范围 1-10，默认 3。修改后会立即应用到后续排队任务。',
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '下载目录',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    downloadDirectory.trim().isEmpty
                        ? '未设置'
                        : downloadDirectory,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: onSelectDownloadDirectory,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('选择目录'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onResetDownloadDirectory,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('恢复默认'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '默认使用当前用户下载目录。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConcurrentTaskCard extends StatelessWidget {
  const _ConcurrentTaskCard({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.description,
  });

  final String title;
  final int value;
  final ValueChanged<int> onChanged;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Slider(
              min: 1,
              max: 10,
              divisions: 9,
              value: value.toDouble(),
              label: '$value',
              onChanged: (newValue) {
                onChanged(newValue.round());
              },
            ),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
