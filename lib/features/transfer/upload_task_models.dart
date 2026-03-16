import 'package:flutter/foundation.dart';

enum UploadTaskStatus {
  queued,
  uploading,
  paused,
  canceled,
  success,
  failed,
}

enum TransferTaskType {
  upload,
  download,
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
    required this.taskType,
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
    this.localPath,
  });

  final String id;
  final TransferTaskType taskType;
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
  final String? localPath;

  UploadTaskItem copyWith({
    UploadTaskStatus? status,
    double? progress,
    double? speedBps,
    int? uploadedBytes,
    int? totalBytes,
    String? errorMessage,
    bool clearError = false,
    String? downloadUrl,
    String? localPath,
  }) {
    return UploadTaskItem(
      id: id,
      taskType: taskType,
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
      localPath: localPath ?? this.localPath,
    );
  }
}
