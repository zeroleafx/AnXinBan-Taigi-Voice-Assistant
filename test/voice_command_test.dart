import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/voice_command.dart';

import 'support/sounds.dart';

Matcher opens(PhoneApp app) =>
    isA<OpenAppCommand>().having((c) => c.app, 'app', app);
Matcher calls(String name) =>
    isA<CallContactCommand>().having((c) => c.name, 'name', name);
Matcher dials(String number) =>
    isA<DialNumberCommand>().having((c) => c.number, 'number', number);
Matcher torch({required bool? on}) =>
    isA<FlashlightCommand>().having((c) => c.on, 'on', on);
Matcher goesTo(String place) =>
    isA<NavigateCommand>().having((c) => c.place, 'place', place);
Matcher searches(String query) =>
    isA<VideoSearchCommand>().having((c) => c.query, 'query', query);
Matcher sharesWith(String name, {bool line = false}) =>
    isA<ShareLocationCommand>()
        .having((c) => c.name, 'name', name)
        .having((c) => c.viaLine, 'viaLine', line);
Matcher writes(String name, String body, {bool line = false}) =>
    isA<SendMessageCommand>()
        .having((c) => c.name, 'name', name)
        .having((c) => c.body, 'body', body)
        .having((c) => c.viaLine, 'viaLine', line);
Matcher setsContact(String name) =>
    isA<SetEmergencyContactCommand>().having((c) => c.name, 'name', name);
Matcher opensNamed(String name, {required bool certain}) =>
    isA<OpenNamedAppCommand>()
        .having((c) => c.name, 'name', name)
        .having((c) => c.certain, 'certain', certain);
Matcher date({required bool lunar}) =>
    isA<DateCommand>().having((c) => c.lunar, 'lunar', lunar);

