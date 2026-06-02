import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seewopan/features/webdav/seewo_webdav_server.dart';
import 'package:seewopan/features/webdav/webdav_settings.dart';
import 'package:seewopan/shared/pinco_api_client.dart';

void main() {
  test('download link api returns stable Pinco download url for a WebDAV path',
      () async {
    final apiClient = PincoApiClient(
      httpClient: MockClient((request) async {
        final action = request.url.queryParameters['actionName'];
        if (action == 'GetV1DriveMaterials') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          if (payload['folderId'] == '0') {
            return _jsonResponse({
              'statusCode': 0,
              'data': {
                'list': [
                  {
                    'id': 'folder-1',
                    'folderId': '0',
                    'name': '课程',
                    'type': 'folder',
                  },
                ],
              },
            });
          }
          return _jsonResponse({
            'statusCode': 0,
            'data': {
              'list': [
                {
                  'id': 'file-1',
                  'folderId': 'folder-1',
                  'name': '试卷.pdf',
                  'size': 42,
                  'mimeType': 'application/pdf',
                  'type': 'resource',
                },
              ],
            },
          });
        }

        return http.Response('not-found', 404);
      }),
    );
    final server = SeewoWebDavServer(apiClient: apiClient);
    await server.start(
      settings: const WebDavSettings(port: 0, username: '', password: ''),
      cookie: 'token=abc',
    );

    try {
      final response = await http.get(
        server.uri!.replace(
          path: '/__seewopan/api/download-link',
          queryParameters: {'path': '/课程/试卷.pdf'},
        ),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(body['materialId'], 'file-1');
      expect(body['name'], '试卷.pdf');
      expect(
        body['url'],
        'https://pinco.seewo.com/server-main/api/v1/drive/materials/download'
        '?resId=file-1',
      );
      expect(body['source'], 'pincoDownloadUrl');
    } finally {
      await server.stop();
    }
  });
}

http.Response _jsonResponse(Map<String, dynamic> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}
