import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/app_matcher.dart';

import 'support/sounds.dart';

InstalledApp app(String label) =>
    InstalledApp(label: label, package: 'pkg.$label');

void main() {
  final apps = [
    app('LINE'),
    app('LINE Bank'),
    app('YouTube'),
    app('YouTube Music'),
    app('地圖'),
    app('圖庫'),
    app('Google 相簿'),
    app('相機'),
    app('時鐘'),
    app('設定'),
    app('蝦皮購物'),
    app('健保快易通'),
  ];
  String? open(String spoken) => matchApp(spoken, apps)?.label;

  test('the exact name wins over longer names that contain it', () {
    expect(open('LINE'), 'LINE');
    expect(open('youtube'), 'YouTube');
    expect(open('相機'), '相機');
  });

  test('part of a name is enough', () {
    expect(open('健保'), '健保快易通');
    expect(open('蝦皮'), '蝦皮購物');
    expect(open('YouTube Music'), 'YouTube Music');
  });

  test('everyday words find the phone maker\'s own app', () {
    expect(open('相簿'), 'Google 相簿');
    expect(open('照片'), '圖庫');
    expect(open('鬧鐘'), '時鐘');
    expect(open('賴'), 'LINE');
    expect(open('Google 地圖'), '地圖');
  });

  test('things that are not apps match nothing', () {
    expect(open('冷氣'), isNull);
    expect(open('門'), isNull);
    expect(open(''), isNull);
    expect(matchApp('LINE', const []), isNull);
  });

  group('by sound', () {
    String? heard(String spoken) =>
        matchApp(spoken, apps, sounds: shippedSounds)?.label;

    test('a name written in other characters opens the app', () {
      for (final name in ['瞎皮', '象機', '健寶', '設訂']) {
        expect(open(name), isNull, reason: name);
      }
      expect(heard('瞎皮'), '蝦皮購物');
      expect(heard('象機'), '相機');
      expect(heard('健寶'), '健保快易通');
      expect(heard('設訂'), '設定');
    });

    test('everyday words heard wrong find the phone maker\'s own app', () {
      expect(heard('鬧中'), '時鐘');
      expect(heard('來'), 'LINE');
      // As with 相簿 itself, the word that was said comes before 圖庫.
      expect(heard('相不'), 'Google 相簿');
    });

    test('names that fit as written open the same app as before', () {
      for (final name in [
        'LINE', 'youtube', '相機', '健保', '蝦皮', 'YouTube Music', //
        '相簿', '照片', '鬧鐘', '賴', 'Google 地圖', '',
      ]) {
        expect(heard(name), open(name), reason: name);
      }
    });

    test('things that are not apps still match nothing', () {
      expect(heard('冷氣'), isNull);
      expect(heard('電視'), isNull);
      expect(heard('門'), isNull);
      expect(heard('燈'), isNull);
    });
  });
}
