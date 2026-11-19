import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/confirmation_dialog.dart';

void main() {
  testWidgets(
    'confirmation buttons stay side by side and return the chosen result',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (_) => const ConfirmationDialog(
                      title: '重新載入設定？',
                      description: '未發佈的草稿將被雲端設定取代。',
                    ),
                  );
                },
                child: const Text('開啟'),
              ),
            ),
          ),
        ),
      );
      for (final label in ['取消', '確認']) {
        await tester.tap(find.text('開啟'));
        await tester.pumpAndSettle();
        expect(
          tester.getCenter(find.text('取消')).dy,
          tester.getCenter(find.text('確認')).dy,
        );
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(result, label == '確認');
      }
    },
  );
}
