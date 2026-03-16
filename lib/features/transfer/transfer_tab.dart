import 'package:flutter/material.dart';

import 'download_task_manager.dart';
import 'upload_task_manager.dart';

class TransferTab extends StatelessWidget {
  const TransferTab({
    super.key,
    required this.uploadTaskManager,
    required this.downloadTaskManager,
  });

  final UploadTaskManager uploadTaskManager;
  final DownloadTaskManager downloadTaskManager;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([uploadTaskManager, downloadTaskManager]),
      builder: (context, _) {
        final tasks = [
          ...uploadTaskManager.tasks,
          ...downloadTaskManager.tasks,
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final activeUploads = uploadTaskManager.activeTasks;
        final activeDownloads = downloadTaskManager.activeTasks;

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
                _buildSummary(
                  activeUploadCount: activeUploads.length,
                  activeDownloadCount: activeDownloads.length,
                  uploadSpeedBps: uploadTaskManager.totalUploadingSpeedBps,
                  downloadSpeedBps:
                      downloadTaskManager.totalDownloadingSpeedBps,
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: Text('暂无传输记录。')),
                )
              else
                ...tasks.map(
                  (task) => _TaskCard(
                    task: task,
                    onPause: task.taskType == TransferTaskType.upload
                        ? () => uploadTaskManager.pauseTask(task.id)
                        : () => downloadTaskManager.pauseTask(task.id),
                    onResume: task.taskType == TransferTaskType.upload
                        ? () => uploadTaskManager.resumeTask(task.id)
                        : () => downloadTaskManager.resumeTask(task.id),
                    onCancel: task.taskType == TransferTaskType.upload
                        ? () => uploadTaskManager.cancelTask(task.id)
                        : () => downloadTaskManager.cancelTask(task.id),
                    onRetry: task.taskType == TransferTaskType.upload
                        ? () => uploadTaskManager.retryTask(task.id)
                        : () => downloadTaskManager.retryTask(task.id),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

String _buildSummary({
  required int activeUploadCount,
  required int activeDownloadCount,
  required double uploadSpeedBps,
  required double downloadSpeedBps,
}) {
  final activeTotal = activeUploadCount + activeDownloadCount;
  if (activeTotal == 0) {
    return '当前没有进行中的上传/下载任务';
  }
  return '进行中：$activeTotal 个任务 · 上传：$activeUploadCount（${_formatSpeed(uploadSpeedBps)}） · 下载：$activeDownloadCount（${_formatSpeed(downloadSpeedBps)}）';
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRetry,
  });

  final UploadTaskItem task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final typeLabel = task.taskType == TransferTaskType.upload ? '上传' : '下载';
    final statusText = switch (task.status) {
      UploadTaskStatus.queued => '排队中',
      UploadTaskStatus.uploading => '$typeLabel中',
      UploadTaskStatus.paused => '已暂停',
      UploadTaskStatus.canceled => '已取消',
      UploadTaskStatus.success => '$typeLabel成功',
      UploadTaskStatus.failed => '$typeLabel失败',
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusText,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (task.status == UploadTaskStatus.queued ||
                        task.status == UploadTaskStatus.uploading)
                      IconButton(
                        tooltip: '暂停',
                        visualDensity: VisualDensity.compact,
                        onPressed: onPause,
                        icon: const Icon(Icons.pause_circle_outline),
                      ),
                    if (task.status == UploadTaskStatus.paused)
                      IconButton(
                        tooltip: '继续',
                        visualDensity: VisualDensity.compact,
                        onPressed: onResume,
                        icon: const Icon(Icons.play_circle_outline),
                      ),
                    if (task.status == UploadTaskStatus.queued ||
                        task.status == UploadTaskStatus.uploading ||
                        task.status == UploadTaskStatus.paused)
                      IconButton(
                        tooltip: '取消',
                        visualDensity: VisualDensity.compact,
                        onPressed: onCancel,
                        icon: const Icon(Icons.cancel_outlined),
                      ),
                    if (task.status == UploadTaskStatus.failed ||
                        task.status == UploadTaskStatus.canceled)
                      IconButton(
                        tooltip: '重试',
                        visualDensity: VisualDensity.compact,
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: task.status == UploadTaskStatus.failed ||
                      task.status == UploadTaskStatus.canceled
                  ? 0
                  : task.progress,
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatBytes(task.uploadedBytes)} / ${_formatBytes(task.totalBytes)} · ${_formatSpeed(task.speedBps)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (task.localPath != null &&
                task.localPath!.trim().isNotEmpty &&
                task.status == UploadTaskStatus.success &&
                task.taskType == TransferTaskType.download)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  task.localPath!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
