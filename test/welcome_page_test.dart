import 'package:an_xin_ban/app_theme.dart';
import 'package:an_xin_ban/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('family entry shows login before settings and PIN', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildTheme(), home: const WelcomePage()),
    );
    expect(find.text('家人'), findsOneWidget);
    expect(find.text('長輩'), findsOneWidget);
    expect(find.text('使用 Google 登入'), findsNothing);
    await tester.tap(find.text('家人'));
    await tester.pumpAndSettle();
    expect(find.text('建立家人 PIN'), findsNothing);
    expect(find.text('家人登入'), findsOneWidget);
    expect(find.text('使用 Google 登入'), findsOneWidget);
    expect(find.text('解鎖設定'), findsNothing);
    expect(find.text('新增聯絡人與綽號'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('長輩'));
    await tester.pumpAndSettle();
    expect(find.text('與家人配對'), findsOneWidget);
    expect(find.text('不配對，直接使用'), findsOneWidget);
    expect(find.text('使用 Google 登入'), findsNothing);
    expect(find.text('我是家人，管理設定'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
