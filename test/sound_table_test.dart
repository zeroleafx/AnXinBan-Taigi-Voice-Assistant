import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/sound_table.dart';

import 'support/sounds.dart';

void main() {
  final sounds = shippedSounds;

  test('the same characters cost nothing', () {
    expect(sounds.alike('阿明', '阿明'), 0);
    expect(sounds.alike('LINE', 'LINE'), 0);
  });

  test('characters read alike in either language sound alike', () {
    // Both are ming in Mandarin and bêng in Taiwanese.
    expect(sounds.alike('阿銘', '阿明'), 1);
    // Taiwanese only: 德 and 竹 are both tek.
    expect(sounds.alike('阿竹', '阿德'), 1);
    // Mandarin only: 志 is chì in Taiwanese, 智 is tì.
    expect(sounds.alike('智明', '志明'), 1);
    // A second reading counts: 樂 is also yue, 名 is also bêng.
    expect(sounds.alike('音月', '音樂'), 1);
    expect(sounds.alike('阿名', '阿明'), 1);
  });

  test('sounds that are easily mistaken are close', () {
    expect(sounds.alike('阿新', '阿星'), 4);
    expect(sounds.alike('小林', '小凌'), 4);
    expect(sounds.alike('位子', '位置'), 4);
  });

  test('other characters are never alike', () {
    expect(sounds.alike('淑芳', '淑芬'), isNull);
    expect(sounds.alike('阿發', '阿華'), isNull);
    expect(sounds.alike('志明', '春嬌'), isNull);
    // Letters and digits have no sound on record.
    expect(sounds.alike('lime', 'line'), isNull);
    expect(sounds.alike('119', '110'), isNull);
  });

  test('words of different lengths are not compared', () {
    expect(sounds.alike('手電', '手電筒'), isNull);
    expect(sounds.alike('', ''), isNull);
  });

  test('a single character must sound the same, not just close', () {
    expect(sounds.alike('來', '賴'), 1);
    expect(sounds.alike('林', '凌'), isNull);
  });

  test('a word allows one close sound, and any number of the same', () {
    expect(sounds.alike('汪曉名', '王小明', name: true), 3);
    // 新 and 星, then 林 and 凌: two close sounds are too far.
    expect(sounds.alike('新林', '星凌', name: true), isNull);
  });

  test('an everyday word keeps most of its characters', () {
    expect(sounds.alike('手電桶', '手電筒'), 1);
    expect(sounds.alike('手店筒', '手電筒'), 1);
    expect(sounds.alike('首店桶', '手電筒'), isNull);
    expect(sounds.alike('大吉', '打給'), isNull);
    expect(sounds.alike('緊急連落人', '緊急聯絡人'), 2);
  });

  test('a name may be written in other characters throughout', () {
    expect(sounds.alike('智銘', '志明'), isNull);
    expect(sounds.alike('智銘', '志明', name: true), 2);
  });

  test('within finds the closest stretch', () {
    expect(sounds.within('美齡', '陳美玲', name: true), 1);
    expect(sounds.within('美玲', '陳美玲'), 0);
    expect(sounds.within('美華', '陳美玲', name: true), isNull);
    expect(sounds.within('陳美玲小姐', '美玲'), isNull);
  });

  group('Taiwanese sounds fold together', () {
    void close(String a, String b) =>
        expect(looseTaigi(a), looseTaigi(b), reason: '$a, $b');
    void apart(String a, String b) =>
        expect(looseTaigi(a), isNot(looseTaigi(b)), reason: '$a, $b');

    test('with and without a puff of air', () {
      close('pang', 'phang');
      close('tang', 'thang');
      close('kO', 'khO');
      close('chiu', 'chhiu');
    });

    test('voiced and nasal initials', () {
      close('bi', 'mi');
      close('lai', 'nai');
      close('gO', 'ngO');
      close('jit', 'lit');
    });

    test('nasal vowels, the glottal stop and the open o', () {
      close('saN', 'sa');
      close('tah', 'ta');
      close('hO', 'ho');
      close('hiahN', 'hia');
    });

    test('endings', () {
      close('tiam', 'tian');
      close('tian', 'tiang');
      close('lip', 'lit');
      close('lek', 'let');
    });

    test('syllables that are a nasal alone', () {
      expect(looseTaigi('ng'), 'ng');
      expect(looseTaigi('m'), 'm');
      close('ngh', 'ng');
      close('mng', 'bng');
      apart('hng', 'hn');
      apart('ng', 'n');
    });

    test('other sounds stay apart', () {
      apart('ti', 'chi');
      apart('si', 'chi');
      apart('hoa', 'hoat');
      apart('kim', 'kam');
    });
  });

  group('Mandarin sounds fold together', () {
    void close(String a, String b) =>
        expect(looseMandarin(a), looseMandarin(b), reason: '$a, $b');
    void apart(String a, String b) =>
        expect(looseMandarin(a), isNot(looseMandarin(b)), reason: '$a, $b');

    test('with and without the tongue curled', () {
      close('zhi', 'zi');
      close('chang', 'can');
      close('shu', 'su');
    });

    test('n, l and r', () {
      close('nan', 'lan');
      close('re', 'le');
      // The sounds people make without a word are left as they are.
      expect(looseMandarin('n'), 'n');
      expect(looseMandarin('ng'), 'ng');
    });

    test('-ng after a, e and i', () {
      close('xin', 'xing');
      close('fen', 'feng');
      close('wan', 'wang');
      apart('dong', 'don');
    });

    test('ü said as i', () {
      close('lv', 'li');
      close('nve', 'lie');
      close('yu', 'yi');
      close('yue', 'ye');
      close('yuan', 'yan');
      close('yun', 'yin');
      close('ju', 'ji');
      close('quan', 'qian');
      close('xue', 'xie');
      apart('you', 'yi');
      apart('lu', 'li');
    });

    test('other sounds stay apart', () {
      apart('da', 'ta');
      apart('fa', 'hua');
      apart('ji', 'qi');
    });
  });

  group('the table that ships with the app', () {
    final lines = File('assets/fuzzy/char_readings.txt').readAsLinesSync();

    test('has well-formed lines for both languages', () {
      final line = RegExp(r'^[TM] [a-zNO]+ [\u4e00-\u9fff]+$');
      final entries = lines.where((line) => !line.startsWith('#')).toList();
      expect(entries.where((entry) => !line.hasMatch(entry)), isEmpty);
      expect(entries.where((entry) => entry.startsWith('T ')), isNotEmpty);
      expect(entries.where((entry) => entry.startsWith('M ')), isNotEmpty);
    });

    test('is read from the app bundle', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bundled = await SoundTable.load();
      expect(bundled, isNotNull);
      expect(bundled!.alike('阿銘', '阿明'), 1);
    });

    test('lines that are not readings are skipped', () {
      final table = SoundTable.parse('# 明銘\n\nM ming 明銘\nnot a reading\n');
      expect(table.alike('銘', '明'), 1);
    });
  });
}
