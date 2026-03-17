import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../shared/pinco_api_client.dart';
import 'upload_task_models.dart';

export 'upload_task_models.dart';

typedef UploadFileHandler = Future<UploadFileResult> Function({
  required String cookie,
  required Uint8List bytes,
  required String fileName,
  String parentFolderId,
  String? mimeType,
  CancelToken? cancelToken,
  UploadProgressCallback? onProgress,
});

enum _TaskStopAction {
  paused,
  canceled,
}

class UploadTaskManager extends ChangeNotifier {
  UploadTaskManager({
    required PincoApiClient apiClient,
    UploadFileHandler? uploadFileHandler,
  }) : _uploadFileHandler = uploadFileHandler ?? apiClient.uploadFileBytes;
  final UploadFileHandler _uploadFileHandler;
  final List<UploadTaskItem> _tasks = <UploadTaskItem>[];
  final Map<String, UploadSourceFile> _sourceByTaskId =
      <String, UploadSourceFile>{};
  final Map<String, CancelToken> _cancelTokenByTaskId = <String, CancelToken>{};
  final Map<String, _TaskStopAction> _stopActionByTaskId =
      <String, _TaskStopAction>{};
  final Map<String, _ProgressSample> _progressSampleByTaskId =
      <String, _ProgressSample>{};
  final Random _random = Random();

  String _cookie = '';
  bool _isDispatching = false;
  int _runningUploads = 0;
  int _maxConcurrentUploads = 3;

  List<UploadTaskItem> get tasks => List<UploadTaskItem>.unmodifiable(_tasks);
  int get maxConcurrentUploads => _maxConcurrentUploads;

  List<UploadTaskItem> get activeTasks => _tasks
      .where((task) =>
          task.status == UploadTaskStatus.queued ||
          task.status == UploadTaskStatus.uploading)
      .toList(growable: false);
  double get totalUploadingSpeedBps => _tasks
      .where((task) => task.status == UploadTaskStatus.uploading)
      .fold(0.0, (sum, task) => sum + task.speedBps);

  void updateCookie(String value) {
    _cookie = value.trim();
  }

  void updateMaxConcurrentUploads(int value) {
    final normalized = value.clamp(1, 10);
    if (normalized == _maxConcurrentUploads) {
      return;
    }
    _maxConcurrentUploads = normalized;
    notifyListeners();
    unawaited(_runQueue());
  }

