part of 'seewo_webdav_server.dart';

const _directLinkApiPath = '/__seewopan/api/download-link';

bool isDirectLinkApiRequest(HttpRequest request) {
  return request.uri.path == _directLinkApiPath;
}

extension _SeewoWebDavDirectLinkApi on SeewoWebDavServer {
  Future<void> _handleDirectLinkApi(HttpRequest request) async {
    if (request.method.toUpperCase() != 'GET') {
      request.response.headers.set(HttpHeaders.allowHeader, 'GET');
      _writeDirectLinkJsonError(
        request.response,
        HttpStatus.methodNotAllowed,
        'Method not allowed.',
      );
      return;
    }
    if (_cookie.trim().isEmpty) {
      _writeDirectLinkJsonError(
        request.response,
        HttpStatus.serviceUnavailable,
        'Seewo cookie is not configured.',
      );
      return;
    }

    final query = request.uri.queryParameters;
    final materialId = query['id']?.trim();
    final path = query['path']?.trim();
    DriveMaterial? material;
    String? resolvedMaterialId = materialId;

    if (resolvedMaterialId == null || resolvedMaterialId.isEmpty) {
      if (path == null || path.isEmpty) {
        _writeDirectLinkJsonError(
          request.response,
          HttpStatus.badRequest,
          'Missing required query parameter: path or id.',
        );
        return;
      }
      final normalizedPath = path.startsWith('/') ? path : '/$path';
      final resolved = await _gateway.resolve(
        WebDavPath.parse(Uri(path: normalizedPath)).segments,
      );
      material = resolved.material;
      if (material == null) {
        _writeDirectLinkJsonError(
          request.response,
          HttpStatus.notFound,
          'File not found.',
        );
        return;
      }
      if (material.isFolder) {
        _writeDirectLinkJsonError(
          request.response,
          HttpStatus.methodNotAllowed,
          'Path points to a folder.',
        );
        return;
      }
      resolvedMaterialId = material.id;
    }

    final preview = await _apiClient.getMaterialPreview(
      cookie: _cookie,
      materialId: resolvedMaterialId,
    );
    final directUrl = preview.downloadUrl ?? preview.previewUrl;

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode(
          <String, Object?>{
            'materialId': resolvedMaterialId,
            'name': material?.name,
            'size': material?.size,
            'mimeType': material?.mimeType,
            'url': directUrl,
            'source':
                preview.downloadUrl == null ? 'previewUrl' : 'downloadUrl',
          },
        ),
      );
  }

  void _writeDirectLinkJsonError(
    HttpResponse response,
    int statusCode,
    String message,
  ) {
    response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode(
          <String, Object?>{
            'error': message,
            'statusCode': statusCode,
          },
        ),
      );
  }
}
