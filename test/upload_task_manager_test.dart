import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewopan/features/transfer/upload_task_manager.dart';
import 'package:seewopan/shared/pinco_api_client.dart';

void main() {
  test('keeps progress below 100% until upload actually finishes', () async {
    final resultCompleter = Completer<UploadFileResult>();
    final manager = UploadTaskManager(
      apiClient: PincoApiClient(),
      uploadFileHandler: ({
        required String cookie,
        required Uint8List bytes,
        required String fileName,
        String parentFolderId = '0',
        String? mimeType,
        CancelToken? cancelToken,
        UploadProgressCallback? onProgress,
      }) async {
        onProgress?.call(
          UploadProgress(
            sentBytes: bytes.length,
            totalBytes: bytes.length,
            elapsed: const Duration(milliseconds: 300),
            estimatedProgress: 1,
          ),
        );
        return resultCompleter.future;
      },
    );

    manager.updateCookie('token=abc');
    await manager.enqueueFiles([
      UploadSourceFile(
        name: 'demo.bin',
        bytes: Uint8List.fromList(List<int>.filled(1024, 1)),
        parentFolderId: '0',
      ),
    ]);

    await _waitUntil(() {
      return manager.tasks.isNotEmpty &&
          manager.tasks.first.status == UploadTaskStatus.uploading;
    });

    final uploadingTask = manager.tasks.first;
    expect(uploadingTask.progress, lessThan(1));

    resultCompleter.complete(
      UploadFileResult(
        deduplicated: false,
        name: 'demo.bin',
        size: 1024,
        mimeType: 'application/octet-stream',
        fileMd5: 'md5',
        fileKey: 'file-key',
        downloadUrl: 'https://example.com/file',
        metrics: const UploadMetrics(
          fileSizeBytes: 1024,
          totalElapsed: Duration(seconds: 2),
          uploadElapsed: Duration(seconds: 1),
          uploadSpeedBps: 1024,
        ),
      ),
    );

    await _waitUntil(() {
      return manager.tasks.isNotEmpty &&
          manager.tasks.first.status == UploadTaskStatus.success;
    });

    final successTask = manager.tasks.first;
    expect(successTask.progress, 1);
  });

  test('respects max concurrent uploads setting', () async {
    const delay = Duration(milliseconds: 200);
    var active = 0;
    var maxObservedActive = 0;
    final manager = UploadTaskManager(
      apiClient: PincoApiClient(),
      uploadFileHandler: ({
        required String cookie,
        required Uint8List bytes,
        required String fileName,
        String parentFolderId = '0',
        String? mimeType,
        CancelToken? cancelToken,
        UploadProgressCallback? onProgress,
      }) async {
        active += 1;
        if (active > maxObservedActive) {
          maxObservedActive = active;
        }

        await Future<void>.delayed(delay);
        onProgress?.call(
          UploadProgress(
            sentBytes: bytes.length,
            totalBytes: bytes.length,
            elapsed: delay,
            estimatedProgress: 1,
          ),
        );
        active -= 1;
        return UploadFileResult(
          deduplicated: false,
          name: fileName,
          size: bytes.length,
          mimeType: 'application/octet-stream',
          fileMd5: 'md5',
          fileKey: 'file-key',
          downloadUrl: 'https://example.com/$fileName',
          metrics: UploadMetrics(
            fileSizeBytes: bytes.length,
            totalElapsed: delay,
            uploadElapsed: delay,
            uploadSpeedBps: bytes.length / delay.inMilliseconds * 1000,
          ),
        );
      },
    );

    manager.updateCookie('token=abc');
    manager.updateMaxConcurrentUploads(2);
    await manager.enqueueFiles(
      List<UploadSourceFile>.generate(
        5,
        (index) => UploadSourceFile(
          name: 'file_$index.bin',
          bytes: Uint8List.fromList(List<int>.filled(1024, 1)),
          parentFolderId: '0',
        ),
      ),
    );

    await _waitUntil(() {
      return manager.tasks.length == 5 &&
          manager.tasks
              .every((task) => task.status == UploadTaskStatus.success);
    }, timeout: const Duration(seconds: 5));

    expect(maxObservedActive, 2);
  });

  test('aggregates speed across all uploading tasks', () async {
    final releaseUploads = Completer<void>();
    final manager = UploadTaskManager(
      apiClient: PincoApiClient(),
      uploadFileHandler: ({
        required String cookie,
        required Uint8List bytes,
        required String fileName,
        String parentFolderId = '0',
        String? mimeType,
        CancelToken? cancelToken,
        UploadProgressCallback? onProgress,
      }) async {
        final elapsed = fileName == 'a.bin'
            ? const Duration(milliseconds: 500)
            : const Duration(milliseconds: 250);
        onProgress?.call(
          UploadProgress(
            sentBytes: 256,
            totalBytes: bytes.length,
            elapsed: elapsed,
            estimatedProgress: 0.5,
          ),
        );
        await releaseUploads.future;
        return UploadFileResult(
          deduplicated: false,
          name: fileName,
          size: bytes.length,
          mimeType: 'application/octet-stream',
          fileMd5: 'md5',
          fileKey: 'file-key',
          downloadUrl: 'https://example.com/$fileName',
          metrics: UploadMetrics(
            fileSizeBytes: bytes.length,
            totalElapsed: const Duration(seconds: 1),
            uploadElapsed: const Duration(seconds: 1),
            uploadSpeedBps: 0,
          ),
        );
      },
    );

    manager.updateCookie('token=abc');
    manager.updateMaxConcurrentUploads(2);
    await manager.enqueueFiles([
      UploadSourceFile(
        name: 'a.bin',
        bytes: Uint8List.fromList(List<int>.filled(512, 1)),
        parentFolderId: '0',
      ),
      UploadSourceFile(
        name: 'b.bin',
        bytes: Uint8List.fromList(List<int>.filled(512, 1)),
        parentFolderId: '0',
      ),
    ]);

    await _waitUntil(() {
      final uploading = manager.tasks
          .where((task) => task.status == UploadTaskStatus.uploading)
          .toList(growable: false);
      return uploading.length == 2 &&
          uploading.every((task) => task.speedBps > 0);
    });

    expect(manager.totalUploadingSpeedBps, closeTo(1536.0, 0.001));

    releaseUploads.complete();
    await _waitUntil(() {
      return manager.tasks
          .every((task) => task.status == UploadTaskStatus.success);
    });
  });

  test('supports pause and resume for queued task', () async {
    final releaseUpload = Completer<void>();
    var started = 0;
    final manager = UploadTaskManager(
      apiClient: PincoApiClient(),
      uploadFileHandler: ({
        required String cookie,
        required Uint8List bytes,
        required String fileName,
        String parentFolderId = '0',
        String? mimeType,
        CancelToken? cancelToken,
        UploadProgressCallback? onProgress,
      }) async {
        started += 1;
        await releaseUpload.future;
        return UploadFileResult(
          deduplicated: false,
          name: fileName,
          size: bytes.length,
          mimeType: 'application/octet-stream',
          fileMd5: 'md5',
          fileKey: 'file-key',
          downloadUrl: 'https://example.com/$fileName',
          metrics: const UploadMetrics(
            fileSizeBytes: 1024,
            totalElapsed: Duration(seconds: 1),
            uploadElapsed: Duration(seconds: 1),
            uploadSpeedBps: 1024,
          ),
        );
      },
    );

    manager.updateCookie('token=abc');
    manager.updateMaxConcurrentUploads(1);
    await manager.enqueueFiles([
      UploadSourceFile(
        name: 'first.bin',
        bytes: Uint8List.fromList(List<int>.filled(1024, 1)),
        parentFolderId: '0',
      ),
      UploadSourceFile(
        name: 'second.bin',
        bytes: Uint8List.fromList(List<int>.filled(1024, 2)),
        parentFolderId: '0',
      ),
    ]);

    await _waitUntil(() {
      return manager.tasks.length == 2 &&
          manager.tasks.any((task) => task.status == UploadTaskStatus.queued);
    });
    final queuedId = manager.tasks
        .firstWhere((task) => task.status == UploadTaskStatus.queued)
        .id;

    manager.pauseTask(queuedId);
    expect(
      manager.tasks.firstWhere((task) => task.id == queuedId).status,
      UploadTaskStatus.paused,
    );

    releaseUpload.complete();
    await _waitUntil(() {
      final target = manager.tasks.firstWhere((task) => task.id == queuedId);
      return target.status == UploadTaskStatus.paused;
    });
    expect(started, 1);

    manager.resumeTask(queuedId);
    await _waitUntil(() {
      final target = manager.tasks.firstWhere((task) => task.id == queuedId);
      return target.status == UploadTaskStatus.success;
    });
    expect(started, 2);
  });

  test('supports cancel for uploading task', () async {
    final manager = UploadTaskManager(
      apiClient: PincoApiClient(),
      uploadFileHandler: ({
        required String cookie,
        required Uint8List bytes,
        required String fileName,
        String parentFolderId = '0',
        String? mimeType,
        CancelToken? cancelToken,
        UploadProgressCallback? onProgress,
      }) async {
        onProgress?.call(
          UploadProgress(
            sentBytes: 128,
            totalBytes: bytes.length,
            elapsed: const Duration(milliseconds: 100),
            estimatedProgress: 0.3,
          ),
        );
        await (cancelToken?.whenCancel ?? Future<void>.value());
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: '/mock-upload'),
          reason: 'Canceled by test',
        );
      },
    );

    manager.updateCookie('token=abc');
    await manager.enqueueFiles([
      UploadSourceFile(
        name: 'cancel-me.bin',
        bytes: Uint8List.fromList(List<int>.filled(1024, 1)),
        parentFolderId: '0',
      ),
    ]);

    await _waitUntil(() {
      return manager.tasks.isNotEmpty &&
          manager.tasks.first.status == UploadTaskStatus.uploading;
    });

    final taskId = manager.tasks.first.id;
    manager.cancelTask(taskId);

    await _waitUntil(() {
      return manager.tasks.first.status == UploadTaskStatus.canceled;
    });
    final task = manager.tasks.first;
    expect(task.progress, 0);
    expect(task.uploadedBytes, 0);
  });

  test('supports retry for canceled task', () async {
    var calls = 0;
    final manager = UploadTaskManager(
      apiClient: PincoApiClient(),
      uploadFileHandler: ({
        required String cookie,
        required Uint8List bytes,
        required String fileName,
        String parentFolderId = '0',
        String? mimeType,
        CancelToken? cancelToken,
        UploadProgressCallback? onProgress,
      }) async {
        calls += 1;
        if (calls == 1) {
          await (cancelToken?.whenCancel ?? Future<void>.value());
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: '/mock-upload'),
            reason: 'Canceled by test',
          );
        }
        return UploadFileResult(
          deduplicated: false,
          name: fileName,
          size: bytes.length,
          mimeType: 'application/octet-stream',
          fileMd5: 'md5',
          fileKey: 'file-key',
          downloadUrl: 'https://example.com/$fileName',
          metrics: const UploadMetrics(
            fileSizeBytes: 1024,
            totalElapsed: Duration(seconds: 1),
            uploadElapsed: Duration(seconds: 1),
            uploadSpeedBps: 1024,
          ),
        );
      },
    );

    manager.updateCookie('token=abc');
    await manager.enqueueFiles([
      UploadSourceFile(
        name: 'retry-canceled.bin',
        bytes: Uint8List.fromList(List<int>.filled(1024, 1)),
        parentFolderId: '0',
      ),
    ]);

    await _waitUntil(() {
      return manager.tasks.isNotEmpty &&
          manager.tasks.first.status == UploadTaskStatus.uploading;
    });
    final taskId = manager.tasks.first.id;

    manager.cancelTask(taskId);
    await _waitUntil(() {
      return manager.tasks.first.status == UploadTaskStatus.canceled;
    });

    manager.retryTask(taskId);
    await _waitUntil(() {
      return manager.tasks.first.status == UploadTaskStatus.success;
    });
    expect(calls, 2);
  });

  test('supports retry for failed task', () async {
    var calls = 0;
    final manager = UploadTaskManager(
      apiClient: PincoApiClient(),
      uploadFileHandler: ({
        required String cookie,
        required Uint8List bytes,
        required String fileName,
        String parentFolderId = '0',
        String? mimeType,
        CancelToken? cancelToken,
        UploadProgressCallback? onProgress,
      }) async {
        calls += 1;
        if (calls == 1) {
          throw Exception('mock failed');
        }
        return UploadFileResult(
          deduplicated: false,
          name: fileName,
          size: bytes.length,
          mimeType: 'application/octet-stream',
          fileMd5: 'md5',
          fileKey: 'file-key',
          downloadUrl: 'https://example.com/$fileName',
          metrics: const UploadMetrics(
            fileSizeBytes: 1024,
            totalElapsed: Duration(seconds: 1),
            uploadElapsed: Duration(seconds: 1),
            uploadSpeedBps: 1024,
          ),
        );
      },
    );

    manager.updateCookie('token=abc');
    await manager.enqueueFiles([
      UploadSourceFile(
        name: 'retry-failed.bin',
        bytes: Uint8List.fromList(List<int>.filled(1024, 1)),
        parentFolderId: '0',
      ),
    ]);

    await _waitUntil(() {
      return manager.tasks.isNotEmpty &&
          manager.tasks.first.status == UploadTaskStatus.failed;
    });
    final taskId = manager.tasks.first.id;

    manager.retryTask(taskId);
    await _waitUntil(() {
      return manager.tasks.first.status == UploadTaskStatus.success;
    });
    expect(calls, 2);
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final start = DateTime.now();
  while (!condition()) {
    if (DateTime.now().difference(start) > timeout) {
      fail('Timed out while waiting for condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
