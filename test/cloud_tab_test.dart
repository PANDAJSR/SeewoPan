import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seewopan/features/cloud/cloud_tab.dart';
import 'package:seewopan/features/transfer/upload_task_manager.dart';
import 'package:seewopan/shared/pinco_api_client.dart';

void main() {
  testWidgets(
    'shows cloud courseware virtual folder and loads it with en tag',
    (WidgetTester tester) async {
      final materialRequests = <Map<String, dynamic>>[];

      final mockClient = MockClient((request) async {
        final action = request.url.queryParameters['actionName'];
        if (action == 'GetV1DriveMaterials') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          materialRequests.add(payload);
          final tagName = payload['tagName']?.toString() ?? '';

          final list = tagName == 'en'
              ? [
                  {
                    'id': 'en-1',
                    'folderId': '0',
                    'name': '云课件示例.enbx',
                    'type': 'resource',
                    'size': 1024,
                  },
                ]
              : [
                  {
                    'id': 'm1',
                    'folderId': '0',
                    'name': '语文课件.pdf',
                    'type': 'resource',
                    'size': 1234,
                  },
                ];

          return http.Response(
            jsonEncode({
              'statusCode': 0,
              'data': {'list': list},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('not-found', 404);
      });

      final apiClient = PincoApiClient(httpClient: mockClient);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudTab(
              cookie: 'token=abc',
              isLoadingCookie: false,
              apiClient: apiClient,
              onUploadFiles: (List<UploadSourceFile> files) async {},
              onDownloadMaterials: (materials) async => materials.length,
              onOpenTransferTab: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('云课件'), findsOneWidget);
      expect(find.text('语文课件.pdf'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('云课件')).dy <
            tester.getTopLeft(find.text('语文课件.pdf')).dy,
        isTrue,
      );

      await tester.tap(find.text('云课件'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('重命名'), findsNothing);
      expect(find.text('分享...'), findsNothing);
      expect(find.text('删除文件夹'), findsNothing);

      await tester.tap(find.text('云课件'));
      await tester.pumpAndSettle();

      expect(find.text('云课件示例.enbx'), findsOneWidget);
      expect(find.text('根目录 / 云课件'), findsOneWidget);
      expect(materialRequests, hasLength(2));
      expect(materialRequests.first['tagName'], 'resource,folder');
      expect(materialRequests.last['tagName'], 'en');
      expect(materialRequests.last['folderId'], '0');
    },
  );

  testWidgets('loads a real folder by its own id instead of its parent id', (
    WidgetTester tester,
  ) async {
    final requestedFolderIds = <String>[];

    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action != 'GetV1DriveMaterials') {
        return http.Response('not-found', 404);
      }

      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      final folderId = payload['folderId']?.toString() ?? '0';
      requestedFolderIds.add(folderId);
      final list = folderId == 'folder-1'
          ? [
              {
                'id': 'child-file',
                'folderId': 'folder-1',
                'name': '二级目录文件.pdf',
                'type': 'resource',
                'size': 2048,
              },
            ]
          : [
              {
                'id': 'folder-1',
                'folderId': '0',
                'name': '课件目录',
                'type': 'folder',
              },
            ];

      return http.Response(
        jsonEncode({
          'statusCode': 0,
          'data': {'list': list},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudTab(
            cookie: 'token=abc',
            isLoadingCookie: false,
            apiClient: PincoApiClient(httpClient: mockClient),
            onUploadFiles: (List<UploadSourceFile> files) async {},
            onDownloadMaterials: (materials) async => materials.length,
            onOpenTransferTab: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('课件目录'));
    await tester.pumpAndSettle();

    expect(requestedFolderIds, <String>['0', 'folder-1']);
    expect(find.text('根目录 / 课件目录'), findsOneWidget);
    expect(find.text('二级目录文件.pdf'), findsOneWidget);
    expect(find.text('云课件'), findsNothing);
  });

  testWidgets('supports selecting multiple items and deleting them in batch', (
    WidgetTester tester,
  ) async {
    final deleteRequests = <List<String>>[];

    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1DriveMaterials') {
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'list': [
                {
                  'id': 'm1',
                  'folderId': '0',
                  'name': '语文课件.pdf',
                  'type': 'resource',
                  'size': 1234,
                },
                {
                  'id': 'm2',
                  'folderId': '0',
                  'name': '数学课件.pdf',
                  'type': 'resource',
                  'size': 4567,
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (action == 'DeleteV1DriveMaterials') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final ids = (payload['resIds'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(growable: false);
        deleteRequests.add(ids);

        return http.Response(
          jsonEncode({'statusCode': 0, 'data': true, 'message': 'ok'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not-found', 404);
    });

    final apiClient = PincoApiClient(httpClient: mockClient);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudTab(
            cookie: 'token=abc',
            isLoadingCookie: false,
            apiClient: apiClient,
            onUploadFiles: (List<UploadSourceFile> files) async {},
            onDownloadMaterials: (materials) async => materials.length,
            onOpenTransferTab: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('语文课件.pdf'), findsOneWidget);
    expect(find.text('数学课件.pdf'), findsOneWidget);

    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('语文课件.pdf'));
    await tester.pump();
    await tester.tap(find.text('数学课件.pdf'));
    await tester.pumpAndSettle();

    expect(find.text('已选择 2 项'), findsOneWidget);

    await tester.tap(find.byTooltip('删除所选'));
    await tester.pumpAndSettle();
    expect(find.text('确认删除已选择的 2 项吗？此操作不可撤销。'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(deleteRequests, hasLength(1));
    expect(deleteRequests.first, hasLength(2));
    expect(deleteRequests.first, containsAll(<String>['m1', 'm2']));
  });

  testWidgets('supports selecting multiple items and moving them in batch', (
    WidgetTester tester,
  ) async {
    final moveRequests = <Map<String, dynamic>>[];

    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1DriveMaterials') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final folderId = payload['folderId']?.toString() ?? '0';
        final tagName = payload['tagName']?.toString() ?? '';

        if (folderId == '0' && tagName == 'resource,folder') {
          return http.Response(
            jsonEncode({
              'statusCode': 0,
              'data': {
                'list': [
                  {
                    'id': 'm1',
                    'folderId': '0',
                    'name': '语文课件.pdf',
                    'type': 'resource',
                    'size': 1234,
                  },
                  {
                    'id': 'm2',
                    'folderId': '0',
                    'name': '数学课件.pdf',
                    'type': 'resource',
                    'size': 4567,
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (folderId == '0' && tagName == 'folder') {
          return http.Response(
            jsonEncode({
              'statusCode': 0,
              'data': {
                'list': [
                  {
                    'id': 'f1',
                    'folderId': 'f1',
                    'name': '目标文件夹',
                    'type': 'folder',
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (folderId == 'f1' && tagName == 'folder') {
          return http.Response(
            jsonEncode({
              'statusCode': 0,
              'data': {'list': []},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
      }

      if (action == 'PutV1DriveMaterialsLocations') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        moveRequests.add(payload);
        return http.Response(
          jsonEncode({'statusCode': 0, 'data': true, 'message': 'ok'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not-found', 404);
    });

    final apiClient = PincoApiClient(httpClient: mockClient);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudTab(
            cookie: 'token=abc',
            isLoadingCookie: false,
            apiClient: apiClient,
            onUploadFiles: (List<UploadSourceFile> files) async {},
            onDownloadMaterials: (materials) async => materials.length,
            onOpenTransferTab: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('语文课件.pdf'), findsOneWidget);
    expect(find.text('数学课件.pdf'), findsOneWidget);

    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('语文课件.pdf'));
    await tester.pump();
    await tester.tap(find.text('数学课件.pdf'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('移动所选'));
    await tester.pumpAndSettle();
    expect(find.text('选择目标目录'), findsOneWidget);

    await tester.tap(find.text('目标文件夹'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('移动到此处'));
    await tester.pumpAndSettle();

    expect(moveRequests, hasLength(1));
    expect(moveRequests.first['resIdList'], hasLength(2));
    expect(
      moveRequests.first['resIdList'],
      containsAll(<String>['m1', 'm2']),
    );
    expect(moveRequests.first['targetFolderId'], 'f1');
  });

  testWidgets('supports creating a folder from selected items', (
    WidgetTester tester,
  ) async {
    final createFolderRequests = <Map<String, dynamic>>[];
    final moveRequests = <Map<String, dynamic>>[];

    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1DriveMaterials') {
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'list': [
                {
                  'id': 'm1',
                  'folderId': '0',
                  'name': '语文课件.pdf',
                  'type': 'resource',
                  'size': 1234,
                },
                {
                  'id': 'm2',
                  'folderId': '0',
                  'name': '数学课件.pdf',
                  'type': 'resource',
                  'size': 4567,
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (action == 'PostV1DriveMaterialsFolders') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        createFolderRequests.add(payload);
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'id': 'f-new',
              'folderId': 'f-new',
              'name': payload['name'] ?? '',
            },
            'message': 'ok',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (action == 'PutV1DriveMaterialsLocations') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        moveRequests.add(payload);
        return http.Response(
          jsonEncode({'statusCode': 0, 'data': true, 'message': 'ok'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not-found', 404);
    });

    final apiClient = PincoApiClient(httpClient: mockClient);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudTab(
            cookie: 'token=abc',
            isLoadingCookie: false,
            apiClient: apiClient,
            onUploadFiles: (List<UploadSourceFile> files) async {},
            onDownloadMaterials: (materials) async => materials.length,
            onOpenTransferTab: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('语文课件.pdf'), findsOneWidget);
    expect(find.text('数学课件.pdf'), findsOneWidget);

    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('语文课件.pdf'));
    await tester.pump();
    await tester.tap(find.text('数学课件.pdf'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('用所选项目新建文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('新建文件夹'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '课堂资料');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(createFolderRequests, hasLength(1));
    expect(createFolderRequests.first['name'], '课堂资料');
    expect(createFolderRequests.first['parentFolderId'], '0');

    expect(moveRequests, hasLength(1));
    expect(moveRequests.first['resIdList'], hasLength(2));
    expect(
      moveRequests.first['resIdList'],
      containsAll(<String>['m1', 'm2']),
    );
    expect(moveRequests.first['targetFolderId'], 'f-new');
  });

  testWidgets('supports searching materials by keyword', (
    WidgetTester tester,
  ) async {
    final requestedKeywords = <String>[];

    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1DriveMaterials') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final keyword = payload['keyword']?.toString() ?? '';
        requestedKeywords.add(keyword);
        final list = keyword == '数学'
            ? [
                {
                  'id': 'm2',
                  'folderId': '0',
                  'name': '数学课件.pdf',
                  'type': 'resource',
                  'size': 4567,
                },
              ]
            : [
                {
                  'id': 'm1',
                  'folderId': '0',
                  'name': '语文课件.pdf',
                  'type': 'resource',
                  'size': 1234,
                },
                {
                  'id': 'm2',
                  'folderId': '0',
                  'name': '数学课件.pdf',
                  'type': 'resource',
                  'size': 4567,
                },
              ];
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'list': list,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not-found', 404);
    });

    final apiClient = PincoApiClient(httpClient: mockClient);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudTab(
            cookie: 'token=abc',
            isLoadingCookie: false,
            apiClient: apiClient,
            onUploadFiles: (List<UploadSourceFile> files) async {},
            onDownloadMaterials: (materials) async => materials.length,
            onOpenTransferTab: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('语文课件.pdf'), findsOneWidget);
    expect(find.text('数学课件.pdf'), findsOneWidget);

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '数学');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('数学课件.pdf'), findsOneWidget);
    expect(find.text('语文课件.pdf'), findsNothing);
    expect(requestedKeywords, containsAllInOrder(<String>['', '数学']));

    await tester.tap(find.byTooltip('收起搜索'));
    await tester.pumpAndSettle();

    expect(find.text('语文课件.pdf'), findsOneWidget);
    expect(find.text('数学课件.pdf'), findsOneWidget);
    expect(requestedKeywords, containsAllInOrder(<String>['', '数学', '']));
  });

  testWidgets('supports sorting materials by name, size and update time', (
    WidgetTester tester,
  ) async {
    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1DriveMaterials') {
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'list': [
                {
                  'id': 'm-b',
                  'folderId': '0',
                  'name': 'B.txt',
                  'type': 'resource',
                  'size': 200,
                  'updatedAt': '2024-01-03T10:00:00Z',
                },
                {
                  'id': 'm-c',
                  'folderId': '0',
                  'name': 'C.txt',
                  'type': 'resource',
                  'size': 300,
                  'updatedAt': '2024-01-02T10:00:00Z',
                },
                {
                  'id': 'm-a',
                  'folderId': '0',
                  'name': 'A.txt',
                  'type': 'resource',
                  'size': 100,
                  'updatedAt': '2024-01-01T10:00:00Z',
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

    final apiClient = PincoApiClient(httpClient: mockClient);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudTab(
            cookie: 'token=abc',
            isLoadingCookie: false,
            apiClient: apiClient,
            onUploadFiles: (List<UploadSourceFile> files) async {},
            onDownloadMaterials: (materials) async => materials.length,
            onOpenTransferTab: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    double yOf(String fileName) {
      return tester.getTopLeft(find.text(fileName)).dy;
    }

    expect(yOf('A.txt') < yOf('B.txt'), isTrue);
    expect(yOf('B.txt') < yOf('C.txt'), isTrue);

    await tester.tap(find.byTooltip('排序方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按大小（降序）'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(yOf('C.txt') < yOf('B.txt'), isTrue);
    expect(yOf('B.txt') < yOf('A.txt'), isTrue);

    await tester.tap(find.byTooltip('排序方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按修改日期（最新）'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(yOf('B.txt') < yOf('C.txt'), isTrue);
    expect(yOf('C.txt') < yOf('A.txt'), isTrue);
  });

  testWidgets('previews image materials from material detail url', (
    WidgetTester tester,
  ) async {
    final requestedMaterialIds = <String>[];
    final clipboardWrites = <String>[];
    const pngDataUrl =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final data = call.arguments as Map<dynamic, dynamic>;
        clipboardWrites.add(data['text'].toString());
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1DriveMaterials') {
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'list': [
                {
                  'id': 'image-1',
                  'folderId': '0',
                  'name': '板书截图.PNG',
                  'mimeType': 'image/png',
                  'type': 'resource',
                  'size': 1234,
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (action == 'GetV1DriveMaterialsByMaterialId') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        requestedMaterialIds.add(payload['materialId'].toString());
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'storeType': 2,
              'showUrl': '',
              'downloadUrl': pngDataUrl,
            },
            'message': 'ok',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not-found', 404);
    });

    final apiClient = PincoApiClient(httpClient: mockClient);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudTab(
            cookie: 'token=abc',
            isLoadingCookie: false,
            apiClient: apiClient,
            onUploadFiles: (List<UploadSourceFile> files) async {},
            onDownloadMaterials: (materials) async => materials.length,
            onOpenTransferTab: () {},
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('板书截图.PNG'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(requestedMaterialIds, <String>['image-1']);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('板书截图.PNG'), findsAtLeastNWidgets(2));

    await tester.tap(find.text('复制地址'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(clipboardWrites, <String>[pngDataUrl]);
    expect(find.text('已复制文件地址'), findsOneWidget);
  });
}
