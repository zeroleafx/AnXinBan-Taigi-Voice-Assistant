/// What the assistant says aloud, in Taiwanese.
///
/// The voice (Meta MMS-TTS, Min Nan) reads Pe̍h-ōe-jī (POJ) only, so every
/// reply is written here in POJ. Sentences are complete and plain rather than
/// clipped: the model reads full, written-style sentences more clearly. It
/// drops the nasal mark ⁿ, so words with a nasal vowel are swapped for a
/// synonym where one exists ("佗一位" rather than "啥人").
///
/// Names, numbers and addresses on a card are not read out; the card shows
/// them. Times and dates are.
library;

import 'package:flutter/foundation.dart';

import 'assistant_controller.dart';

/// The words to say for [outcome], or null when there is nothing to say.
String? taigiSpeech(AssistantOutcome outcome) {
  final title = outcome.title;
  final fixed = _fixed[title];
  if (fixed != null) return fixed;

  if (title == '緊急聯絡人') {
    if (outcome.tone == OutcomeTone.done) return _contactSaved;
    return outcome.detail == '還沒設定' ? _noContact : _contactShown;
  }
  if (title.startsWith('找不到「')) {
    return (outcome.detail ?? '').contains('通訊錄') ? _noSuchPerson : _noSuchApp;
  }
  final time = _time.firstMatch(title);
  if (time != null) {
    return _sayTime(
      time.group(1)!,
      int.parse(time.group(2)!),
      int.parse(time.group(3)!),
    );
  }
  final date = _date.firstMatch(title);
  if (date != null) {
    final weekday = _weekday.firstMatch(outcome.detail ?? '')?.group(1);
    return _sayDate(
      int.parse(date.group(1)!),
      int.parse(date.group(2)!),
      weekday,
    );
  }
  final lunar = _lunar.firstMatch(title);
  if (lunar != null) {
    final month = _lunarMonth(lunar.group(2)!);
    final day = _lunarDay(lunar.group(3)!);
    if (month != null && day != null) {
      final leap = lunar.group(1) == null ? '' : 'lūn ';
      return 'Kin-á-ji̍t sī lông-le̍k $leap$month-goe̍h $day';
    }
    return null;
  }
  for (final (pattern, words) in _patterns) {
    if (pattern.hasMatch(title)) return words;
  }
  return null;
}

/// The words for the recording's own cards on the home screen ("沒有聽清楚",
/// "需要麥克風權限"), which do not come from the assistant. Null when none
/// of them is shown.
String? taigiRecordingSpeech({
  required bool micDenied,
  String? error,
  String? speechError,
}) {
  if (micDenied) return _micDenied;
  if (error != null) return _recordingFailed;
  if (speechError == null) return null;
  // "沒有聽到聲音" is silence; anything else is speech that was not clear.
  return speechError.contains('沒有聽到') ? _noSound : _notHeard;
}

/// Every sentence this file can produce apart from times and dates, so tests
/// can check that the voice knows all of their letters.
@visibleForTesting
Iterable<String> get fixedTaigiPhrases => {
  ..._fixed.values,
  for (final (_, words) in _patterns) words,
  _contactSaved,
  _noContact,
  _contactShown,
  _noSuchPerson,
  _noSuchApp,
  _micDenied,
  _recordingFailed,
  _noSound,
  _notHeard,
};

const _micDenied = 'Ài khui lio̍k-im ê koân-hān';
const _recordingFailed = 'Lio̍k-im bô seng-kong koh chhì chi̍t pái';
const _noSound = 'Bô lio̍k tio̍h lí ê ōe koh kóng chi̍t pái';
const _notHeard = 'Bô hoat-tō͘ piān-sek lí kóng ê ōe koh kóng chi̍t pái';

const _noSuchApp = 'Chhiú-ki lāi-té chhōe bô chit ê thêng-sek';
const _noSuchPerson = 'Thong-sìn-lo̍k lāi-té chhōe bô chit ê lâng ê miâ';
const _contactSaved = 'Kín-kip liân-lo̍k-jîn í-keng siat-tēng hó ah';
const _noContact = 'Lí iáu-bē siat-tēng kín-kip liân-lo̍k-jîn';
const _contactShown = 'Che sī lí ê kín-kip liân-lo̍k-jîn';
const _opened = 'Í-keng phah-khui ah';
const _dialing = 'Chún-pī khà tiān-ōe';
const _written = 'ài chhi̍h sàng-chhut';

