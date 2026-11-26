import 'dart:convert';

import 'package:flutter/services.dart';

final _readings = rootBundle
    .loadString('assets/taigi/reminder_readings.json')
    .then((data) => Map<String, String>.from(jsonDecode(data) as Map));

// Everyday Mandarin reminder terms with an idiomatic Taiwanese reading.
const _phrases = {
  '吃藥': 'chia̍h-io̍h',
  '吃飯': 'chia̍h-pn̄g',
  '喝水': 'lim-chúi',
  '看醫生': 'khòaⁿ i-seng',
  '回診': 'tńg-khì khòaⁿ i-seng',
  '量血壓': 'niû huih-ap',
  '吃': 'chia̍h',
  '喝': 'lim',
};

Future<String?> reminderPronunciation(String title) async {
  final readings = await _readings;
  final words = <String>[];
  final text = title.trim();
  for (var i = 0; i < text.length;) {
    if (RegExp(r'[\s，。！？、,.!?：:（）()]').hasMatch(text[i])) {
      i++;
      continue;
    }
    String? reading;
    for (var end = text.length; end > i; end--) {
      final word = text.substring(i, end);
      reading = _phrases[word] ?? readings[word];
      if (reading != null) {
        i = end;
        break;
      }
    }
    if (reading == null) return null;
    words.add(reading);
  }
  return words.isEmpty ? null : words.join(' ');
}
