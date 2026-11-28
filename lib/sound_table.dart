/// Fuzzy matching by sound.
///
/// Breeze writes what it hears in whichever characters fit, so the name of
/// 阿明 may arrive as "阿銘", and 手電筒 as "手電桶". This file tells
/// whether two words sound alike, from a table of how each Han character is
/// read.
///
/// People speak Taiwanese to the app, with names and brands often said in
/// Mandarin, so two characters are alike when either language reads them
/// alike. Tones are left out: they change inside a Taiwanese phrase and
/// differ between the two languages, so a character written wrong need not
/// keep its tone.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What it costs, in tenths, to take one character for another: nothing for
/// the same character, a little for the same sound (明 and 銘), more for
/// sounds that are easily mistaken (電 tiān and 店 tiàm, 新 xin and 星 xing).
/// Other characters are never taken for each other.
const _sameSound = 1;
const _closeSound = 4;

/// The most a whole word may cost: several characters with the same sound,
/// but only one whose sound is merely close.
const _mostCost = 5;

class SoundTable {
  /// Reads the lines of `assets/fuzzy/char_readings.txt`: T (Taiwanese) or M
  /// (Mandarin), a syllable without its tone, and every character read so.
  SoundTable.parse(String lines) {
    final readings = <int, List<String>>{};
    final loose = <String, String>{};
    for (final line in lines.split('\n')) {
      final parts = line.trim().split(' ');
      if (parts.length != 3 || !const {'T', 'M'}.contains(parts[0])) continue;
      final [language, syllable, characters] = parts;
      final reading = '$language$syllable';
      loose[reading] = language == 'T'
          ? 'T${looseTaigi(syllable)}'
          : 'M${looseMandarin(syllable)}';
      for (final rune in characters.runes) {
        (readings[rune] ??= []).add(reading);
      }
    }
    // Most characters have one reading and share it with many others, so
    // characters that are read the same share one record.
    final shared = <String, ({List<String> same, List<String> close})>{};
    readings.forEach((rune, same) {
      _sounds[rune] = shared[same.join(' ')] ??= (
        same: same,
        close: {for (final reading in same) loose[reading]!}.toList(),
      );
    });
  }

  static Future<SoundTable?>? _shipped;

  /// The table that comes with the app. Null when it cannot be read; names
  /// are then matched by their characters only, as before.
  static Future<SoundTable?> load() => _shipped ??= _read();

  static Future<SoundTable?> _read() async {
    try {
      return SoundTable.parse(
        await rootBundle.loadString('assets/fuzzy/char_readings.txt'),
      );
    } catch (_) {
      return null;
    }
  }

  /// Each character's readings, and the same readings with easily mistaken
  /// sounds folded together.
  final _sounds = <int, ({List<String> same, List<String> close})>{};

  /// What it costs to take [heard] for [word], or null when they do not
  /// sound alike. 0 means they are written the same.
  ///
  /// They are compared character by character, so they must be equally
  /// long. An everyday word may differ in one character, or in up to half
  /// of them from four characters on: 手電桶 is 手電筒, 首店桶 is not. Set
  /// [name] for the name of a person, whose characters Breeze can only
  /// guess: 智銘 may be 志明.
  int? alike(String heard, String word, {bool name = false}) {
    final a = heard.runes.toList();
    final b = word.runes.toList();
    return a.length == b.length ? _alike(a, 0, b, name) : null;
  }

  /// The least [alike] cost between [part] and any stretch of [whole] that
  /// is as long, or null: "美齡" is within 陳美玲.
  int? within(String part, String whole, {bool name = false}) {
    final a = whole.runes.toList();
    final b = part.runes.toList();
    int? least;
    for (var start = 0; start + b.length <= a.length; start++) {
      final cost = _alike(a, start, b, name);
      if (cost != null && (least == null || cost < least)) least = cost;
    }
    return least;
  }

