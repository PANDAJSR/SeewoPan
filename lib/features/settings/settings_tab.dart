import 'package:flutter/material.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.maxConcurrentUploads,
    required this.onMaxConcurrentUploadsChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final int maxConcurrentUploads;
  final ValueChanged<int> onMaxConcurrentUploadsChanged;

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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '同时最大上传任务数',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$maxConcurrentUploads',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Slider(
                    min: 1,
                    max: 10,
                    divisions: 9,
                    value: maxConcurrentUploads.toDouble(),
                    label: '$maxConcurrentUploads',
                    onChanged: (value) {
                      onMaxConcurrentUploadsChanged(value.round());
                    },
                  ),
                  Text(
                    '范围 1-10，默认 3。修改后会立即应用到后续排队任务。',
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
