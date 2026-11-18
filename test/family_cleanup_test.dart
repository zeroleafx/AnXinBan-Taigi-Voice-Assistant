import 'package:an_xin_ban/family_demo_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('only a new server deletion clears family drafts', () async {
    final store = FamilyDemoStore();
    final draft = [
      {'label': '家'},
    ];
    await store.write('pending', draft);
    await store.reconcileCloudDeletion('owner', null);
    expect(await store.read('pending'), draft);
    await store.reconcileCloudDeletion('owner', 'deletion-1');
    expect(await store.read('pending'), isEmpty);
    await store.write('pending', draft);
    await store.reconcileCloudDeletion('owner', 'deletion-1');
    expect(await store.read('pending'), draft);
    await store.reconcileCloudDeletion('owner', 'deletion-2');
    expect(await store.read('pending'), isEmpty);
  });
}
