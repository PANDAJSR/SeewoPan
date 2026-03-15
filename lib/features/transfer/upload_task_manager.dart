import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../shared/pinco_api_client.dart';

enum UploadTaskStatus {
  queued,
  uploading,
  success,
  failed,
}

class UploadSourceFile {
  const UploadSourceFile({
    required this.name,
    required this.bytes,
    required this.parentFolderId,
  });

  final String name;
  final Uint8List bytes;
  final String parentFolderId;
}

class UploadTaskItem {
  const UploadTaskItem({
    required this.id,
    required this.name,
    required this.size,
    required this.parentFolderId,
    required this.status,
    required this.createdAt,
    required this.progress,
    required this.speedBps,
    required this.uploadedBytes,
    required this.totalBytes,
    this.errorMessage,
    this.downloadUrl,
  });

  final String id;
  final String name;
  final int size;
  final String parentFolderId;
  final UploadTaskStatus status;
  final DateTime createdAt;
  final double progress;
  final double speedBps;
  final int uploadedBytes;
  final int totalBytes;
  final String? errorMessage;
  final String? downloadUrl;

  UploadTaskItem copyWith({
    UploadTaskStatus? status,
    double? progress,
    double? speedBps,
    int? uploadedBytes,
    int? totalBytes,
    String? errorMessage,
    bool clearError = false,
    String? downloadUrl,
  }) {
    return UploadTaskItem(
      id: id,
      name: name,
      size: size,
      parentFolderId: parentFolderId,
      status: status ?? this.status,
      createdAt: createdAt,
      progress: progress ?? this.progress,
      speedBps: speedBps ?? this.speedBps,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      downloadUrl: downloadUrl ?? this.downloadUrl,
    );
  }
}

class UploadTaskManager extends ChangeNotifier {
  UploadTaskManager({required PincoApiClient apiClient})
      : _apiClient = apiClient;

  final PincoApiClient _apiClient;
  final List<UploadTaskItem> _tasks = <UploadTaskItem>[];
  final Map<String, UploadSourceFile> _sourceByTaskId =
      <String, UploadSourceFile>{};
  final Random _random = Random();

  String _cookie = '';
  bool _running = false;

  List<UploadTaskItem> get tasks => List<UploadTaskItem>.unmodifiable(_tasks);

  List<UploadTaskItem> get activeTasks => _tasks
      .where((task) =>
          task.status == UploadTaskStatus.queued ||
          task.status == UploadTaskStatus.uploading)
      .toList(growable: false);

  void updateCookie(String value) {
    _cookie = value.trim();
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

  Future<void> _runQueue() async {
    if (_running) {
      return;
    }
    _running = true;

    try {
      for (var i = 0; i < _tasks.length; i++) {
        final task = _tasks[i];
        if (task.status != UploadTaskStatus.queued) {
          continue;
        }

        final source = _sourceByTaskId[task.id];

        if (source == null || source.bytes.isEmpty) {
          _tasks[i] = task.copyWith(
            status: UploadTaskStatus.failed,
            errorMessage: '文件数据已失效，请重新选择文件。',
          );
          _sourceByTaskId.remove(task.id);
          notifyListeners();
          continue;
        }

        if (_cookie.isEmpty) {
          _tasks[i] = task.copyWith(
            status: UploadTaskStatus.failed,
            errorMessage: '未设置 Cookie，请先到“我的”保存 Cookie。',
          );
          notifyListeners();
          continue;
        }

        _tasks[i] = task.copyWith(
          status: UploadTaskStatus.uploading,
          clearError: true,
        );
        notifyListeners();

        try {
          final result = await _apiClient.uploadFileBytes(
            cookie: _cookie,
            bytes: source.bytes,
            fileName: source.name,
            parentFolderId: source.parentFolderId,
            onProgress: (progress) {
              final index = _tasks.indexWhere((item) => item.id == task.id);
              if (index < 0) {
                return;
              }
              _tasks[index] = _tasks[index].copyWith(
                status: UploadTaskStatus.uploading,
                progress: progress.progress.clamp(0.0, 0.99),
                speedBps: progress.speedBps,
                uploadedBytes: progress.sentBytes,
                totalBytes: progress.totalBytes,
              );
              notifyListeners();
            },
          );

          final index = _tasks.indexWhere((item) => item.id == task.id);
          if (index >= 0) {
            _tasks[index] = _tasks[index].copyWith(
              status: UploadTaskStatus.success,
              progress: 1,
              speedBps: result.metrics.uploadSpeedBps,
              uploadedBytes: result.size,
              totalBytes: result.size,
              downloadUrl: result.downloadUrl,
              errorMessage: null,
            );
            _sourceByTaskId.remove(task.id);
            notifyListeners();
          }
        } catch (error) {
          final index = _tasks.indexWhere((item) => item.id == task.id);
          if (index >= 0) {
            _tasks[index] = _tasks[index].copyWith(
              status: UploadTaskStatus.failed,
              errorMessage: '$error',
            );
            _sourceByTaskId.remove(task.id);
            notifyListeners();
          }
        }
      }
    } finally {
      _running = false;
    }
  }

  String _createTaskId(DateTime now) {
    final millis = now.millisecondsSinceEpoch.toRadixString(16);
    final randomPart =
        _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '$millis$randomPart';
  }
}
