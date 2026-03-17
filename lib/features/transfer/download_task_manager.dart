import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../shared/pinco_api_client.dart';
import '../../shared/models/drive_material.dart';
import 'upload_task_models.dart';

typedef DownloadFileHandler = Future<void> Function({
  required String cookie,
  required String materialId,
  required String savePath,
  CancelToken? cancelToken,
  ProgressCallback? onReceiveProgress,
});

enum _DownloadTaskStopAction {
  paused,
  canceled,
}

class DownloadTaskManager extends ChangeNotifier {
  DownloadTaskManager({
    required PincoApiClient apiClient,
    DownloadFileHandler? downloadFileHandler,
  }) : _downloadFileHandler =
            downloadFileHandler ?? apiClient.downloadMaterialToFile;

  final DownloadFileHandler _downloadFileHandler;
  final List<UploadTaskItem> _tasks = <UploadTaskItem>[];
  final Map<String, DriveMaterial> _sourceByTaskId = <String, DriveMaterial>{};
  final Map<String, CancelToken> _cancelTokenByTaskId = <String, CancelToken>{};
  final Map<String, _DownloadTaskStopAction> _stopActionByTaskId =
      <String, _DownloadTaskStopAction>{};
  final Map<String, List<_ProgressSample>> _progressSamplesByTaskId =
      <String, List<_ProgressSample>>{};
  final Map<String, double> _lastReportedSpeedByTaskId = <String, double>{};
  final Map<String, DateTime> _lastSpeedUpdateAtByTaskId = <String, DateTime>{};
  final Random _random = Random();

  String _cookie = '';
  String _downloadDirectory = '';
  bool _isDispatching = false;
  int _runningDownloads = 0;
  int _maxConcurrentDownloads = 3;

  List<UploadTaskItem> get tasks => List<UploadTaskItem>.unmodifiable(_tasks);
  int get maxConcurrentDownloads => _maxConcurrentDownloads;
  String get downloadDirectory => _downloadDirectory;

  List<UploadTaskItem> get activeTasks => _tasks
      .where((task) =>
          task.status == UploadTaskStatus.queued ||
          task.status == UploadTaskStatus.uploading)
      .toList(growable: false);

  double get totalDownloadingSpeedBps => _tasks
      .where((task) => task.status == UploadTaskStatus.uploading)
      .fold(0.0, (sum, task) => sum + task.speedBps);

  void updateCookie(String value) {
    _cookie = value.trim();
  }

  void updateDownloadDirectory(String value) {
    _downloadDirectory = value.trim();
  }

  void updateMaxConcurrentDownloads(int value) {
    final normalized = value.clamp(1, 10);
    if (normalized == _maxConcurrentDownloads) {
      return;
    }
    _maxConcurrentDownloads = normalized;
    notifyListeners();
    unawaited(_runQueue());
  }

  Future<void> enqueueMaterials(List<DriveMaterial> materials) async {
    if (materials.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final added = materials.map((material) {
      final taskId = _createTaskId(now);
      _sourceByTaskId[taskId] = material;
      return UploadTaskItem(
        id: taskId,
        taskType: TransferTaskType.download,
        name: material.name,
        size: material.size,
        parentFolderId: material.folderId,
        status: UploadTaskStatus.queued,
        createdAt: now,
        progress: 0,
        speedBps: 0,
        uploadedBytes: 0,
        totalBytes: max(material.size, 0),
      );
    }).toList(growable: false);

    _tasks.addAll(added);
    notifyListeners();
    unawaited(_runQueue());
  }

  void pauseTask(String taskId) {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) {
      return;
    }

    final task = _tasks[index];
    if (task.status == UploadTaskStatus.queued) {
      _tasks[index] = task.copyWith(
        status: UploadTaskStatus.paused,
        speedBps: 0,
      );
      notifyListeners();
      return;
    }

    if (task.status != UploadTaskStatus.uploading) {
      return;
    }

    _stopActionByTaskId[taskId] = _DownloadTaskStopAction.paused;
    _tasks[index] = task.copyWith(
      status: UploadTaskStatus.paused,
      speedBps: 0,
    );
    _progressSamplesByTaskId.remove(taskId);
    _lastReportedSpeedByTaskId.remove(taskId);
    _lastSpeedUpdateAtByTaskId.remove(taskId);
    notifyListeners();
    _cancelTokenByTaskId[taskId]?.cancel('Paused by user');
  }

