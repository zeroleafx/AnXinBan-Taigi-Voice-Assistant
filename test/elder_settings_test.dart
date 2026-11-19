import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:an_xin_ban/elder_draft_store.dart';
import 'package:an_xin_ban/family_cloud.dart';
import 'package:an_xin_ban/family_dashboard.dart';
import 'package:an_xin_ban/app_theme.dart';
import 'package:an_xin_ban/family_demo_store.dart';

class FakeFamilyCloud extends FamilyCloud {
  final rows = [
    {
      'id': 'a',
      'owner_id': 'owner',
      'elder_id': 'one',
      'display_name': '阿公',
      'applied_revision': 1,
    },
    {
      'id': 'b',
      'owner_id': 'owner',
      'elder_id': 'two',
      'display_name': '阿嬤',
      'applied_revision': 0,
    },
  ];
  final data = <String, Map<String, dynamic>>{
    'a': {
      'link_id': 'a',
      'revision': 1,
      'entries': [
        {'kind': 'place', 'label': '阿公的家', 'aliases': '厝', 'value': '台北'},
      ],
    },
    'b': {
      'link_id': 'b',
      'revision': 1,
      'entries': [
        {'kind': 'place', 'label': '阿嬤的家', 'aliases': '厝', 'value': '台南'},
      ],
    },
  };
  String? publishedTo;
  @override
  String? get user => 'owner';
  @override
  bool get hasFamilyAccount => true;
  @override
  Future<List<Map<String, dynamic>>> links() async => rows;
  @override
  Future<List<Map<String, dynamic>>> elderSnapshots() async =>
      data.values.toList();
  @override
  Future<Map<String, dynamic>?> elderSnapshot(String linkId) async =>
      data[linkId];
  @override
  Future<int> publishElder(
    String linkId,
    List<Map<String, String>> entries,
    int revision,
  ) async {
    publishedTo = linkId;
    data[linkId] = {
      'link_id': linkId,
      'revision': revision + 1,
      'entries': entries,
    };
    return revision + 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'drafts are isolated by family and pairing, with selective cleanup',
    () async {
      final store = ElderDraftStore();
      await store.save('owner', 'a', [
        {'label': '阿公'},
      ], 1);
      await store.save('owner', 'b', [
        {'label': '阿嬤'},
      ], 2);
      await store.save('other', 'a', [
        {'label': '別人'},
      ], 1);
      expect((await store.read('owner', 'a'))!['entries'], [
        {'label': '阿公'},
      ]);
      await store.prune('owner', {'b'});
      expect(await store.read('owner', 'a'), isNull);
      expect(await store.read('owner', 'b'), isNotNull);
      expect(await store.read('other', 'a'), isNotNull);
    },
  );
  testWidgets('dashboard opens only the selected elder settings', (
    tester,
  ) async {
    final cloud = FakeFamilyCloud();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: FamilyDashboard(cloud: cloud),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('阿公'), findsOneWidget);
    expect(find.text('阿嬤'), findsOneWidget);
    expect(find.text('設定已同步'), findsOneWidget);
    expect(find.text('等待同步'), findsOneWidget);
    await tester.tap(find.text('阿嬤'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('常用地址'));
    await tester.pumpAndSettle();
    expect(find.text('阿嬤的家'), findsOneWidget);
    expect(find.text('阿公的家'), findsNothing);
    for (final label in ['重載', '改名', '發布', '解除']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.byTooltip('返回分類'));
    await tester.pumpAndSettle();
    expect(find.text('聯絡人與綽號'), findsOneWidget);
    expect(find.text('常用地址'), findsOneWidget);
    expect(find.text('阿嬤的家'), findsOneWidget);
    expect(find.text('阿公的家'), findsNothing);
    expect(find.text('模擬同步到長輩端'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'publishing a saved draft targets only that elder and requires PIN',
    (tester) async {
      final cloud = FakeFamilyCloud();
      await FamilyDemoStore().setPin('123456');
      await ElderDraftStore().save('owner', 'b', [
        {'kind': 'place', 'label': '新家', 'aliases': '厝', 'value': '高雄'},
      ], 1);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: ElderSettingsPage(
            link: cloud.rows[1],
            name: '阿嬤',
            cloud: cloud,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('發布'));
      await tester.pumpAndSettle();
      expect(cloud.publishedTo, isNull);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('確認'));
      await tester.pumpAndSettle();
      expect(cloud.publishedTo, 'b');
      expect((cloud.data['a']!['entries'] as List).single['value'], '台北');
      expect((cloud.data['b']!['entries'] as List).single['value'], '高雄');
    },
  );
}
