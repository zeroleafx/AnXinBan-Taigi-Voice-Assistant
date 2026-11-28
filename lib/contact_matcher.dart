import 'dart:math';

import 'sound_table.dart';
import 'voice_command.dart';

class ContactEntry {
  const ContactEntry({
    required this.name,
    required this.numbers,
    this.nickname,
    this.aliases = const [],
  });

  final String name;
  final String? nickname;
  final List<String> aliases;
  final List<String> numbers;

  String get number => numbers.first;
}

/// Contacts that best match a spoken name, best first.
///
/// More than one result means the names tie and the person should pick.
///
/// With [sounds], a name also fits when it only sounds like what was said,
/// because Breeze may write it in other characters: "阿銘" finds 阿明. Such
/// a contact is a guess. Ask before acting on it; [matchContacts] without
/// [sounds] tells whether the name fits as written.
List<ContactEntry> matchContacts(
  String spoken,
  Iterable<ContactEntry> contacts, {
  int limit = 5,
  SoundTable? sounds,
}) {
  final query = normalizeTranscript(spoken);
  if (query.isEmpty) return const [];
  final asked = {
    query: 0,
    for (final word in _sameAs[query] ?? const []) word: _otherWord,
  };
  // A family word heard a little wrong still stands for the others: "阿木"
  // is 阿母, who may be saved as 媽媽.
  final guessed = <String, int>{};
  if (sounds != null) {
    for (final MapEntry(key: word, value: others) in _sameAs.entries) {
      final cost = sounds.alike(query, word);
      if (cost == null) continue;
      for (final other in [word, ...others]) {
        if (asked.containsKey(other)) continue;
        guessed.putIfAbsent(other, () => other == word ? cost : _otherWord);
      }
    }
  }
  // Each contact's best score, and its best score as written.
  final scored = <(int, int, ContactEntry)>[];
  for (final contact in contacts) {
    if (contact.numbers.isEmpty) continue;
    var best = 0;
    var written = 0;
    for (final label in [contact.name, ?contact.nickname, ...contact.aliases]) {
      final name = normalizeTranscript(label);
      if (name.isEmpty) continue;
      for (final MapEntry(key: word, value: penalty) in asked.entries) {
        var score = _score(word, name);
        if (score > 0) written = max(written, score - penalty);
        if (score == 0 && sounds != null) {
          score = _soundScore(word, name, sounds);
        }
        if (score > 0) best = max(best, score - penalty);
      }
      if (sounds == null) continue;
      for (final MapEntry(key: word, value: penalty) in guessed.entries) {
        var score = _score(word, name);
        if (score == 0) score = _soundScore(word, name, sounds);
        if (score > 0) best = max(best, score - penalty);
      }
    }
    if (best > 0) scored.add((best, written, contact));
  }
  if (scored.isEmpty) return const [];
  final top = scored.map((entry) => entry.$1).reduce(max);
  final topWritten = scored.map((entry) => entry.$2).reduce(max);
  final winners = [
    for (final entry in scored)
      // Names that fit as written tie or do not. Names that fit by sound
      // also tie when their sounds are nearly as close, and they never push
      // out the names that fit best as written.
      if (top - entry.$1 < _nearly || entry.$2 > 0 && entry.$2 == topWritten)
        entry,
  ];
  winners.sort((a, b) {
    final better = b.$1.compareTo(a.$1);
    return better != 0 ? better : a.$3.name.length.compareTo(b.$3.name.length);
  });
  return [for (final (_, _, contact) in winners.take(limit)) contact];
}

/// Taken off the score of another word for the person who was named.
const _otherWord = 1000;

/// Scores this close together are a tie.
const _nearly = 100;

int _score(String query, String name) {
  if (name == query) return 10000;
  if (name.contains(query) || (name.length >= 2 && query.contains(name))) {
    return 8000;
  }
  final core = _core(query);
  if (core != query && (name.contains(core) || _core(name) == core)) {
    return 6000;
  }
  return 0;
}

/// The same three kinds of fit as [_score], by sound. Each scores under its
/// written kind, and the whole name by sound ("美齡" for 美玲) nearly as
/// much as part of a name as written (陳美齡). Up to 250 comes off for how
/// far the sounds are apart.
int _soundScore(String query, String name, SoundTable sounds) {
  int apart(int cost, String word) => cost * 100 ~/ word.length;
  final whole = sounds.alike(query, name, name: true);
  if (whole != null) return 8000 - apart(whole, query);
  // "美齡" for 陳美玲, or "美齡阿姨" for 美玲.
  final (part, of) = query.length < name.length ? (query, name) : (name, query);
  if (part.length >= 2) {
    final cost = sounds.within(part, of, name: true);
    if (cost != null) return 7000 - apart(cost, part);
  }
  // "銘哥" for 阿明.
  final core = _core(query);
  if (core == query) return 0;
  final cost =
      sounds.within(core, name, name: true) ??
      sounds.alike(core, _core(name), name: true);
  return cost == null ? 0 : 5000 - apart(cost, core);
}

/// "阿明" and "明哥" both come down to "明".
String _core(String name) {
  var core = name;
  for (final prefix in const ['阿', '小', '老']) {
    if (core.length > prefix.length && core.startsWith(prefix)) {
      core = core.substring(prefix.length);
      break;
    }
  }
  for (final suffix in _titles) {
    if (core.length > suffix.length && core.endsWith(suffix)) {
      return core.substring(0, core.length - suffix.length);
    }
  }
  return core;
}

const _titles = [
  '先生', '小姐', '太太', '女士', '老師', '醫生', '哥哥', '姊姊', '姐姐', //
  '阿姨', '伯伯', '叔叔', '哥', '姊', '姐', '仔', '伯', '叔', '姨', '嬸',
];

/// Family words Breeze may write differently from how they are saved.
const _sameAs = {
  '阿母': ['媽媽', '老媽', '母親', '媽'],
  '媽媽': ['阿母', '老媽', '母親', '媽'],
  '阿爸': ['爸爸', '老爸', '父親', '爸'],
  '爸爸': ['阿爸', '老爸', '父親', '爸'],
  '後生': ['兒子'],
  '兒子': ['後生'],
  '查某囝': ['女兒'],
  '女兒': ['查某囝'],
  '阿公': ['爺爺', '外公'],
  '阿嬤': ['奶奶', '外婆'],
  '牽手': ['老婆', '太太', '老公', '先生'],
};