  void resumeTask(String taskId) {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) {
      return;
    }

    final task = _tasks[index];
    if (task.status != UploadTaskStatus.paused) {
      return;
    }

    _tasks[index] = task.copyWith(
      status: UploadTaskStatus.queued,
      progress: 0,
      speedBps: 0,
      uploadedBytes: 0,
      totalBytes: max(task.size, 0),
      clearError: true,
    );
    _progressSamplesByTaskId.remove(taskId);
    _lastReportedSpeedByTaskId.remove(taskId);
    _lastSpeedUpdateAtByTaskId.remove(taskId);
    notifyListeners();
    unawaited(_runQueue());
  }

  void cancelTask(String taskId) {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) {
      return;
    }

    final task = _tasks[index];
    if (task.status == UploadTaskStatus.success ||
        task.status == UploadTaskStatus.failed ||
        task.status == UploadTaskStatus.canceled) {
      return;
    }

    if (task.status == UploadTaskStatus.uploading) {
      _stopActionByTaskId[taskId] = _DownloadTaskStopAction.canceled;
      _tasks[index] = task.copyWith(
        status: UploadTaskStatus.canceled,
        progress: 0,
        speedBps: 0,
        uploadedBytes: 0,
        totalBytes: max(task.size, 0),
        clearError: true,
      );
      _progressSamplesByTaskId.remove(taskId);
      _lastReportedSpeedByTaskId.remove(taskId);
      _lastSpeedUpdateAtByTaskId.remove(taskId);
      notifyListeners();
      _cancelTokenByTaskId[taskId]?.cancel('Canceled by user');
      return;
    }

    _tasks[index] = task.copyWith(
      status: UploadTaskStatus.canceled,
      progress: 0,
      speedBps: 0,
      uploadedBytes: 0,
      totalBytes: max(task.size, 0),
      clearError: true,
    );
    _progressSamplesByTaskId.remove(taskId);
    _lastReportedSpeedByTaskId.remove(taskId);
    _lastSpeedUpdateAtByTaskId.remove(taskId);
    notifyListeners();
    unawaited(_runQueue());
  }

  void retryTask(String taskId) {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) {
      return;
    }

    final task = _tasks[index];
    if (task.status != UploadTaskStatus.failed &&
        task.status != UploadTaskStatus.canceled) {
      return;
    }

    final source = _sourceByTaskId[taskId];
    if (source == null) {
      _tasks[index] = task.copyWith(
        status: UploadTaskStatus.failed,
        errorMessage: '文件信息已失效，请重新选择下载。',
      );
      notifyListeners();
      return;
    }

    _tasks[index] = task.copyWith(
      status: UploadTaskStatus.queued,
      progress: 0,
      speedBps: 0,
      uploadedBytes: 0,
      totalBytes: max(task.size, 0),
      clearError: true,
    );
    _progressSamplesByTaskId.remove(taskId);
    _lastReportedSpeedByTaskId.remove(taskId);
    _lastSpeedUpdateAtByTaskId.remove(taskId);
    notifyListeners();
    unawaited(_runQueue());
  }

  Future<void> _runQueue() async {
    if (_isDispatching) {
      return;
    }
    _isDispatching = true;

    try {
      while (_runningDownloads < _maxConcurrentDownloads) {
        final index = _tasks.indexWhere(
          (task) => task.status == UploadTaskStatus.queued,
        );
        if (index < 0) {
          break;
        }

        final task = _tasks[index];
        final source = _sourceByTaskId[task.id];
        if (source == null) {
          _tasks[index] = task.copyWith(
            status: UploadTaskStatus.failed,
            errorMessage: '文件信息已失效，请重新选择下载。',
          );
          notifyListeners();
          continue;
        }

        if (_cookie.isEmpty) {
          _tasks[index] = task.copyWith(
            status: UploadTaskStatus.failed,
            errorMessage: '未设置 Cookie，请先到“我的”保存 Cookie。',
          );
          notifyListeners();
          continue;
        }

        if (_downloadDirectory.isEmpty) {
          _tasks[index] = task.copyWith(
            status: UploadTaskStatus.failed,
            errorMessage: '未设置下载目录，请先到“设置”配置。',
          );
          notifyListeners();
          continue;
        }

        final downloadDirectoryError = await _validateDownloadDirectory();
        if (downloadDirectoryError != null) {
          _tasks[index] = task.copyWith(
            status: UploadTaskStatus.failed,
            errorMessage: downloadDirectoryError,
          );
          notifyListeners();
          continue;
        }

        _tasks[index] = task.copyWith(
          status: UploadTaskStatus.uploading,
          clearError: true,
        );
        _runningDownloads += 1;
        notifyListeners();
        unawaited(_startDownload(taskId: task.id, source: source));
      }
    } finally {
      _isDispatching = false;
    }
  }

  Future<void> _startDownload({
    required String taskId,
    required DriveMaterial source,
  }) async {
    final cancelToken = CancelToken();
    _cancelTokenByTaskId[taskId] = cancelToken;
    try {
      final savePath = _buildSavePath(source.name);
      await _ensureParentDirectory(savePath);
      await _downloadFileHandler(
        cookie: _cookie,
        materialId: source.id,
        savePath: savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final index = _tasks.indexWhere((item) => item.id == taskId);
          if (index < 0) {
            return;
          }
          if (_tasks[index].status != UploadTaskStatus.uploading) {
            return;
          }

          final totalBytes = total > 0 ? total : max(_tasks[index].size, 0);
          final progress =
              totalBytes <= 0 ? 0.0 : (received / totalBytes).clamp(0.0, 0.99);
          final speedBps = _calculateRecentAverageSpeed(taskId, received);

          _tasks[index] = _tasks[index].copyWith(
            status: UploadTaskStatus.uploading,
            progress: progress,
            speedBps: speedBps,
            uploadedBytes: max(received, 0),
            totalBytes: max(totalBytes, 0),
          );
          notifyListeners();
        },
      );

      final index = _tasks.indexWhere((item) => item.id == taskId);
      if (index >= 0) {
        if (_tasks[index].status == UploadTaskStatus.paused ||
            _tasks[index].status == UploadTaskStatus.canceled) {
          return;
        }

        final totalBytes = max(_tasks[index].totalBytes, _tasks[index].size);
        _tasks[index] = _tasks[index].copyWith(
          status: UploadTaskStatus.success,
          progress: 1,
          speedBps: 0,
          uploadedBytes: totalBytes,
          totalBytes: totalBytes,
          errorMessage: null,
          localPath: savePath,
        );
        _progressSamplesByTaskId.remove(taskId);
        _lastReportedSpeedByTaskId.remove(taskId);
        _lastSpeedUpdateAtByTaskId.remove(taskId);
        notifyListeners();
      }
    } catch (error) {
      final index = _tasks.indexWhere((item) => item.id == taskId);
      if (index >= 0) {
        final stopAction = _stopActionByTaskId.remove(taskId);
        if (error is DioException &&
            CancelToken.isCancel(error) &&
            stopAction != null) {
          if (stopAction == _DownloadTaskStopAction.canceled) {
            _tasks[index] = _tasks[index].copyWith(
              status: UploadTaskStatus.canceled,
              progress: 0,
              speedBps: 0,
              uploadedBytes: 0,
              totalBytes: max(_tasks[index].size, 0),
              clearError: true,
            );
          } else {
            _tasks[index] = _tasks[index].copyWith(
              status: UploadTaskStatus.paused,
              speedBps: 0,
              clearError: true,
            );
          }
          _progressSamplesByTaskId.remove(taskId);
          _lastReportedSpeedByTaskId.remove(taskId);
          _lastSpeedUpdateAtByTaskId.remove(taskId);
          notifyListeners();
          return;
        }

        _tasks[index] = _tasks[index].copyWith(
          status: UploadTaskStatus.failed,
          errorMessage: '$error',
        );
        _progressSamplesByTaskId.remove(taskId);
        _lastReportedSpeedByTaskId.remove(taskId);
        _lastSpeedUpdateAtByTaskId.remove(taskId);
        notifyListeners();
      }
    } finally {
      _cancelTokenByTaskId.remove(taskId);
      _stopActionByTaskId.remove(taskId);
      _progressSamplesByTaskId.remove(taskId);
      _lastReportedSpeedByTaskId.remove(taskId);
      _lastSpeedUpdateAtByTaskId.remove(taskId);
      _runningDownloads = max(0, _runningDownloads - 1);
      unawaited(_runQueue());
    }
  }

  String _buildSavePath(String fileName) {
    final normalizedName = fileName.trim().isEmpty ? 'unnamed' : fileName;
    final safeName = normalizedName
        .replaceAll('\\', '_')
        .replaceAll('/', '_')
        .replaceAll(':', '_')
        .replaceAll('*', '_')
        .replaceAll('?', '_')
        .replaceAll('"', '_')
        .replaceAll('<', '_')
        .replaceAll('>', '_')
        .replaceAll('|', '_');
    return p.join(_downloadDirectory, safeName);
  }

  Future<String?> _validateDownloadDirectory() async {
    final normalized = _downloadDirectory.trim();
    if (normalized.isEmpty) {
      return '未设置下载目录，请先到“设置”配置。';
    }

    try {
      final directory = Directory(normalized);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final probeFile = File(p.join(directory.path, '.seewopan_write_probe'));
      await probeFile.writeAsString('ok', flush: true);
      if (await probeFile.exists()) {
        await probeFile.delete();
      }
      return null;
    } catch (_) {
      return '下载目录不可写，请在“设置”中重新选择目录。当前路径：$normalized';
    }
  }

  Future<void> _ensureParentDirectory(String filePath) async {
    final parentPath = p.dirname(filePath);
    final directory = Directory(parentPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  double _calculateRecentAverageSpeed(String taskId, int receivedBytes) {
    const speedWindow = Duration(milliseconds: 500);
    final now = DateTime.now();
    final samples = _progressSamplesByTaskId.putIfAbsent(
      taskId,
      () => <_ProgressSample>[],
    );
    samples.add(
      _ProgressSample(
        receivedBytes: receivedBytes,
        timestamp: now,
      ),
    );

    final cutoff = now.subtract(speedWindow);
    while (samples.length >= 2 && samples[1].timestamp.isBefore(cutoff)) {
      samples.removeAt(0);
    }
    if (samples.length < 2) {
      return 0;
    }

    final first = samples.first;
    final last = samples.last;
    final deltaBytes = last.receivedBytes - first.receivedBytes;
    final deltaMs = last.timestamp.difference(first.timestamp).inMilliseconds;
    if (deltaBytes <= 0 || deltaMs <= 0) {
      return 0;
    }

    // Keep a small bounded history per task.
    if (samples.length > 32) {
      samples.removeRange(0, samples.length - 32);
    }

    final previousUpdateAt = _lastSpeedUpdateAtByTaskId[taskId];
    final previousReported = _lastReportedSpeedByTaskId[taskId] ?? 0;
    if (previousUpdateAt != null &&
        now.difference(previousUpdateAt) < speedWindow) {
      return previousReported;
    }

    final computed = deltaBytes * 1000 / deltaMs;
    _lastReportedSpeedByTaskId[taskId] = computed;
    _lastSpeedUpdateAtByTaskId[taskId] = now;
    return computed;
  }

  String _createTaskId(DateTime now) {
    final millis = now.millisecondsSinceEpoch.toRadixString(16);
    final randomPart =
        _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '$millis$randomPart';
  }
}

class _ProgressSample {
  const _ProgressSample({
    required this.receivedBytes,
    required this.timestamp,
  });

  final int receivedBytes;
  final DateTime timestamp;
}
