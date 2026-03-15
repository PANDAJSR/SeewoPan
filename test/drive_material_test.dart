import 'package:flutter_test/flutter_test.dart';
import 'package:seewopan/shared/models/drive_material.dart';

void main() {
  test('detects folder item from API payload', () {
    final item = DriveMaterial.fromApi({
      'id': 'folder-1',
      'folderId': 'folder-1',
      'name': '课件目录',
      'type': 'folder',
    });

    expect(item.isFolder, isTrue);
    expect(item.folderId, 'folder-1');
  });

  test('detects file item from API payload', () {
    final item = DriveMaterial.fromApi({
      'id': 'file-1',
      'name': '数学课.pptx',
      'type': 'resource',
      'size': 1024,
      'mimeType':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    });

    expect(item.isFolder, isFalse);
    expect(item.folderId, 'file-1');
  });
}
