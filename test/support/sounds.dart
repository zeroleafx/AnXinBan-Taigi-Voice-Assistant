import 'dart:io';

import 'package:an_xin_ban/sound_table.dart';

/// The table the app ships with, read from the source tree.
final shippedSounds = SoundTable.parse(
  File('assets/fuzzy/char_readings.txt').readAsStringSync(),
);
