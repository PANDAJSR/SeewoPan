import 'package:flutter_test/flutter_test.dart';

import 'package:seewopan/app/seewo_pan_app.dart';

void main() {
  testWidgets('shows navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const SeewoPanApp());

    expect(find.text('云盘'), findsOneWidget);
    expect(find.text('传输'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
