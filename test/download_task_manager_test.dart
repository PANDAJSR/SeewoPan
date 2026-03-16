import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewopan/features/transfer/download_task_manager.dart';
import 'package:seewopan/features/transfer/upload_task_manager.dart';
import 'package:seewopan/shared/models/drive_material.dart';
import 'package:seewopan/shared/pinco_api_client.dart';

void main() {
  test('respects max concurrent downloads setting', () async {
    var active = 0;
    var maxObserved = 0;
    final release = Completer<void>();

    final manager = DownloadTaskManager(
      apiClient: PincoApiClient(),
      downloadFileHandler: ({
        required String cookie,
        required String materialId,
        required String savePath,
        CancelToken? cancelToken,
        ProgressCallback? onReceiveProgress,
      }) async {
        active += 1;
        if (active > maxObserved) {
          maxObserved = active;
        }
        onReceiveProgress?.call(256, 1024);
        await release.future;
        active -= 1;
      },
    );

    manager.updateCookie('token=abc');
    manager.updateDownloadDirectory('/tmp');
    manager.updateMaxConcurrentDownloads(2);

    await manager.enqueueMaterials([
      const DriveMaterial(
        id: '1',
        folderId: '0',
        name: 'a.txt',
        size: 1024,
        mimeType: 'text/plain',
      ),
      const DriveMaterial(
        id: '2',
        folderId: '0',
        name: 'b.txt',
        size: 1024,
        mimeType: 'text/plain',
      ),
      const DriveMaterial(
        id: '3',
        folderId: '0',
        name: 'c.txt',
        size: 1024,
        mimeType: 'text/plain',
      ),
    ]);

    await _waitUntil(() {
      final uploading = manager.tasks
          .where((task) => task.status == UploadTaskStatus.uploading)
          .length;
      return uploading == 2;
    });

    expect(maxObserved, 2);

    release.complete();
    await _waitUntil(() {
      return manager.tasks.length == 3 &&
          manager.tasks
              .every((task) => task.status == UploadTaskStatus.success);
    });
  });

  test('marks task failed when download directory is missing', () async {
    final manager = DownloadTaskManager(apiClient: PincoApiClient());
    manager.updateCookie('token=abc');

    await manager.enqueueMaterials([
      const DriveMaterial(
        id: '1',
        folderId: '0',
        name: 'a.txt',
        size: 1024,
        mimeType: 'text/plain',
      ),
    ]);

    await _waitUntil(() {
      return manager.tasks.isNotEmpty &&
          manager.tasks.first.status == UploadTaskStatus.failed;
    });

    expect(manager.tasks.first.errorMessage, contains('未设置下载目录'));
  });
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
  Duration step = const Duration(milliseconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(step);
  }
  fail('Timed out waiting for condition.');
}
