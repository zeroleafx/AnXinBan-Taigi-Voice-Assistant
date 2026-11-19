import 'package:an_xin_ban/main.dart';
import 'package:an_xin_ban/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the splash paints its mark and fades into the next page', (
    tester,
  ) async {
    final splash = find.byKey(const ValueKey('splash'));
    await tester.pumpWidget(const AnXinBanApp());
    expect(splash, findsOneWidget);
    // No image to load, so the mark is there on the very first frame.
    expect(find.byType(Image), findsNothing);
    expect(find.byType(WelcomePage), findsNothing);

    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 150));
    expect(splash, findsOneWidget, reason: 'still under the fade');
    expect(find.byType(WelcomePage), findsOneWidget);

    await tester.pumpAndSettle();
    expect(splash, findsNothing);
    expect(find.byType(WelcomePage), findsOneWidget);
  });
}