/// Card titles that never change.
const _fixed = {
  // Questions before something is opened or sent.
  '要撥打電話嗎？': 'Lí beh khà chit thong tiān-ōe bô',
  '要開啟導航嗎？': 'Lí beh iōng tē-tô͘ chhōa lō͘ bô',
  '要開啟地圖嗎？': 'Lí beh phah-khui tē-tô͘ bô',
  '要開啟網頁查天氣嗎？': 'Lí beh khui bāng-ia̍h cha khì-hāu bô',
  '要分享目前位置嗎？': 'Lí beh hun-hióng lí chit-má ê ūi-tì bô',
  '要取消緊急聯絡人嗎？': 'Lí beh chhú-siau kín-kip liân-lo̍k-jîn bô',
  '已開啟': _opened,
  '已取消': 'Í-keng chhú-siau ah',

  // Who is it for?
  '要打給誰？': 'Lí beh khà tiān-ōe hō͘ tó chi̍t ūi',
  '要打給哪一位？': 'Ū kúi ūi ê miâ sio-kāng lí beh khà hō͘ tó chi̍t ūi',
  '要傳給誰？': 'Lí beh thoân hō͘ tó chi̍t ūi',
  '要傳給哪一位？': 'Ū kúi ūi ê miâ sio-kāng lí beh thoân hō͘ tó chi̍t ūi',
  '要設定哪一位？': 'Ū kúi ūi ê miâ sio-kāng lí beh siat-tēng tó chi̍t ūi',

  // Help.
  '需要幫忙嗎？': 'Lí kám ū su-iàu lâng pang-bâng',
  '已取消緊急聯絡人': 'Kín-kip liân-lo̍k-jîn í-keng chhú-siau ah',

  // Flashlight.
  '手電筒開了': 'Chhiú-tiān-tâng í-keng phah-khui ah',
  '手電筒關了': 'Chhiú-tiān-tâng í-keng khìm-tiāu ah',
  '這支手機開不了手電筒': 'Chit ki chhiú-ki bô hoat-tō͘ khui chhiú-tiān-tâng',
  '手電筒關不掉': 'Chhiú-tiān-tâng khìm bē tiāu',

  // Places.
  '你在這裡': 'Í-keng chhōe tio̍h lí ê ūi-tì',
  '打不開地圖': 'Tē-tô͘ bô hoat-tō͘ phah-khui',
  '需要定位權限': 'Ài khui tēng-ūi ê koân-hān',
  '定位沒有打開': 'Tēng-ūi bô phah-khui',
  '現在找不到位置': 'Chit-má chhōe bô lí ê ūi-tì',
  '選一位朋友傳位置': 'Lí ē-tàng soán chi̍t ūi pêng-iú thoân ūi-tì',
  '選一位聯絡人傳位置': 'Lí ē-tàng soán chi̍t ūi liân-lo̍k-jîn thoân ūi-tì',

  // Messages and apps.
  '選一位朋友傳 LINE': 'Lí ē-tàng soán chi̍t ūi pêng-iú thoân sìn-sit',
  '打不開 YouTube': 'Bô hoat-tō͘ phah-khui chit ê thêng-sek',
  '幫你查天氣': 'Í-keng pang lí cha khì-hāu',
  '現在查不到天氣': 'Chit-má cha bô khì-hāu',
  '需要通訊錄權限': 'Ài khui thong-sìn-lo̍k ê koân-hān',
  '這支手機沒辦法撥號': 'Chit ki chhiú-ki bô hoat-tō͘ khà tiān-ōe',
  '這支手機沒辦法傳訊息': 'Chit ki chhiú-ki bô hoat-tō͘ thoân sìn-sit',

  // Not understood, or failed.
  '這句我還不會': 'Chit kù ōe góa iáu bô hoat-tō͘ chhú-lí',
  '這件事沒有做成': 'Tāi-chì bô chò seng-kong koh chhì chi̍t pái',
};

