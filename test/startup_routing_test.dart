import 'package:an_xin_ban/family_cloud.dart';
import 'package:an_xin_ban/family_demo_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestCloud extends FamilyCloud {
  String? id = 'elder';
  bool offline = false;
  List<Map<String, dynamic>> rows = [];
  @override
  String? get user => id;
  @override
  Future<List<Map<String, dynamic>>> links() async {
    if (offline) throw Exception('offline');
    return rows;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('only a linked elder skips role selection', () async {
    final cloud = TestCloud()
      ..rows = [
        {'elder_id': 'elder', 'owner_id': 'family'},
      ];
    expect(await cloud.shouldOpenRecorder(), isTrue);
    cloud.id = 'family';
    expect(await cloud.shouldOpenRecorder(), isFalse);
  });
  test('offline cache is bound to the paired account', () async {
    final cloud = TestCloud()
      ..rows = [
        {'elder_id': 'elder'},
      ];
    expect(await cloud.shouldOpenRecorder(), isTrue);
    cloud.offline = true;
    expect(await cloud.shouldOpenRecorder(), isTrue);
    cloud.id = 'other';
    expect(await cloud.shouldOpenRecorder(), isFalse);
  });
  test(
    'confirmed unlink removes cached routing and synchronized settings',
    () async {
      final cloud = TestCloud()
        ..rows = [
          {'elder_id': 'elder'},
        ];
      await cloud.shouldOpenRecorder();
      await FamilyDemoStore().write('applied', [
        {'label': '家'},
      ]);
      cloud.rows = [];
      expect(await cloud.shouldOpenRecorder(), isFalse);
      expect(await FamilyDemoStore().read('applied'), isEmpty);
      cloud.offline = true;
      expect(await cloud.shouldOpenRecorder(), isFalse);
    },
  );
}
