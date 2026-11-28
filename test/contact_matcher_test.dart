import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/contact_matcher.dart';

import 'support/sounds.dart';

ContactEntry person(String name, {String? nickname, String number = '0912'}) =>
    ContactEntry(name: name, nickname: nickname, numbers: [number]);

List<String> names(List<ContactEntry> contacts) => [
  for (final contact in contacts) contact.name,
];

void main() {
  final book = [
    person('阿明'),
    person('王小明'),
    person('媽媽'),
    person('陳志明'),
    person('女兒小美'),
    person('李大華', nickname: '華哥'),
    const ContactEntry(name: '沒有電話', numbers: []),
  ];

  test('an exact name wins over partial matches', () {
    expect(names(matchContacts('阿明', book)), ['阿明']);
  });

  test('a shortened name offers every close match to choose from', () {
    final others = book.where((c) => c.name != '阿明');
    expect(names(matchContacts('阿明', others)), ['王小明', '陳志明']);
  });

  test('family words match how the contact was saved', () {
    expect(names(matchContacts('阿母', book)), ['媽媽']);
    expect(names(matchContacts('女兒', book)), ['女兒小美']);
  });

  test('nicknames and titles are understood', () {
    expect(names(matchContacts('華哥', book)), ['李大華']);
    expect(names(matchContacts('王小明先生', book)), ['王小明']);
  });

  test('contacts without a phone number are never offered', () {
    expect(matchContacts('沒有電話', book), isEmpty);
    expect(matchContacts('不存在的人', book), isEmpty);
    expect(matchContacts('', book), isEmpty);
  });

  group('by sound', () {
    List<String> heard(String name, [Iterable<ContactEntry>? among]) =>
        names(matchContacts(name, among ?? book, sounds: shippedSounds));

    test('a name written in other characters finds the person', () {
      for (final name in ['阿銘', '小名', '志銘', '大花']) {
        expect(matchContacts(name, book), isEmpty, reason: name);
      }
      expect(heard('阿銘'), ['阿明']);
      expect(heard('小名'), ['王小明']);
      expect(heard('志銘'), ['陳志明']);
      expect(heard('大花'), ['李大華']);
      expect(heard('汪曉名'), ['王小明']);
      expect(heard('女而'), ['女兒小美']);
    });

    test('a title or extra words around the name do not matter', () {
      expect(heard('志銘先生'), ['陳志明']);
      expect(heard('銘哥', [person('阿明'), person('林淑芬')]), ['阿明']);
      expect(heard('小美阿姨', [person('曉梅'), person('阿明')]), ['曉梅']);
    });

    test('a family word heard wrong still finds how it was saved', () {
      expect(heard('阿木'), ['媽媽']);
      expect(heard('女而', [person('查某囝'), person('阿明')]), ['查某囝']);
      // Someone called 阿木 as written is still offered.
      final people = [person('林木森'), person('媽媽')];
      expect(names(matchContacts('阿木', people)), ['林木森']);
      expect(heard('阿木', people), ['媽媽', '林木森']);
      expect(heard('阿木', [person('阿木'), person('媽媽')]), ['阿木']);
    });

    test('names that fit as written are found as before', () {
      for (final name in ['阿明', '阿母', '女兒', '華哥', '王小明先生', '沒有電話', '']) {
        expect(heard(name), names(matchContacts(name, book)), reason: name);
      }
      final others = book.where((c) => c.name != '阿明');
      expect(heard('阿明', others), ['王小明', '陳志明']);
    });

    test('a closer name by sound comes first, the written one stays', () {
      final people = [person('王銘傳'), person('阿明'), person('林淑芬')];
      expect(names(matchContacts('阿銘', people)), ['王銘傳']);
      expect(heard('阿銘', people), ['阿明', '王銘傳']);
      // Said the same way, 阿明 could be either of them.
      final others = [person('王小明'), person('阿銘')];
      expect(heard('阿明', others), ['阿銘', '王小明']);
    });

    test('a name that fits whole as written is the only answer', () {
      expect(heard('阿明', [person('阿銘'), person('阿明')]), ['阿明']);
    });

    test('close calls are all offered, the closest first', () {
      final people = [person('黃智明'), person('陳志明'), person('林淑芬')];
      expect(heard('志銘', people), ['陳志明', '黃智明']);
      expect(heard('智銘', people), ['黃智明', '陳志明']);
      // Part of a name as written is hardly surer than a whole name by
      // sound, so both are offered.
      final two = [person('美齡'), person('陳美玲')];
      expect(heard('美玲', two), ['陳美玲', '美齡']);
    });

    test('a name that only shares some sounds is not offered', () {
      expect(heard('阿發'), isEmpty);
      expect(heard('淑芳', [person('林淑芬')]), isEmpty);
      expect(heard('春嬌'), isEmpty);
      expect(heard('不存在的人'), isEmpty);
    });
  });
}
