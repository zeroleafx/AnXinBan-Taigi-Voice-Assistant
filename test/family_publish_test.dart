import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/family_cloud.dart';

void main() {
  test('cloud JSON key ordering does not create a new version', () {
    expect(
      sameFamilySettings(
        [
          {'value': '台北', 'label': '家'},
        ],
        [
          {'label': '家', 'value': '台北'},
        ],
      ),
      isTrue,
    );
  });
  test('changed and removed settings require publication', () {
    final saved = [
      {'label': '家', 'value': '台北'},
    ];
    expect(
      sameFamilySettings(saved, [
        {'label': '家', 'value': '台南'},
      ]),
      isFalse,
    );
    expect(sameFamilySettings(saved, []), isFalse);
    expect(sameFamilySettings([], []), isTrue);
  });
}
