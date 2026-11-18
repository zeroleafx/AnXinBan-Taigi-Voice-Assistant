import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:an_xin_ban/speech_model.dart';
import 'package:an_xin_ban/taigi_voice.dart';

/// A voice whose "audio" is the words themselves.
class FakeSynthesizer implements TaigiSynthesizer {
  final asked = <String>[];
  final prepared = <ModelNetwork>[];

  /// Whether the voice is already on the phone.
  bool installed = true;
  bool mobileDataAllowed = false;

  /// When set, each sentence waits for the test to finish it.
  final pending = <String, Completer<Uint8List?>>{};
  bool hold = false;
  bool disposed = false;

  @override
  int get downloadBytes => 114024708 + 474;

  @override
  void allowMobileData() => mobileDataAllowed = true;

  /// When set, a download reports [downloadReaches] percent and waits for the
  /// test to complete it.
  Completer<void>? downloadGate;
  int downloadReaches = 42;

  @override
  Future<VoiceSetup> prepare(
    ModelNetwork network, {
    void Function(int percent)? onPercent,
  }) async {
    prepared.add(network);
    if (installed) return VoiceSetup.ready;
    switch (network) {
      case ModelNetwork.none:
        return VoiceSetup.waiting;
      case ModelNetwork.metered when !mobileDataAllowed:
        return VoiceSetup.askMobileData;
      default:
        final gate = downloadGate;
        if (gate != null) {
          onPercent?.call(downloadReaches);
          await gate.future;
        }
        installed = true;
        return VoiceSetup.ready;
    }
  }

  @override
  Future<Uint8List?> synthesize(String words) {
    asked.add(words);
    if (!hold) return Future.value(Uint8List.fromList(utf8.encode(words)));
    return (pending[words] = Completer<Uint8List?>()).future;
  }

  void finish(String words) =>
      pending[words]!.complete(Uint8List.fromList(utf8.encode(words)));

  @override
  void dispose() => disposed = true;
}

class FakePlayer implements VoicePlayer {
  final events = <String>[];

  List<String> get played => [
    for (final e in events)
      if (e.startsWith('play:')) e.substring(5),
  ];

  @override
  Future<void> play(Uint8List wav) async =>
      events.add('play:${utf8.decode(wav)}');

  @override
  Future<void> stop() async => events.add('stop');

  @override
  void dispose() => events.add('dispose');
}
