import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:seewopan/app/home_shell_page.dart';
import 'package:seewopan/features/cloud/cloud_tab.dart';

void main() {
  testWidgets('keeps cloud tab state when switching tabs', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShellPage(
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final beforeSwitch = tester.state(find.byType(CloudTab));

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('云盘'));
    await tester.pumpAndSettle();

    final afterSwitch = tester.state(find.byType(CloudTab));
    expect(identical(beforeSwitch, afterSwitch), isTrue);
  });
}
