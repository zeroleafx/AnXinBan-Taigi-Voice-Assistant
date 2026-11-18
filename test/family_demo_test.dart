import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:an_xin_ban/family_demo_store.dart';
import 'package:an_xin_ban/family_demo.dart';
import 'package:an_xin_ban/assistant_controller.dart';
import 'package:an_xin_ban/contact_matcher.dart';

import 'support/fake_phone.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('invitation dialog copies its code and closes', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const InvitationCodeDialog(code: 'test-code'),
              ),
              child: const Text('開啟'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('複製'));
    await tester.pumpAndSettle();
    expect(copied, 'test-code');
    expect(find.text('已複製'), findsOneWidget);
    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();
    expect(find.byType(InvitationCodeDialog), findsNothing);
  });
  test('draft settings only reach the elder after simulated sync', () async {
    final store = FamilyDemoStore();
    await store.write('pending', [
      {'kind': 'place', 'label': '家', 'aliases': '厝', 'value': '台北市中山路一號'},
    ]);
    expect(await store.read('applied'), isEmpty);
    await store.apply();
    expect(
      await FamilyDemoStore().read('applied'),
      await store.read('pending'),
    );
    await store.write('pending', []);
    expect(await store.read('applied'), isNotEmpty);
  });
  test(
    'PIN persists without plaintext and locks after five failures',
    () async {
      final store = FamilyDemoStore();
      await store.setPin('123456');
      expect(await store.unlock('123456'), isTrue);
      expect(
        await store.preferences.getString('family_demo_pin'),
        isNot(contains('123456')),
      );
      for (var i = 0; i < 5; i++) {
        expect(await store.unlock('000000'), isFalse);
      }
      expect(await FamilyDemoStore().unlock('123456'), isFalse);
    },
  );
  test('family aliases resolve before confirmation without dialing', () async {
    final phone = FakePhone();
    final assistant = AssistantController(phone);
    addTearDown(assistant.dispose);
    assistant.familyContacts = [
      const ContactEntry(
        name: '王美玲',
        numbers: ['0912345678'],
        aliases: ['女兒', '阿美'],
      ),
    ];
    await assistant.handle('打給女兒');
    expect(phone.dialed, isEmpty);
    expect(assistant.outcome!.title, contains('王美玲'));
    await assistant.press(assistant.outcome!.buttons.first);
    expect(phone.dialed, ['0912345678']);
  });
  testWidgets('family entry requires PIN and labels simulation', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FamilyDemoPage()));
    await tester.pumpAndSettle();
    expect(find.text('本機模擬模式'), findsOneWidget);
    await tester.tap(find.text('我是家人，管理設定'));
    await tester.pumpAndSettle();
    expect(find.text('建立家人 PIN'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '123456');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    expect(find.text('新增聯絡人與綽號'), findsOneWidget);
    await tester.tap(find.byTooltip('鎖定家人設定'));
    await tester.pumpAndSettle();
    expect(find.text('新增聯絡人與綽號'), findsNothing);
  });
  testWidgets(
    'pairing dialog survives dismissal animation with focused input',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => const PairCodeDialog(),
                ),
                child: const Text('配對'),
              ),
            ),
          ),
        ),
      );
      for (final button in ['取消', '確認連結並接收家人設定']) {
        await tester.tap(find.text('配對'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'test-code');
        await tester.tap(find.text(button));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
  for (final background in [false, true]) {
    testWidgets(
      'contact survives ${background ? "background reauthentication" : "inactive overlay"}',
      (tester) async {
        final store = FamilyDemoStore();
        await store.setPin('123456');
        await tester.pumpWidget(const MaterialApp(home: FamilyDemoPage()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('我是家人，管理設定'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '123456');
        await tester.tap(find.text('確認'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('新增聯絡人與綽號'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), '王美玲');
        await tester.enterText(find.byType(TextField).at(1), '女兒,阿美');
        await tester.enterText(find.byType(TextField).at(2), '0912345678');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('儲存'));
        await tester.pumpAndSettle();
        if (background) {
          expect(await store.read('pending'), isEmpty);
          expect(find.text('輸入家人 PIN'), findsOneWidget);
          await tester.enterText(find.byType(TextField), '123456');
          await tester.tap(find.text('確認'));
          await tester.pumpAndSettle();
        }
        expect((await store.read('pending')).single['label'], '王美玲');
        expect(await store.read('applied'), isEmpty);
        expect(find.text('家人設定'), findsOneWidget);
      },
    );
  }
}