  /// Compares [b] with as many characters of [a] from [start] on.
  int? _alike(List<int> a, int start, List<int> b, bool name) {
    if (b.isEmpty) return null;
    final mayDiffer = name ? b.length : max(1, b.length ~/ 2);
    // One character alone is too little to go on for a sound that is only
    // close.
    final farthest = b.length == 1 ? _sameSound : _closeSound;
    var differ = 0;
    var cost = 0;
    for (var i = 0; i < b.length; i++) {
      if (a[start + i] == b[i]) continue;
      final step = _between(a[start + i], b[i]);
      if (step == null || step > farthest) return null;
      cost += step;
      if (++differ > mayDiffer || cost > _mostCost) return null;
    }
    return cost;
  }

  /// Null when the two characters share no sound, or either has none on
  /// record, such as a Latin letter.
  int? _between(int a, int b) {
    final one = _sounds[a];
    final other = _sounds[b];
    if (one == null || other == null) return null;
    if (one.same.any(other.same.contains)) return _sameSound;
    if (one.close.any(other.close.contains)) return _closeSound;
    return null;
  }
}

/// Folds together the Taiwanese sounds that are easily mistaken: with and
/// without a puff of air (p and ph), the voiced and nasal pairs (b and m, l
/// and n, g and ng), j said as l, nasal vowels, the glottal stop, and the
/// endings -m, -n, -ng and -p, -t, -k.
///
/// In the table N marks a nasal vowel (ⁿ) and O the open o (o͘).
@visibleForTesting
String looseTaigi(String syllable) {
  var initial = '';
  // "ng" and "m" are whole syllables too, also as "ngh" and "mh".
  if (!const {'ng', 'ngh', 'm', 'mh'}.contains(syllable)) {
    for (final candidate in _taigiInitials) {
      if (syllable.length > candidate.length &&
          syllable.startsWith(candidate)) {
        initial = candidate;
        break;
      }
    }
  }
  var rime = syllable
      .substring(initial.length)
      .replaceAll('N', '')
      .replaceAll('O', 'o');
  String cut(int letters) => rime.substring(0, rime.length - letters);
  if (rime.length > 1 && rime.endsWith('h')) rime = cut(1);
  if (rime != 'ng' && rime != 'm') {
    if (rime.endsWith('ng')) {
      rime = '${cut(2)}n';
    } else if (rime.endsWith('m')) {
      rime = '${cut(1)}n';
    } else if (rime.endsWith('p') || rime.endsWith('k')) {
      rime = '${cut(1)}t';
    }
  }
  return '${_looseTaigiInitials[initial] ?? initial}$rime';
}

/// Longest first, so "chh" is not read as "ch".
const _taigiInitials = [
  'chh', 'ch', 'kh', 'ph', 'th', 'ng', //
  'p', 'b', 'm', 't', 'n', 'l', 'k', 'g', 'h', 's', 'j',
];
const _looseTaigiInitials = {
  'ph': 'p', 'th': 't', 'kh': 'k', 'chh': 'ch', //
  'm': 'b', 'n': 'l', 'ng': 'g', 'j': 'l',
};

/// Folds together the Mandarin sounds that run together in Taiwan: zh and
/// z, ch and c, sh and s; n, r and l; -ng and -n after a, e and i; and ü
/// said as i (written v in the table, or u after j, q, x and y).
@visibleForTesting
String looseMandarin(String syllable) {
  var text = syllable;
  if (text.length > 2 && text[1] == 'h' && 'zcs'.contains(text[0])) {
    text = text[0] + text.substring(2);
  } else if (text.length > 1 && 'nr'.contains(text[0]) && text != 'ng') {
    text = 'l${text.substring(1)}';
  }
  text = text.replaceAll('v', 'i');
  if (text.length > 1 && text[1] == 'u') {
    final rest = text.substring(2);
    if ('jqx'.contains(text[0])) {
      text = '${text[0]}i$rest';
    } else if (text[0] == 'y') {
      // yu, yue, yuan, yun: yi, ye, yan, yin.
      text = rest.isEmpty || rest == 'n' ? 'yi$rest' : 'y$rest';
    }
  }
  if (text.endsWith('ang') || text.endsWith('eng') || text.endsWith('ing')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}
