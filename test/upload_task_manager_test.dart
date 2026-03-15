import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewopan/features/transfer/upload_task_manager.dart';
import 'package:seewopan/shared/pinco_api_client.dart';

class _FakePincoApiClient extends PincoApiClient {
  _FakePincoApiClient(this._resultCompleter);

  final Completer<UploadFileResult> _resultCompleter;

  @override
  Future<UploadFileResult> uploadFileBytes({
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
    return _resultCompleter.future;
  }
}

void main() {
  test('keeps progress below 100% until upload actually finishes', () async {
    final resultCompleter = Completer<UploadFileResult>();
    final apiClient = _FakePincoApiClient(resultCompleter);
    final manager = UploadTaskManager(apiClient: apiClient);

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
