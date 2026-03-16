import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seewopan/features/profile/profile_tab.dart';
import 'package:seewopan/shared/pinco_api_client.dart';

void main() {
  testWidgets('shows storage usage in my tab with one stacked progress bar', (
    WidgetTester tester,
  ) async {
    final mockClient = MockClient((request) async {
      final action = request.url.queryParameters['actionName'];
      if (action == 'GetV1UsersInfo') {
        return http.Response(
          jsonEncode({
            'statusCode': 0,
            'data': {
              'nickName': '测试老师',
              'username': 'teacher001',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (action == 'GetV1DriveMaterialsCapacity') {
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
                {
                  'appCode': 'pinco',
                  'appName': 'pinco',
                  'totalUsed': 467693954,
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
          body: ProfileTab(
            initialCookie: 'token=abc',
            isLoadingCookie: false,
            isSavingCookie: false,
            onSaveCookie: (_) async {},
            apiClient: apiClient,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('空间占用'), findsOneWidget);
    expect(find.textContaining('总已用'), findsOneWidget);
    expect(find.textContaining('白板'), findsOneWidget);
    expect(find.textContaining('pinco'), findsOneWidget);
    expect(find.byKey(const Key('capacity_stacked_bar')), findsOneWidget);
  });
}