/// Card titles with a name or a number in them; the name is not read out.
final _patterns = [
  (RegExp(r'^要開啟 .+ 嗎？$'), 'Lí beh phah-khui chit ê thêng-sek bô'),
  (RegExp(r'^要打給 .+ 嗎？$'), 'Lí beh khà tiān-ōe hō͘ i bô'),
  (RegExp(r'^要傳簡訊給 .+ 嗎？$'), 'Lí beh thoân kán-sìn hō͘ i bô'),
  (RegExp(r'^要把位置傳給 .+ 嗎？$'), 'Lí beh kā ūi-tì thoân hō͘ i bô'),
  (RegExp(r'^已打開'), _opened),
  (RegExp(r'^手機裡找不到'), _noSuchApp),
  (RegExp(r'^(撥打|打給) '), _dialing),
  (RegExp(r'^正在打給 '), 'Tng-teh khà tiān-ōe hō͘ kín-kip liân-lo̍k-jîn'),
  (RegExp(r'^帶你去'), 'Tē-tô͘ í-keng phah-khui ah'),
  (RegExp(r'^傳簡訊給 '), 'Kán-sìn í-keng siá hó ah $_written'),
  (RegExp(r'^把位置傳給 '), 'Ūi-tì í-keng siá hó ah $_written'),
  (RegExp(r'^在 YouTube 找'), 'Í-keng chhōe hó ah'),
];

// "現在是下午 3:25", as written by the assistant's clock.
final _time = RegExp(r'^現在是(凌晨|早上|中午|下午|晚上) (\d{1,2}):(\d{2})$');
final _date = RegExp(r'^今天 (\d{1,2}) 月 (\d{1,2}) 日$');
final _weekday = RegExp(r'星期([一二三四五六日])');
final _lunar = RegExp(r'^農曆(閏)?(.+?)月(.+)$');

const _periods = {
  '凌晨': 'thàu-chá',
  '早上': 'chá-khí',
  '中午': 'tiong-tàu',
  '下午': 'ē-po͘',
  '晚上': 'àm-sî',
};

String _sayTime(String period, int hour, int minute) {
  final hours = switch (hour) {
    1 => 'chi̍t',
    2 => 'nn̄g',
    _ => taigiNumber(hour),
  };
  final minutes = switch (minute) {
    0 => 'chéng',
    1 => 'chi̍t hun',
    2 => 'nn̄g hun',
    _ => '${taigiNumber(minute)} hun',
  };
  return 'Hiān-chāi sī ${_periods[period]} $hours tiám $minutes';
}

String _sayDate(int month, int day, String? weekday) {
  final words =
      'Kin-á-ji̍t sī ${taigiNumber(month)}-goe̍h ${taigiNumber(day)} hō';
  final week = _weekdays[weekday];
  return week == null ? words : '$words $week';
}

const _weekdays = {
  '一': 'pài-it',
  '二': 'pài-jī',
  '三': 'pài-saⁿ',
  '四': 'pài-sì',
  '五': 'pài-gō͘',
  '六': 'pài-la̍k',
  '日': 'lé-pài',
};

/// 1..99 the way it is said in dates and times: 11 cha̍p-it, 25 jī-cha̍p-gō͘.
@visibleForTesting
String taigiNumber(int n) {
  if (n < 10) return _digits[n];
  final tens = n ~/ 10;
  final ones = n % 10;
  final head = tens == 1 ? 'cha̍p' : '${_digits[tens]}-cha̍p';
  return ones == 0 ? head : '$head-${_digits[ones]}';
}

const _digits = [
  'khòng', 'it', 'jī', 'saⁿ', 'sì', 'gō͘', 'la̍k', 'chhit', 'peh', 'káu', //
];

/// "十一" → "cha̍p-it"; "正" → "chiaⁿ" (the first month).
String? _lunarMonth(String words) => words == '正' ? 'chiaⁿ' : _hanNumber(words);

/// "初二" → "chhe-jī", "廿一" → "jia̍p-it", "十五" → "cha̍p-gō͘".
String? _lunarDay(String words) {
  if (words.startsWith('初')) {
    final n = _hanValue(words.substring(1));
    return n == null ? null : 'chhe-${taigiNumber(n)}';
  }
  if (words.startsWith('廿')) {
    final n = _hanValue(words.substring(1));
    return n == null ? null : 'jia̍p-${taigiNumber(n)}';
  }
  return _hanNumber(words);
}

String? _hanNumber(String words) {
  final n = _hanValue(words);
  return n == null ? null : taigiNumber(n);
}

/// "一".."九", "十", "十一".."十九", "二十", "三十" as a number.
int? _hanValue(String words) {
  const units = {
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, //
    '六': 6, '七': 7, '八': 8, '九': 9,
  };
  if (words.length == 1) return words == '十' ? 10 : units[words];
  if (words.length == 2 && words[0] == '十') {
    final ones = units[words[1]];
    return ones == null ? null : 10 + ones;
  }
  if (words.length == 2 && words[1] == '十') {
    final tens = units[words[0]];
    return tens == null ? null : tens * 10;
  }
  return null;
}
