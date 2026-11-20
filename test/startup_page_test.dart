import 'package:an_xin_ban/main.dart';
import 'package:an_xin_ban/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'the splash paints its mark and fades its mark out before the next page fades in',
    (tester) async {
      final splash = find.byKey(const ValueKey('splash'));
      await tester.pumpWidget(const AnXinBanApp());
      expect(splash, findsOneWidget);
      // No image to load, so the mark is there on the very first frame.
      expect(find.byType(Image), findsNothing);
      expect(find.byType(WelcomePage), findsNothing);

      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pump(const Duration(milliseconds: 150));
      final mark = find.byType(Row).first;
      final fade = find
          .ancestor(of: mark, matching: find.byType(Opacity))
          .first;
      expect(tester.widget<Opacity>(fade).opacity, inExclusiveRange(0, 1));
      expect(find.byType(WelcomePage), findsNothing);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final reveal = find
          .ancestor(
            of: find.byType(WelcomePage),
            matching: find.byType(Opacity),
          )
          .first;
      expect(tester.widget<Opacity>(reveal).opacity, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(reveal).opacity, 1);
      expect(splash, findsNothing);
      expect(find.byType(WelcomePage), findsOneWidget);
    },
  );
}