  Future<void> enqueueFiles(List<UploadSourceFile> files) async {
    if (files.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final added = files.map((file) {
      final taskId = _createTaskId(now);
      _sourceByTaskId[taskId] = file;
      return UploadTaskItem(
        id: taskId,
        taskType: TransferTaskType.upload,
        name: file.name,
        size: file.bytes.length,
        parentFolderId: file.parentFolderId,
        status: UploadTaskStatus.queued,
        createdAt: now,
        progress: 0,
        speedBps: 0,
        uploadedBytes: 0,
        totalBytes: file.bytes.length,
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

    _stopActionByTaskId[taskId] = _TaskStopAction.paused;
    _tasks[index] = task.copyWith(
      status: UploadTaskStatus.paused,
      speedBps: 0,
    );
    _progressSampleByTaskId.remove(taskId);
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
      totalBytes: task.size,
      clearError: true,
    );
    _progressSampleByTaskId.remove(taskId);
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
      _stopActionByTaskId[taskId] = _TaskStopAction.canceled;
      _tasks[index] = task.copyWith(
        status: UploadTaskStatus.canceled,
        progress: 0,
        speedBps: 0,
        uploadedBytes: 0,
        totalBytes: task.size,
        clearError: true,
      );
      _progressSampleByTaskId.remove(taskId);
      notifyListeners();
      _cancelTokenByTaskId[taskId]?.cancel('Canceled by user');
      return;
    }

    _tasks[index] = task.copyWith(
      status: UploadTaskStatus.canceled,
      progress: 0,
      speedBps: 0,
      uploadedBytes: 0,
      totalBytes: task.size,
      clearError: true,
    );
    _progressSampleByTaskId.remove(taskId);
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
    if (source == null || source.bytes.isEmpty) {
      _tasks[index] = task.copyWith(
        status: UploadTaskStatus.failed,
        errorMessage: '文件数据已失效，请重新选择文件。',
      );
      notifyListeners();
      return;
    }

    _tasks[index] = task.copyWith(
      status: UploadTaskStatus.queued,
      progress: 0,
      speedBps: 0,
      uploadedBytes: 0,
      totalBytes: task.size,
      clearError: true,
    );
    _progressSampleByTaskId.remove(taskId);
    notifyListeners();
    unawaited(_runQueue());
  }

  Future<void> _runQueue() async {
    if (_isDispatching) {
      return;
    }
    _isDispatching = true;

    try {
      while (_runningUploads < _maxConcurrentUploads) {
        final index = _tasks.indexWhere(
          (task) => task.status == UploadTaskStatus.queued,
        );
        if (index < 0) {
          break;
        }

        final task = _tasks[index];
        final source = _sourceByTaskId[task.id];
        if (source == null || source.bytes.isEmpty) {
          _tasks[index] = task.copyWith(
            status: UploadTaskStatus.failed,
            errorMessage: '文件数据已失效，请重新选择文件。',
          );
          _sourceByTaskId.remove(task.id);
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

        _tasks[index] = task.copyWith(
          status: UploadTaskStatus.uploading,
          clearError: true,
        );
        _runningUploads += 1;
        notifyListeners();
        unawaited(_startUpload(taskId: task.id, source: source));
      }
    } finally {
      _isDispatching = false;
    }
  }

  Future<void> _startUpload({
    required String taskId,
    required UploadSourceFile source,
  }) async {
    final cancelToken = CancelToken();
    _cancelTokenByTaskId[taskId] = cancelToken;

    try {
      final result = await _uploadFileHandler(
        cookie: _cookie,
        bytes: source.bytes,
        fileName: source.name,
        parentFolderId: source.parentFolderId,
        cancelToken: cancelToken,
        onProgress: (progress) {
          final index = _tasks.indexWhere((item) => item.id == taskId);
          if (index < 0) {
            return;
          }
          if (_tasks[index].status != UploadTaskStatus.uploading) {
            return;
          }
          _tasks[index] = _tasks[index].copyWith(
            status: UploadTaskStatus.uploading,
            progress: progress.progress.clamp(0.0, 0.99),
            speedBps: _calculateInstantSpeed(taskId, progress.sentBytes),
            uploadedBytes: progress.sentBytes,
            totalBytes: progress.totalBytes,
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
        _tasks[index] = _tasks[index].copyWith(
          status: UploadTaskStatus.success,
          progress: 1,
          speedBps: 0,
          uploadedBytes: result.size,
          totalBytes: result.size,
          downloadUrl: result.downloadUrl,
          errorMessage: null,
        );
        _progressSampleByTaskId.remove(taskId);
        _sourceByTaskId.remove(taskId);
        notifyListeners();
      }
    } catch (error) {
      final index = _tasks.indexWhere((item) => item.id == taskId);
      if (index >= 0) {
        final stopAction = _stopActionByTaskId.remove(taskId);
        if (error is DioException &&
            CancelToken.isCancel(error) &&
            stopAction != null) {
          if (stopAction == _TaskStopAction.canceled) {
            _tasks[index] = _tasks[index].copyWith(
              status: UploadTaskStatus.canceled,
              progress: 0,
              speedBps: 0,
              uploadedBytes: 0,
              totalBytes: _tasks[index].size,
              clearError: true,
            );
          } else {
            _tasks[index] = _tasks[index].copyWith(
              status: UploadTaskStatus.paused,
              speedBps: 0,
              clearError: true,
            );
          }
          _progressSampleByTaskId.remove(taskId);
          notifyListeners();
          return;
        }
        _tasks[index] = _tasks[index].copyWith(
          status: UploadTaskStatus.failed,
          errorMessage: '$error',
        );
        _progressSampleByTaskId.remove(taskId);
        notifyListeners();
      }
    } finally {
      _cancelTokenByTaskId.remove(taskId);
      _stopActionByTaskId.remove(taskId);
      _progressSampleByTaskId.remove(taskId);
      _runningUploads = max(0, _runningUploads - 1);
      unawaited(_runQueue());
    }
  }

  double _calculateInstantSpeed(String taskId, int sentBytes) {
    final now = DateTime.now();
    final previous = _progressSampleByTaskId[taskId];
    _progressSampleByTaskId[taskId] = _ProgressSample(
      sentBytes: sentBytes,
      timestamp: now,
    );
    if (previous == null) {
      return 0;
    }

    final deltaBytes = sentBytes - previous.sentBytes;
    final deltaMs = now.difference(previous.timestamp).inMilliseconds;
    if (deltaBytes <= 0 || deltaMs <= 0) {
      return 0;
    }
    return deltaBytes * 1000 / deltaMs;
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
    required this.sentBytes,
    required this.timestamp,
  });

  final int sentBytes;
  final DateTime timestamp;
}
