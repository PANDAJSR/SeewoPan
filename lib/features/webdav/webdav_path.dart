import '../../shared/models/drive_material.dart';

class WebDavPath {
  const WebDavPath({
    required this.rawPath,
    required this.segments,
  });

  factory WebDavPath.parse(Uri uri) {
    final decoded = uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    return WebDavPath(rawPath: uri.path, segments: decoded);
  }

  final String rawPath;
  final List<String> segments;

  bool get isRoot => segments.isEmpty;

  String get name => isRoot ? '' : segments.last;

  List<String> get parentSegments =>
      isRoot ? const <String>[] : segments.sublist(0, segments.length - 1);

  String get href => hrefForSegments(segments, isCollection: isRoot);

  static String hrefForMaterial(
    List<String> parentSegments,
    DriveMaterial material,
  ) {
    return hrefForSegments(
      <String>[...parentSegments, material.name],
      isCollection: material.isFolder,
    );
  }

  static String hrefForSegments(
    List<String> segments, {
    required bool isCollection,
  }) {
    if (segments.isEmpty) {
      return '/';
    }
    final encoded = segments.map(Uri.encodeComponent).join('/');
    return isCollection ? '/$encoded/' : '/$encoded';
  }
}