void main() {
  void expectCommand(String transcript, Matcher matcher) =>
      expect(parseVoiceCommand(transcript), matcher, reason: transcript);

  test('opens apps however LINE is written', () {
    expectCommand('幫我開LINE', opens(PhoneApp.line));
    expectCommand('幫我開 Line。', opens(PhoneApp.line));
    expectCommand('打開ＬＩＮＥ', opens(PhoneApp.line));
    expectCommand('LINE', opens(PhoneApp.line));
    expectCommand('開賴', opens(PhoneApp.line));
    expectCommand('我要看YouTube', opens(PhoneApp.youtube));
    expectCommand('幫我上臉書', opens(PhoneApp.facebook));
    expectCommand('打開地圖', opens(PhoneApp.maps));
    expectCommand('看簡訊', opens(PhoneApp.messages));
  });

  test('calls a contact by name', () {
    expectCommand('幫我打電話給阿明', calls('阿明'));
    expectCommand('幫我打電話予阿明', calls('阿明'));
    expectCommand('打給女兒好嗎', calls('女兒'));
    expectCommand('幫我給阿明打個電話', calls('阿明'));
    expectCommand('敲電話予阿母', calls('阿母'));
    expectCommand('打電話給王小明的手機', calls('王小明'));
    expectCommand('打电话给妈妈', calls('媽媽'));
    expectCommand('聯絡陳老師', calls('陳老師'));
  });

  test('asks who to call when no one is named', () {
    expectCommand('幫我打電話', calls(''));
  });

  test('a contact named 賴 does not open LINE', () {
    expectCommand('打電話給賴先生', calls('賴先生'));
  });

  test('dials spoken numbers', () {
    expectCommand('打119', dials('119'));
    expectCommand('撥一一九', dials('119'));
    expectCommand('打電話給零九一二三四五六七八', dials('0912345678'));
  });

  test('turns the flashlight on and off', () {
    expectCommand('打開手電筒', torch(on: true));
    expectCommand('幫我開手電筒', torch(on: true));
    expectCommand('手電筒關掉', torch(on: false));
    expectCommand('把电筒关掉', torch(on: false));
    expectCommand('開電火', torch(on: true));
  });

  test('understands the ways people switch the flashlight off', () {
    expectCommand('手電筒禁掉', torch(on: false));
    expectCommand('共電火禁掉', torch(on: false));
    expectCommand('手電筒不用了', torch(on: false));
    expectCommand('不用手電筒了', torch(on: false));
    expectCommand('手電筒熄掉', torch(on: false));
    expectCommand('手電筒收起來', torch(on: false));
    expectCommand('不要開手電筒', torch(on: false));
    expectCommand('手电筒灭掉', torch(on: false));
  });

  test('dark rooms and power cuts ask for light', () {
    expectCommand('好暗，幫我開手電筒', torch(on: true));
    expectCommand('停電了開手電筒', torch(on: true));
    expectCommand('點電火', torch(on: true));
  });

  test('just naming the flashlight switches it over', () {
    expectCommand('手電筒', torch(on: null));
    expectCommand('手電筒好了', torch(on: null));
  });

  test('a short "關掉" reaches the flashlight only while it is on', () {
    for (final words in ['關掉', '關燈', '幫我關起來', '不用了']) {
      expect(
        parseVoiceCommand(words, torchOn: true),
        torch(on: false),
        reason: words,
      );
      expect(parseVoiceCommand(words), isA<UnknownCommand>(), reason: words);
    }
    // Other requests still work while the light is on.
    expect(parseVoiceCommand('打給阿明', torchOn: true), calls('阿明'));
  });

  test('navigates to a place', () {
    expectCommand('帶我去台北車站', goesTo('台北車站'));
    expectCommand('幫我導航到彰化火車站', goesTo('彰化火車站'));
    expectCommand('去台北車站要怎麼走', goesTo('台北車站'));
    expectCommand('郵局在哪裡', goesTo('郵局'));
    expectCommand('開地圖帶我去台北車站', goesTo('台北車站'));
    expectCommand('幫我開導航', opens(PhoneApp.maps));
  });

  test('daily phrases that are not places are not navigation', () {
    expectCommand('我要去睡覺', isA<UnknownCommand>());
    expectCommand('我要去看醫生', isA<UnknownCommand>());
  });

  test('asks where I am', () {
    expectCommand('我在哪裡', isA<WhereAmICommand>());
    expectCommand('我現在在哪裡？', isA<WhereAmICommand>());
    expectCommand('請問這裡是哪裡啊', isA<WhereAmICommand>());
    expectCommand('我人在哪', isA<WhereAmICommand>());
    expectCommand('告訴我我在哪裡', isA<WhereAmICommand>());
    expectCommand('我的位置', isA<WhereAmICommand>());
    expectCommand('郵局在哪裡', goesTo('郵局'));
  });

  test('a call for help', () {
    expectCommand('救命', isA<EmergencyCommand>());
    expectCommand('救命啊！', isA<EmergencyCommand>());
    expectCommand('我跌倒了', isA<EmergencyCommand>());
    expectCommand('SOS', isA<EmergencyCommand>());
    expectCommand('打給緊急聯絡人', isA<EmergencyCommand>());
    expectCommand('幫我聯絡緊急連絡人', isA<EmergencyCommand>());
  });

  test('ambulance and police are called, their stations are places', () {
    expectCommand('叫救護車', dials('119'));
    expectCommand('失火了', dials('119'));
    expectCommand('幫我報警', dials('110'));
    expectCommand('帶我去消防隊', goesTo('消防隊'));
    expectCommand('警察局在哪裡', goesTo('警察局'));
  });

  test('chooses the emergency contact', () {
    expectCommand('把女兒設成緊急聯絡人', setsContact('女兒'));
    expectCommand('把我女兒設為緊急連絡人', setsContact('女兒'));
    expectCommand('緊急聯絡人改成阿明', setsContact('阿明'));
    expectCommand('設阿明為緊急聯絡人', setsContact('阿明'));
    expectCommand('設定緊急聯絡人', setsContact(''));
    expectCommand('我的緊急聯絡人是誰', setsContact(''));
    expectCommand('誰是我的緊急聯絡人？', setsContact(''));
    expectCommand('取消緊急聯絡人', isA<ClearEmergencyContactCommand>());
  });

  test('sends my location', () {
    expectCommand('把我的位置傳給女兒', sharesWith('女兒'));
    expectCommand('傳位置給阿明', sharesWith('阿明'));
    expectCommand('跟女兒說我在哪裡', sharesWith('女兒'));
    expectCommand('告訴我女兒我在哪裡', sharesWith('女兒'));
    expectCommand('分享我的位置', sharesWith(''));
    expectCommand('把位置傳給家人', sharesWith(''));
    expectCommand('用LINE傳我的位置', sharesWith('', line: true));
    expectCommand('用 LINE 把位置傳給女兒', sharesWith('', line: true));
  });

  test('writes a message with the words as they were said', () {
    expectCommand('傳簡訊給阿明說我晚一點到', writes('阿明', '我晚一點到'));
    expectCommand('傳簡訊給阿明', writes('阿明', ''));
    expectCommand('幫我傳訊息給女兒，說我到家了。', writes('女兒', '我到家了。'));
    expectCommand('傳簡訊給阿明說我在 Costco 等你', writes('阿明', '我在 Costco 等你'));
    expectCommand('用LINE跟女兒說我到了', writes('', '我到了', line: true));
    expectCommand('看簡訊', opens(PhoneApp.messages));
    expectCommand('傳賴給女兒講我到了', writes('', '我到了', line: true));
    expectCommand('用LINE打給阿明', opens(PhoneApp.line));
    expectCommand('開LINE講電話', opens(PhoneApp.line));
    expectCommand('用LINE跟女兒講電話', opens(PhoneApp.line));
  });

  test('opens other apps by name', () {
    expectCommand('打開相機', opensNamed('相機', certain: true));
    expectCommand('相機打開', opensNamed('相機', certain: true));
    expectCommand('幫我打開 Instagram 好嗎', opensNamed('instagram', certain: true));
    expectCommand('打開電話', opensNamed('電話', certain: true));
    expectCommand('開相簿', opensNamed('相簿', certain: false));
    expectCommand('開冷氣', opensNamed('冷氣', certain: false));
    expectCommand('幫我開LINE', opens(PhoneApp.line));
    expectCommand('打開手電筒', torch(on: true));
  });

  test('names keep their first character', () {
    expectCommand('打給我女兒', calls('女兒'));
    expectCommand('打給阮小姐', calls('阮小姐'));
    expectCommand('打給和平', calls('和平'));
  });

  test('answers time, date and weather questions', () {
    expectCommand('現在幾點', isA<TimeCommand>());
    expectCommand('今天禮拜幾', date(lunar: false));
    expectCommand('今天幾號', date(lunar: false));
    expectCommand('今天農曆幾號', date(lunar: true));
    expectCommand('今天初幾', date(lunar: true));
    expectCommand('今天會下雨嗎', isA<WeatherCommand>());
  });

  test('searches YouTube for songs', () {
    expectCommand('我想聽鄧麗君的歌', searches('鄧麗君的歌'));
    expectCommand('放一首望春風', searches('望春風'));
  });

  test('unknown requests stay unknown', () {
    expectCommand('', isA<UnknownCommand>());
    expectCommand('今天心情不錯', isA<UnknownCommand>());
  });

  test('normalization keeps names but drops punctuation and spaces', () {
    expect(normalizeTranscript('幫我 開 LINE！'), '幫我開line');
    expect(spokenDigits('零九一二'), '0912');
    expect(spokenDigits('阿明'), isNull);
  });

  group('guessing by sound', () {
    VoiceCommand? guess(String transcript, {bool torchOn = false}) =>
        guessVoiceCommand(transcript, shippedSounds, torchOn: torchOn);
    void expectGuess(String transcript, Matcher matcher) {
      final asWritten = parseVoiceCommand(transcript);
      expect(
        asWritten,
        anyOf(isA<UnknownCommand>(), isA<OpenNamedAppCommand>()),
        reason: '$transcript is understood as written',
      );
      expect(guess(transcript), matcher, reason: transcript);
    }

    test('a word that sounds like a known one is read as that word', () {
      expectGuess('開手店筒', torch(on: true));
      expectGuess('閃光登打開', torch(on: true));
      expectGuess('打店話給阿明', calls('阿明'));
      expectGuess('大電話給女兒', calls('女兒'));
      expectGuess('導行到台北車站', goesTo('台北車站'));
      expectGuess('代我去郵局', goesTo('郵局'));
      expectGuess('今天星期己', date(lunar: false));
      expectGuess('我的位址在哪裡', isA<WhereAmICommand>());
      expectGuess('把我的位志傳給女兒', sharesWith('女兒'));
      expectGuess('傳檢訊給阿明說我晚一點到', writes('阿明', '我晚一點到'));
    });

    test('a call for help is made out', () {
      expectGuess('就我', isA<EmergencyCommand>());
      expectGuess('我跌到了', isA<EmergencyCommand>());
      expectGuess('我摔到了', isA<EmergencyCommand>());
      expectGuess('快叫九護車', dials('119'));
      expectGuess('找警查', dials('110'));
      expectGuess('把女兒設成緊急連落人', setsContact('女兒'));
      expectGuess('取消緊急連落人', isA<ClearEmergencyContactCommand>());
    });

    test('apps are known by the sound of their names', () {
      expectGuess('開來', opens(PhoneApp.line));
      expectGuess('打開來恩', opens(PhoneApp.line));
      expectGuess('打開優吐', opens(PhoneApp.youtube));
      expectGuess('開油罐', opens(PhoneApp.youtube));
      expectGuess('上臉輸', opens(PhoneApp.facebook));
      expectGuess('看減訊', opens(PhoneApp.messages));
      expectGuess('打開信息', opens(PhoneApp.messages));
      expectGuess('開地途', opens(PhoneApp.maps));
    });

    test('several words heard wrong are all put right', () {
      expectGuess('打店話給緊急連落人', isA<EmergencyCommand>());
    });

    test('a message keeps its words as they were said', () {
      expectGuess('傳檢訊給阿明說 我晚一點到，OK 嗎？', writes('阿明', '我晚一點到，OK 嗎？'));
      expectGuess('傳檢訊給阿明', writes('阿明', ''));
    });

    test('what is understood as written is left alone', () {
      for (final transcript in [
        '幫我開LINE', '打給阿明', '開手電筒', '帶我去台北車站', '現在幾點', //
        '救命', '傳簡訊給阿明說我晚一點到', '我想聽鄧麗君的歌', '',
      ]) {
        expect(guess(transcript), isNull, reason: transcript);
      }
      expect(guess('關掉', torchOn: true), isNull);
    });

    test('other apps keep their names', () {
      for (final transcript in ['打開相機', '打開股票', '開冷氣', '開門']) {
        expect(parseVoiceCommand(transcript), isA<OpenNamedAppCommand>());
        expect(guess(transcript), isNull, reason: transcript);
      }
    });

    test('everyday talk is not turned into a command', () {
      for (final transcript in [
        '今天心情不錯', '明天起床叫我', '幫我訂位', '我在小房間', '打擊犯罪', //
        '大吉大利', '我想停車', '極度疲勞', '做個記號', '即日起開始',
        '一百幾十塊', '活在當下', '洗臉梳頭', '收電費的來了', '他要娶老婆',
        '這個位子有人坐嗎', '用手點一下', '我的眼鏡放在哪', '藥吃了沒',
        '一朵花', '我的手機壞了', '明天的事明天再說', '把窗戶打開', '嗯嗯嗯',
      ]) {
        expect(guess(transcript), isNull, reason: transcript);
      }
    });
  });
}
