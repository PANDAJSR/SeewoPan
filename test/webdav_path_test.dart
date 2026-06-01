import 'package:flutter_test/flutter_test.dart';
import 'package:seewopan/features/webdav/webdav_path.dart';

void main() {
  test('parses decoded WebDAV path segments', () {
    final path = WebDavPath.parse(Uri.parse('/folder/%E8%AF%95%E5%8D%B7.txt'));

    expect(path.segments, <String>['folder', '试卷.txt']);
    expect(path.parentSegments, <String>['folder']);
    expect(path.name, '试卷.txt');
    expect(path.href, '/folder/%E8%AF%95%E5%8D%B7.txt');
  });

  test('builds collection href with trailing slash', () {
    final href = WebDavPath.hrefForSegments(
      const <String>['课程资料', '第一课'],
      isCollection: true,
    );

    expect(href,
        '/%E8%AF%BE%E7%A8%8B%E8%B5%84%E6%96%99/%E7%AC%AC%E4%B8%80%E8%AF%BE/');
  });
}
