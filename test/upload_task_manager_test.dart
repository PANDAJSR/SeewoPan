import 'dart:async';
import 'dart:typed_data';

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
