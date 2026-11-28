import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/assistant_controller.dart';
import 'package:an_xin_ban/contact_matcher.dart';
import 'package:an_xin_ban/taigi_phrases.dart';

import 'support/fake_phone.dart';
import 'support/sounds.dart';

/// Every symbol in facebook/mms-tts-nan's vocab.json. The model skips
/// anything else; ⁿ (a nasal vowel) is skipped too, so it is checked apart.
const _modelLetters = " '-abceghijklmnopstu|àáâèéêìíîòóôùúûāēīńōūǹ̂̄̍͘ḿ";

Set<String> _unknownLetters(String words) =>
    {for (final rune in words.toLowerCase().runes) String.fromCharCode(rune)}
        .difference({..._modelLetters.split(''), 'ⁿ'});

AssistantOutcome _card(
  String title, {
  String? detail,
  OutcomeTone tone = OutcomeTone.info,
}) => AssistantOutcome(
  tone: tone,
  icon: Icons.info_outline,
  title: title,
  detail: detail,
);

void main() {
  test('every fixed sentence uses only letters the voice can read', () {
    for (final words in fixedTaigiPhrases) {
      expect(_unknownLetters(words), isEmpty, reason: words);
      // A nasal vowel would be read without its nasal.
      expect(words, isNot(contains('ⁿ')), reason: words);
    }
  });

  test('times and dates are read in Taiwanese', () {
    expect(
      taigiSpeech(_card('現在是下午 3:25')),
      'Hiān-chāi sī ē-po͘ saⁿ tiám jī-cha̍p-gō͘ hun',
    );
    expect(
      taigiSpeech(_card('現在是早上 9:00')),
      'Hiān-chāi sī chá-khí káu tiám chéng',
    );
    expect(
      taigiSpeech(_card('現在是凌晨 1:02')),
      'Hiān-chāi sī thàu-chá chi̍t tiám nn̄g hun',
    );
    expect(
      taigiSpeech(_card('今天 11 月 18 日', detail: '星期三 · 農曆九月三十')),
      'Kin-á-ji̍t sī cha̍p-it-goe̍h cha̍p-peh hō pài-saⁿ',
    );
    expect(
      taigiSpeech(_card('農曆十月初二')),
      'Kin-á-ji̍t sī lông-le̍k cha̍p-goe̍h chhe-jī',
    );
    expect(
      taigiSpeech(_card('農曆閏六月廿一')),
      'Kin-á-ji̍t sī lông-le̍k lūn la̍k-goe̍h jia̍p-it',
    );
    expect(
      taigiSpeech(_card('農曆正月十五')),
      'Kin-á-ji̍t sī lông-le̍k chiaⁿ-goe̍h cha̍p-gō͘',
    );
    for (final title in ['現在是晚上 12:59', '今天 12 月 31 日', '農曆十二月三十']) {
      final words = taigiSpeech(_card(title, detail: '星期日'));
      expect(words, isNotNull, reason: title);
      expect(_unknownLetters(words!), isEmpty, reason: words);
    }
  });

  test('numbers', () {
    expect(taigiNumber(7), 'chhit');
    expect(taigiNumber(10), 'cha̍p');
    expect(taigiNumber(11), 'cha̍p-it');
    expect(taigiNumber(20), 'jī-cha̍p');
    expect(taigiNumber(31), 'saⁿ-cha̍p-it');
  });

  test('names stay on the card and are not read out', () {
    expect(taigiSpeech(_card('要打給 阿明 嗎？')), 'Lí beh khà tiān-ōe hō͘ i bô');
    expect(
      taigiSpeech(_card('要開啟 LINE 嗎？')),
      'Lí beh phah-khui chit ê thêng-sek bô',
    );
    expect(
      taigiSpeech(_card('找不到「阿花」', detail: '通訊錄裡沒有這個名字')),
      'Thong-sìn-lo̍k lāi-té chhōe bô chit ê lâng ê miâ',
    );
    expect(
      taigiSpeech(_card('找不到「相簿」', detail: '手機裡沒有這個 App')),
      'Chhiú-ki lāi-té chhōe bô chit ê thêng-sek',
    );
  });

  test('the emergency contact card says whether one is set', () {
    expect(
      taigiSpeech(_card('緊急聯絡人', detail: '還沒設定')),
      'Lí iáu-bē siat-tēng kín-kip liân-lo̍k-jîn',
    );
    expect(
      taigiSpeech(_card('緊急聯絡人', detail: '女兒 0911')),
      'Che sī lí ê kín-kip liân-lo̍k-jîn',
    );
    expect(
      taigiSpeech(_card('緊急聯絡人', detail: '女兒 0911', tone: OutcomeTone.done)),
      'Kín-kip liân-lo̍k-jîn í-keng siat-tēng hó ah',
    );
  });

  test('the recording cards on the home screen are read too', () {
    expect(
      taigiRecordingSpeech(micDenied: true, error: '需要麥克風權限，請到設定打開。'),
      'Ài khui lio̍k-im ê koân-hān',
    );
    expect(
      taigiRecordingSpeech(micDenied: false, error: '錄音未能儲存，請重新錄音。'),
      'Lio̍k-im bô seng-kong koh chhì chi̍t pái',
    );
    expect(
      taigiRecordingSpeech(micDenied: false, speechError: '沒有聽到聲音，請再講一次。'),
      'Bô lio̍k tio̍h lí ê ōe koh kóng chi̍t pái',
    );
    expect(
      taigiRecordingSpeech(micDenied: false, speechError: '這段沒有聽清楚，可以再試一次。'),
      'Bô hoat-tō͘ piān-sek lí kóng ê ōe koh kóng chi̍t pái',
    );
    expect(taigiRecordingSpeech(micDenied: false), isNull);
  });

  test('an unknown title is not read', () {
    expect(taigiSpeech(_card('某個新的標題')), isNull);
  });

  group('cards the assistant really shows are read', () {
    late FakePhone phone;
    late AssistantController assistant;

    setUp(() {
      phone = FakePhone()
        ..contacts = const [
          ContactEntry(name: '阿明', numbers: ['0912 345 678']),
        ];
      assistant = AssistantController(
        phone,
        now: () => DateTime(2026, 11, 10, 15, 5),
      );
    });
    tearDown(() => assistant.dispose());

    Future<String?> say(String heard) async {
      await assistant.handle(heard);
      return taigiSpeech(assistant.outcome!);
    }

    test('everyday requests', () async {
      expect(await say('開手電筒'), 'Chhiú-tiān-tâng í-keng phah-khui ah');
      expect(await say('手電筒關掉'), 'Chhiú-tiān-tâng í-keng khìm-tiāu ah');
      expect(await say('現在幾點'), 'Hiān-chāi sī ē-po͘ saⁿ tiám gō͘ hun');
      expect(
        await say('今天禮拜幾'),
        'Kin-á-ji̍t sī cha̍p-it-goe̍h cha̍p hō pài-jī',
      );
      expect(await say('今天農曆幾號'), startsWith('Kin-á-ji̍t sī lông-le̍k '));
      expect(await say('打給阿明'), 'Lí beh khà tiān-ōe hō͘ i bô');
      expect(
        await say('打給阿花'),
        'Thong-sìn-lo̍k lāi-té chhōe bô chit ê lâng ê miâ',
      );
      expect(await say('開LINE'), 'Lí beh phah-khui chit ê thêng-sek bô');
      expect(await say('嗯嗯嗯'), 'Chit kù ōe góa iáu bô hoat-tō͘ chhú-lí');
    });

    test('every card, and every card behind its buttons, has words', () async {
      // A new card without Taiwanese words would be shown but not read out.
      const requests = [
        '開手電筒', '手電筒關掉', '現在幾點', '今天禮拜幾', '今天農曆幾號', //
        '今天會下雨嗎', '打給阿明', '打給阿花', '打給', '打一一九',
        '撥零九一二三四五六七八', '叫救護車', '救命', '把阿明設成緊急聯絡人',
        '設定緊急聯絡人', '取消緊急聯絡人', '我在哪裡', '把我的位置傳給阿明',
        '分享我的位置', '用LINE傳我的位置', '傳簡訊給阿明說我晚一點到',
        '用LINE跟女兒說我到了', '傳簡訊', '帶我去台北車站', '郵局在哪裡',
        '開地圖', '我想聽鄧麗君的歌', '開LINE', '開YouTube', '上臉書',
        '看簡訊', '打開相機', '打開相簿', '嗯嗯嗯',
      ];
      final silent = <String>[];
      for (final heard in requests) {
        for (final works in [true, false]) {
          Future<AssistantController> ask() async {
            final phone = FakePhone()
              ..contacts = const [
                ContactEntry(name: '阿明', numbers: ['0912']),
              ]
              ..contactsAllowed = works
              ..canDial = works
              ..hasLine = works;
            final helper = AssistantController(
              phone,
              now: () => DateTime(2026, 11, 18, 15, 5),
            );
            await helper.handle(heard);
            return helper;
          }

          final first = await ask();
          final card = first.outcome!;
          if (taigiSpeech(card) == null) silent.add('$heard → ${card.title}');
          for (final label in [for (final b in card.buttons) b.label]) {
            final next = await ask();
            await next.press(
              next.outcome!.buttons.firstWhere((b) => b.label == label),
            );
            final after = next.outcome!;
            if (taigiSpeech(after) == null) {
              silent.add('$heard [$label] → ${after.title}');
            }
            next.dispose();
          }
          first.dispose();
        }
      }
      expect(silent, isEmpty);
    });

    test('the help card', () async {
      await assistant.showEmergency();
      expect(taigiSpeech(assistant.outcome!), 'Lí kám ū su-iàu lâng pang-bâng');
    });

    test('cards for what was made out by sound have words too', () async {
      assistant.sounds = shippedSounds;
      expect(await say('打給阿銘'), 'Lí beh khà tiān-ōe hō͘ i bô');
      expect(
        await say('把阿銘設成緊急聯絡人'),
        'Lí beh kā i siat-tēng chò kín-kip liân-lo̍k-jîn bô',
      );
      for (final heard in ['我跌到了', '快叫九護車', '開來', '開手店筒', '取消緊急連落人']) {
        expect(await say(heard), isNotNull, reason: heard);
        for (final button in assistant.outcome!.buttons) {
          await assistant.handle(heard);
          await assistant.press(
            assistant.outcome!.buttons.firstWhere(
              (b) => b.label == button.label,
            ),
          );
          final after = assistant.outcome!;
          expect(
            taigiSpeech(after),
            isNotNull,
            reason: '$heard [${button.label}] → ${after.title}',
          );
        }
      }
    });
  });
}
