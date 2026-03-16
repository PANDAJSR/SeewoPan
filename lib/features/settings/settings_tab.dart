import 'package:flutter/material.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({
    super.key,
    required this.maxConcurrentUploads,
    required this.onMaxConcurrentUploadsChanged,
  });

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
