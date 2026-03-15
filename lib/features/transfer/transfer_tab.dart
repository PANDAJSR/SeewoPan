import 'package:flutter/material.dart';

import 'upload_task_manager.dart';

class TransferTab extends StatelessWidget {
  const TransferTab({
    super.key,
    required this.taskManager,
  });

  final UploadTaskManager taskManager;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: taskManager,
      builder: (context, _) {
        final tasks = taskManager.tasks.reversed.toList(growable: false);
        final active = taskManager.activeTasks;

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '传输任务',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                active.isEmpty ? '当前没有进行中的上传任务' : '进行中：${active.length} 个任务',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: Text('暂无传输记录。')),
                )
              else
                ...tasks.map((task) => _TaskCard(task: task)),
            ],
          ),
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final UploadTaskItem task;

  @override
  Widget build(BuildContext context) {
    final statusText = switch (task.status) {
      UploadTaskStatus.queued => '排队中',
      UploadTaskStatus.uploading => '上传中',
      UploadTaskStatus.success => '上传成功',
      UploadTaskStatus.failed => '上传失败',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  statusText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: task.status == UploadTaskStatus.failed ? 0 : task.progress,
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatBytes(task.uploadedBytes)} / ${_formatBytes(task.totalBytes)} · ${_formatSpeed(task.speedBps)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (task.errorMessage != null &&
                task.errorMessage!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  task.errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) {
      return '0 B/s';
    }
    return '${_formatBytes(bytesPerSecond.round())}/s';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    const units = ['KB', 'MB', 'GB', 'TB'];
    double value = bytes / 1024;
    var unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }

    return '${value.toStringAsFixed(2)} ${units[unitIndex]}';
  }
}
