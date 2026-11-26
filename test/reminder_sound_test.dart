import 'package:an_xin_ban/reminder_sound.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('speaks the title using Taiwanese reminder phrases', () async {
    expect(await reminderPronunciation('吃藥，喝水'), 'chia̍h-io̍h lim-chúi');
    expect(await reminderPronunciation('運動'), isNotEmpty);
    expect(await reminderPronunciation('🎵'), isNull);
  });
}
