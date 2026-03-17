import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> resolveDefaultDownloadDirectoryPath() async {
  final candidates = <Future<Directory?>>[
    _resolveDownloadsDirectory(),
    _resolveAppSupportDownloadsDirectory(),
    _resolveTempDownloadsDirectory(),
  ];

  for (final future in candidates) {
    final directory = await future;
    if (directory == null) {
      continue;
    }
    if (await _ensureWritableDirectory(directory)) {
      return directory.path;
    }
  }

  return '';
}

Future<Directory?> _resolveDownloadsDirectory() async {
  try {
    final directory = await getDownloadsDirectory().timeout(
      const Duration(milliseconds: 500),
    );
    return directory;
  } catch (_) {
    return null;
  }
}

Future<Directory?> _resolveAppSupportDownloadsDirectory() async {
  try {
    final appSupportDirectory = await getApplicationSupportDirectory().timeout(
      const Duration(milliseconds: 500),
    );
    return Directory(p.join(appSupportDirectory.path, 'Downloads'));
  } catch (_) {
    return null;
  }
}

Future<Directory?> _resolveTempDownloadsDirectory() async {
  try {
    return Directory(p.join(Directory.systemTemp.path, 'seewopan-downloads'));
  } catch (_) {
    return null;
  }
}

Future<bool> _ensureWritableDirectory(Directory directory) async {
  try {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final probe = File(p.join(directory.path, '.seewopan_write_probe'));
    await probe.writeAsString('ok', flush: true);
    if (await probe.exists()) {
      await probe.delete();
    }
    return true;
  } catch (_) {
    return false;
  }
}
