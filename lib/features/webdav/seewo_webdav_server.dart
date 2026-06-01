import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';

import '../../shared/models/drive_material.dart';
import '../../shared/pinco_api_client.dart';
import 'webdav_auth.dart';
import 'webdav_drive_gateway.dart';
import 'webdav_path.dart';
import 'webdav_response.dart';
import 'webdav_settings.dart';

part 'webdav_direct_link_api.dart';

class SeewoWebDavServer {
  SeewoWebDavServer({required PincoApiClient apiClient})
      : _apiClient = apiClient {
    _gateway = WebDavDriveGateway(apiClient: apiClient, cookie: () => _cookie);
  }

  final PincoApiClient _apiClient;
  late final WebDavDriveGateway _gateway;
  HttpServer? _server;
  WebDavSettings _settings = WebDavSettings.defaults;
  String _cookie = '';

  bool get isRunning => _server != null;

  Uri? get uri {
    final server = _server;
    if (server == null) {
      return null;
    }
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/',
    );
  }

  Future<void> start({
    required WebDavSettings settings,
    required String cookie,
  }) async {
    if (isRunning) {
      await stop();
    }
    _settings = settings;
    _cookie = cookie;
    _server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, settings.port);
    unawaited(_serve(_server!));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  void updateCookie(String cookie) {
    _cookie = cookie;
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (!isWebDavAuthorized(request, _settings)) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.set(
            HttpHeaders.wwwAuthenticateHeader,
            'Basic realm="SeewoPan WebDAV"',
          );
        return;
      }
      if (isDirectLinkApiRequest(request)) {
        await _handleDirectLinkApi(request);
        return;
      }
      if (_cookie.trim().isEmpty) {
        writeWebDavError(
          request.response,
          HttpStatus.serviceUnavailable,
          'Seewo cookie is not configured.',
        );
        return;
      }

      switch (request.method.toUpperCase()) {
        case 'OPTIONS':
          _handleOptions(request);
        case 'PROPFIND':
          await _handlePropfind(request);
        case 'HEAD':
          await _handleHead(request);
        case 'GET':
          await _handleGet(request);
        case 'PUT':
          await _handlePut(request);
        case 'DELETE':
          await _handleDelete(request);
        case 'MKCOL':
          await _handleMkcol(request);
        case 'MOVE':
          await _handleMove(request);
        case 'LOCK':
          _handleLock(request);
        case 'UNLOCK':
          request.response.statusCode = HttpStatus.noContent;
        default:
          writeWebDavError(
            request.response,
            HttpStatus.notImplemented,
            'Unsupported WebDAV method.',
          );
      }
    } catch (error) {
      writeWebDavError(
        request.response,
        HttpStatus.internalServerError,
        error.toString(),
      );
    } finally {
      await request.response.close();
    }
  }

  void _handleOptions(HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.set('DAV', '1, 2')
      ..headers.set(
        'Allow',
        'OPTIONS, PROPFIND, GET, HEAD, PUT, DELETE, MKCOL, MOVE, LOCK, UNLOCK',
      )
      ..headers.set('MS-Author-Via', 'DAV');
  }

  Future<void> _handlePropfind(HttpRequest request) async {
    final depth = request.headers.value('Depth') ?? 'infinity';
    final path = WebDavPath.parse(request.uri);
    final resolved = await _gateway.resolve(path.segments);
    if (!path.isRoot && resolved.material == null) {
      writeWebDavError(request.response, HttpStatus.notFound, 'Not found.');
      return;
    }

    final canListChildren =
        depth != '0' && (path.isRoot || resolved.material?.isFolder == true);
    final children = canListChildren
        ? await _gateway.listAll(resolved.material?.id ?? '0')
        : const <DriveMaterial>[];
    final xml = buildPropfindResponse(
      path: path,
      material: resolved.material,
      children: children,
    );

    request.response
      ..statusCode = 207
      ..headers.contentType =
          ContentType('application', 'xml', charset: 'utf-8')
      ..write(xml);
  }

  Future<void> _handleHead(HttpRequest request) async {
    final resolved = await _requireFile(
      WebDavPath.parse(request.uri),
      request.response,
    );
    if (resolved == null) {
      return;
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentLength = resolved.size
      ..headers.contentType = _gateway.contentTypeFor(resolved);
  }

  Future<void> _handleGet(HttpRequest request) async {
    final material = await _requireFile(
      WebDavPath.parse(request.uri),
      request.response,
    );
    if (material == null) {
      return;
    }

    final upstream = await _apiClient.openMaterialDownloadStream(
      cookie: _cookie,
      materialId: material.id,
      range: request.headers.value(HttpHeaders.rangeHeader),
    );
    request.response.statusCode = upstream.statusCode;
    copyWebDavHeader(
      upstream.headers,
      request.response,
      HttpHeaders.contentTypeHeader,
    );
    copyWebDavHeader(
      upstream.headers,
      request.response,
      HttpHeaders.contentLengthHeader,
    );
    copyWebDavHeader(
      upstream.headers,
      request.response,
      HttpHeaders.contentRangeHeader,
    );
    copyWebDavHeader(
      upstream.headers,
      request.response,
      HttpHeaders.acceptRangesHeader,
    );
    if (request.response.headers.value(HttpHeaders.contentTypeHeader) == null) {
      request.response.headers.contentType = _gateway.contentTypeFor(material);
    }
    await request.response.addStream(upstream.stream);
  }

  Future<void> _handlePut(HttpRequest request) async {
    final path = WebDavPath.parse(request.uri);
    if (path.isRoot) {
      writeWebDavError(request.response, HttpStatus.conflict, 'Invalid path.');
      return;
    }
    final parent = await _gateway.resolve(path.parentSegments);
    if (parent.material == null && path.parentSegments.isNotEmpty) {
      writeWebDavError(
          request.response, HttpStatus.conflict, 'Parent missing.');
      return;
    }
    if (parent.material != null && !parent.material!.isFolder) {
      writeWebDavError(
          request.response, HttpStatus.conflict, 'Parent is file.');
      return;
    }

    final existing =
        await _gateway.findChild(parent.material?.id ?? '0', path.name);
    if (existing?.isFolder == true) {
      writeWebDavError(request.response, HttpStatus.conflict, 'Folder exists.');
      return;
    }

    await _apiClient.uploadFileStream(
      cookie: _cookie,
      stream: request,
      fileName: path.name,
      parentFolderId: parent.material?.id ?? '0',
      contentLength: request.headers.contentLength,
      mimeType: lookupMimeType(path.name),
    );
    if (existing != null) {
      await _apiClient.deleteMaterials(
        cookie: _cookie,
        materialIds: [existing.id],
      );
    }
    request.response.statusCode =
        existing == null ? HttpStatus.created : HttpStatus.noContent;
  }

  Future<void> _handleDelete(HttpRequest request) async {
    final path = WebDavPath.parse(request.uri);
    final resolved = await _gateway.resolve(path.segments);
    if (path.isRoot || resolved.material == null) {
      writeWebDavError(request.response, HttpStatus.notFound, 'Not found.');
      return;
    }
    await _apiClient.deleteMaterials(
      cookie: _cookie,
      materialIds: [resolved.material!.id],
    );
    request.response.statusCode = HttpStatus.noContent;
  }

  Future<void> _handleMkcol(HttpRequest request) async {
    final path = WebDavPath.parse(request.uri);
    if (path.isRoot) {
      writeWebDavError(request.response, HttpStatus.methodNotAllowed, 'Root.');
      return;
    }
    final parent = await _gateway.resolve(path.parentSegments);
    if (parent.material == null && path.parentSegments.isNotEmpty) {
      writeWebDavError(
          request.response, HttpStatus.conflict, 'Parent missing.');
      return;
    }
    final existing =
        await _gateway.findChild(parent.material?.id ?? '0', path.name);
    if (existing != null) {
      writeWebDavError(
          request.response, HttpStatus.methodNotAllowed, 'Exists.');
      return;
    }
    await _apiClient.createFolder(
      cookie: _cookie,
      name: path.name,
      parentFolderId: parent.material?.id ?? '0',
    );
    request.response.statusCode = HttpStatus.created;
  }

  Future<void> _handleMove(HttpRequest request) async {
    final sourcePath = WebDavPath.parse(request.uri);
    final source = await _gateway.resolve(sourcePath.segments);
    if (sourcePath.isRoot || source.material == null) {
      writeWebDavError(request.response, HttpStatus.notFound, 'Not found.');
      return;
    }

    final destination = request.headers.value('Destination');
    final destinationUri =
        destination == null ? null : Uri.tryParse(destination);
    if (destinationUri == null) {
      writeWebDavError(request.response, HttpStatus.badRequest, 'Destination.');
      return;
    }
    final targetPath = WebDavPath.parse(destinationUri);
    final targetParent = await _gateway.resolve(targetPath.parentSegments);
    if (targetParent.material == null && targetPath.parentSegments.isNotEmpty) {
      writeWebDavError(
          request.response, HttpStatus.conflict, 'Parent missing.');
      return;
    }

    final targetParentId = targetParent.material?.id ?? '0';
    final overwrite = request.headers.value('Overwrite') != 'F';
    final existing = await _gateway.findChild(targetParentId, targetPath.name);
    if (existing != null && !overwrite) {
      writeWebDavError(
          request.response, HttpStatus.preconditionFailed, 'Exists.');
      return;
    }
    if (existing != null) {
      await _apiClient.deleteMaterials(
        cookie: _cookie,
        materialIds: [existing.id],
      );
    }

    if (source.material!.name != targetPath.name) {
      await _apiClient.renameMaterial(
        cookie: _cookie,
        materialId: source.material!.id,
        name: targetPath.name,
      );
    }
    if (source.parentFolderId != targetParentId) {
      await _apiClient.moveMaterials(
        cookie: _cookie,
        materialIds: [source.material!.id],
        targetFolderId: targetParentId,
      );
    }
    request.response.statusCode = HttpStatus.created;
  }

  void _handleLock(HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType =
          ContentType('application', 'xml', charset: 'utf-8')
      ..headers.set('Lock-Token', '<opaquelocktoken:seewopan>')
      ..write('<?xml version="1.0" encoding="utf-8"?>'
          '<D:prop xmlns:D="DAV:"><D:lockdiscovery/></D:prop>');
  }

  Future<DriveMaterial?> _requireFile(
    WebDavPath path,
    HttpResponse response,
  ) async {
    final resolved = await _gateway.resolve(path.segments);
    if (path.isRoot || resolved.material == null) {
      writeWebDavError(response, HttpStatus.notFound, 'Not found.');
      return null;
    }
    if (resolved.material!.isFolder) {
      writeWebDavError(response, HttpStatus.methodNotAllowed, 'Folder.');
      return null;
    }
    return resolved.material;
  }
}
