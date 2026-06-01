import 'dart:io';

import '../../shared/models/drive_material.dart';
import 'webdav_path.dart';

String buildPropfindResponse({
  required WebDavPath path,
  required DriveMaterial? material,
  required List<DriveMaterial> children,
}) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<D:multistatus xmlns:D="DAV:">');

  if (path.isRoot) {
    _writeResponse(
      buffer,
      href: '/',
      displayName: 'SeewoPan',
      isCollection: true,
      size: 0,
      mimeType: 'httpd/unix-directory',
      updatedAt: null,
    );
  } else if (material != null) {
    _writeResponse(
      buffer,
      href: path.href,
      displayName: material.name,
      isCollection: material.isFolder,
      size: material.size,
      mimeType: material.mimeType,
      updatedAt: material.updatedAt,
    );
  }

  for (final child in children) {
    _writeResponse(
      buffer,
      href: WebDavPath.hrefForMaterial(path.segments, child),
      displayName: child.name,
      isCollection: child.isFolder,
      size: child.size,
      mimeType: child.mimeType,
      updatedAt: child.updatedAt,
    );
  }

  buffer.writeln('</D:multistatus>');
  return buffer.toString();
}

void writeWebDavError(
  HttpResponse response,
  int statusCode,
  String message,
) {
  response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.text
    ..write(message);
}

void copyWebDavHeader(
  Map<String, String> source,
  HttpResponse response,
  String header,
) {
  final value = source[header];
  if (value != null && value.isNotEmpty) {
    response.headers.set(header, value);
  }
}

void _writeResponse(
  StringBuffer buffer, {
  required String href,
  required String displayName,
  required bool isCollection,
  required int size,
  required String mimeType,
  required String? updatedAt,
}) {
  buffer
    ..writeln('  <D:response>')
    ..writeln('    <D:href>${_xmlEscape(href)}</D:href>')
    ..writeln('    <D:propstat>')
    ..writeln('      <D:prop>')
    ..writeln(
        '        <D:displayname>${_xmlEscape(displayName)}</D:displayname>')
    ..writeln('        <D:resourcetype>'
        '${isCollection ? '<D:collection/>' : ''}</D:resourcetype>')
    ..writeln('        <D:getcontentlength>'
        '${isCollection ? 0 : size}</D:getcontentlength>')
    ..writeln(
        '        <D:getcontenttype>${_xmlEscape(mimeType)}</D:getcontenttype>')
    ..writeln('        <D:getlastmodified>'
        '${_xmlEscape(_httpDate(updatedAt))}</D:getlastmodified>')
    ..writeln(
        '        <D:getetag>"${_xmlEscape('$href-$size-$updatedAt')}"</D:getetag>')
    ..writeln('      </D:prop>')
    ..writeln('      <D:status>HTTP/1.1 200 OK</D:status>')
    ..writeln('    </D:propstat>')
    ..writeln('  </D:response>');
}

String _httpDate(String? raw) {
  final parsed = raw == null ? null : DateTime.tryParse(raw);
  return HttpDate.format((parsed ?? DateTime.now()).toUtc());
}

String _xmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
