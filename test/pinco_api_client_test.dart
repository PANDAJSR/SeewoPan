import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewopan/shared/pinco_api_client.dart';

void main() {
  test('buildMaterialDownloadUrl should encode resId', () {
    final client = PincoApiClient();
    const materialId = 'id with space/&?';

    final url = client.buildMaterialDownloadUrl(materialId);

    expect(
      url,
      'https://pinco.seewo.com/server-main/api/v1/drive/materials/download'
      '?resId=id+with+space%2F%26%3F',
    );
  });

  test('getMaterialPreview should call material detail action', () async {
    final mockClient = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.queryParameters['actionName'],
        'GetV1DriveMaterialsByMaterialId',
      );
      expect(request.headers['cookie'], 'token=abc');

      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['materialId'], 'm1');

      return http.Response(
        jsonEncode({
          'statusCode': 0,
          'data': {
            'storeType': 2,
            'showUrl': '',
            'downloadUrl': 'https://example.com/image.png',
          },
          'message': 'ok',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = PincoApiClient(httpClient: mockClient);

    final preview = await client.getMaterialPreview(
      cookie: ' token=abc ',
      materialId: ' m1 ',
    );

    expect(preview.previewUrl, 'https://example.com/image.png');
    expect(preview.downloadUrl, 'https://example.com/image.png');
    expect(preview.showUrl, isNull);
    expect(preview.storeType, 2);
  });

  test('getMaterials should send keyword and cache by keyword', () async {
    var listCallCount = 0;
    final sentKeywords = <String>[];

    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1DriveMaterials') {
        listCallCount += 1;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        sentKeywords.add(payload['keyword']?.toString() ?? '');
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'list': [
                {
                  'id': 'm1',
                  'folderId': '0',
                  'name': 'keyword-test.txt',
                  'type': 'resource',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not-found', 404);
    });

    final client = PincoApiClient(httpClient: mockClient);

    await client.getMaterials(
      cookie: 'token=abc',
      folderId: '0',
      keyword: '鸿合',
    );
    await client.getMaterials(
      cookie: 'token=abc',
      folderId: '0',
      keyword: '鸿合',
    );
    await client.getMaterials(
      cookie: 'token=abc',
      folderId: '0',
      keyword: '试卷',
    );

    expect(listCallCount, 2);
    expect(sentKeywords, <String>['鸿合', '试卷']);
  });

  test('getDriveMaterialsCapacity should parse response and cache by type',
      () async {
    var capacityCallCount = 0;
    final sentTypes = <int>[];

    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1DriveMaterialsCapacity') {
        capacityCallCount += 1;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        sentTypes.add(payload['type'] as int);

        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'capacity': 80302047232,
              'used': 3534613292,
              'usedDetail': [
                {
                  'appCode': 'EN',
                  'appName': '白板',
                  'totalUsed': 3066919338,
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not-found', 404);
    });

    final client = PincoApiClient(httpClient: mockClient);

    final first = await client.getDriveMaterialsCapacity(
      cookie: 'token=abc',
      type: 1,
    );
    final second = await client.getDriveMaterialsCapacity(
      cookie: 'token=abc',
      type: 1,
    );
    await client.getDriveMaterialsCapacity(
      cookie: 'token=abc',
      type: 2,
    );

    expect(first.capacity, 80302047232);
    expect(first.used, 3534613292);
    expect(first.usedDetail, hasLength(1));
    expect(first.usedDetail.first.displayName, '白板');
    expect(identical(first, second), isTrue);
    expect(capacityCallCount, 2);
    expect(sentTypes, <int>[1, 2]);
  });

  test('renameMaterial should call rename action and clear cache', () async {
    var listCallCount = 0;
    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1DriveMaterials') {
        listCallCount += 1;
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'list': [
                {
                  'id': 'm1',
                  'folderId': '0',
                  'name': 'old-name.txt',
                  'type': 'resource',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (action == 'PutV1DriveMaterialsByMaterialIdName') {
        expect(request.method, 'POST');
        expect(request.headers['cookie'], 'token=abc');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['materialId'], 'm1');
        expect(payload['name'], 'new-name.txt');

        return http.Response(
          jsonEncode({'statusCode': 0, 'data': true, 'message': 'ok'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not-found', 404);
    });

    final client = PincoApiClient(httpClient: mockClient);
    await client.getMaterials(cookie: 'token=abc', folderId: '0');
    expect(listCallCount, 1);

    await client.renameMaterial(
      cookie: 'token=abc',
      materialId: 'm1',
      name: 'new-name.txt',
    );

    await client.getMaterials(cookie: 'token=abc', folderId: '0');
    expect(listCallCount, 2);
  });

  test('renameMaterial should throw when backend returns false', () async {
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'statusCode': 0, 'data': false, 'message': 'ok'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = PincoApiClient(httpClient: mockClient);

    await expectLater(
      client.renameMaterial(
        cookie: 'token=abc',
        materialId: 'm1',
        name: 'new-name.txt',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('deleteMaterials should call delete action and clear cache', () async {
    var listCallCount = 0;
    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1DriveMaterials') {
        listCallCount += 1;
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'list': [
                {
                  'id': 'm1',
                  'folderId': '0',
                  'name': 'to-delete.txt',
                  'type': 'resource',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (action == 'DeleteV1DriveMaterials') {
        expect(request.method, 'POST');
        expect(request.headers['cookie'], 'token=abc');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['resIds'], ['m1']);

        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': true,
            'message': 'ok',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not-found', 404);
    });

    final client = PincoApiClient(httpClient: mockClient);
    await client.getMaterials(cookie: 'token=abc', folderId: '0');
    expect(listCallCount, 1);

    await client.deleteMaterials(
      cookie: 'token=abc',
      materialIds: const ['m1'],
    );

    await client.getMaterials(cookie: 'token=abc', folderId: '0');
    expect(listCallCount, 2);
  });

  test('moveMaterials should call move action and clear cache', () async {
    var listCallCount = 0;
    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1DriveMaterials') {
        listCallCount += 1;
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'list': [
                {
                  'id': 'm1',
                  'folderId': '0',
                  'name': 'to-move.txt',
                  'type': 'resource',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (action == 'PutV1DriveMaterialsLocations') {
        expect(request.method, 'POST');
        expect(request.headers['cookie'], 'token=abc');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['resIdList'], ['m1']);
        expect(payload['targetFolderId'], 'folder-2');

        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': true,
            'message': 'ok',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not-found', 404);
    });

    final client = PincoApiClient(httpClient: mockClient);
    await client.getMaterials(cookie: 'token=abc', folderId: '0');
    expect(listCallCount, 1);

    await client.moveMaterials(
      cookie: 'token=abc',
      materialIds: const ['m1'],
      targetFolderId: 'folder-2',
    );

    await client.getMaterials(cookie: 'token=abc', folderId: '0');
    expect(listCallCount, 2);
  });

  test('createFolder should call create action and clear cache', () async {
    var listCallCount = 0;
    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1DriveMaterials') {
        listCallCount += 1;
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'list': [
                {
                  'id': 'm1',
                  'folderId': '0',
                  'name': 'existing-file.txt',
                  'type': 'resource',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (action == 'PostV1DriveMaterialsFolders') {
        expect(request.method, 'POST');
        expect(request.headers['cookie'], 'token=abc');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['name'], 'lesson-1');
        expect(payload['parentFolderId'], '123');

        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {'id': 'folder-001'},
            'message': 'ok',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not-found', 404);
    });

    final client = PincoApiClient(httpClient: mockClient);
    await client.getMaterials(cookie: 'token=abc', folderId: '123');
    expect(listCallCount, 1);

    final folderId = await client.createFolder(
      cookie: 'token=abc',
      name: 'lesson-1',
      parentFolderId: '123',
    );
    expect(folderId, 'folder-001');

    await client.getMaterials(cookie: 'token=abc', folderId: '123');
    expect(listCallCount, 2);
  });

  test('createDriveLinkShare should call share action and parse result',
      () async {
    final requests = <Map<String, dynamic>>[];
    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'PostV1DriveLinkShare') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(payload);
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'shareId': '372604f8a13e42ae8e3640f372abd64c',
              'password': 'uj57',
            },
            'message': 'ok',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not-found', 404);
    });

    final client = PincoApiClient(httpClient: mockClient);
    final result = await client.createDriveLinkShare(
      cookie: 'token=abc',
      resId: 'm1',
      minutes: 30 * 24 * 60,
      shareType: 1,
    );

    expect(requests, hasLength(1));
    expect(requests.first['resId'], 'm1');
    expect(requests.first['minutes'], 30 * 24 * 60);
    expect(requests.first['shareType'], 1);
    expect(result.shareId, '372604f8a13e42ae8e3640f372abd64c');
    expect(result.password, 'uj57');
    expect(
      result.shareUrl,
      'https://pinco.seewo.com/s/372604f8a13e42ae8e3640f372abd64c',
    );
  });
}
