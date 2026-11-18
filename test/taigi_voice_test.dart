import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/assistant_controller.dart';
import 'package:an_xin_ban/speech_model.dart';
import 'package:an_xin_ban/taigi_voice.dart';

import 'support/fake_phone.dart';
import 'support/fake_voice.dart';

void main() {
  late AssistantController assistant;
  late FakeSynthesizer synthesizer;
  late FakePlayer player;
  late TaigiVoice voice;

  const torchOn = 'Chhiú-tiān-tâng í-keng phah-khui ah';
  const torchOff = 'Chhiú-tiān-tâng í-keng khìm-tiāu ah';

  setUp(() {
    assistant = AssistantController(FakePhone());
    synthesizer = FakeSynthesizer();
    player = FakePlayer();
    voice = TaigiVoice(assistant, synthesizer, player);
  });
  tearDown(() {
    voice.dispose();
    assistant.dispose();
  });

  test('reads each new card once', () async {
    await assistant.handle('開手電筒');
    await pumpEventQueue();
    expect(player.played, [torchOn]);

    // Other changes on the controller do not repeat it.
    await assistant.initialize();
    await pumpEventQueue();
    expect(player.played, [torchOn]);
  });

  test('stops talking when the card is cleared', () async {
    await assistant.handle('開手電筒');
    await pumpEventQueue();
    assistant.clear();
    await pumpEventQueue();
    expect(player.events.last, 'stop');
    expect(player.played, [torchOn]);
  });

  test('a card that is already gone is not read', () async {
    synthesizer.hold = true;
    await assistant.handle('開手電筒');
    await pumpEventQueue();
    await assistant.handle('手電筒關掉');
    await pumpEventQueue();
    synthesizer
      ..finish(torchOn)
      ..finish(torchOff);
    await pumpEventQueue();
    expect(player.played, [torchOff]);
  });

  test('a sentence said again is not made again', () async {
    for (final heard in ['開手電筒', '手電筒關掉', '開手電筒']) {
      await assistant.handle(heard);
      await pumpEventQueue(); // each card is read before the next one
    }
    expect(player.played, [torchOn, torchOff, torchOn]);
    expect(synthesizer.asked, [torchOn, torchOff]);
  });

  test('say speaks any sentence; stop cuts it off', () async {
    voice.say('Í-keng lio̍k hó ah');
    await pumpEventQueue();
    expect(player.played, ['Í-keng lio̍k hó ah']);

    synthesizer.hold = true;
    voice.say(torchOn);
    await pumpEventQueue();
    voice.stop();
    synthesizer.finish(torchOn);
    await pumpEventQueue();
    expect(player.played, ['Í-keng lio̍k hó ah']);
    expect(player.events.last, 'stop');
  });

  test('prepare passes the network on and reports where it got to', () async {
    synthesizer.installed = false;
    expect(await voice.prepare(ModelNetwork.none), VoiceSetup.waiting);
    expect(await voice.prepare(ModelNetwork.metered), VoiceSetup.askMobileData);
    voice.allowMobileData();
    expect(await voice.prepare(ModelNetwork.metered), VoiceSetup.ready);
    expect(synthesizer.prepared, [
      ModelNetwork.none,
      ModelNetwork.metered,
      ModelNetwork.metered,
    ]);
    expect(voice.downloadSize, '114 MB');
  });

  test('dispose releases the player and the voice', () {
    voice.dispose();
    expect(player.events, contains('dispose'));
    expect(synthesizer.disposed, isTrue);
    // tearDown disposes again; that must be harmless.
  });

  group('encodeWav', () {
    test('writes a 16-bit mono header', () {
      final wav = encodeWav(Float32List.fromList([0, 0.25, -0.25]), 16000);
      final data = ByteData.sublistView(wav);
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 16)), 'WAVEfmt ');
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint32(24, Endian.little), 16000);
      expect(data.getUint16(34, Endian.little), 16);
      expect(data.getUint32(40, Endian.little), 6);
      expect(wav.length, 44 + 6);
    });

    test('raises soft speech to the peak, within the gain limit', () {
      final loud = ByteData.sublistView(
        encodeWav(Float32List.fromList([0.3, -0.3]), 16000),
      );
      expect(loud.getInt16(44, Endian.little), (0.9 * 32767).round());

      final quiet = ByteData.sublistView(
        encodeWav(Float32List.fromList([0.01]), 16000),
      );
      expect(quiet.getInt16(44, Endian.little), (0.04 * 32767).round());

      final silent = encodeWav(Float32List.fromList([0, 0]), 16000);
      expect(silent.length, 48);
    });
  });
}
