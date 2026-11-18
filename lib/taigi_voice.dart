import 'dart:async';

import 'package:flutter/foundation.dart';

import 'assistant_controller.dart';
import 'speech_model.dart';
import 'taigi_phrases.dart';

/// Where [TaigiSynthesizer.prepare] got to.
enum VoiceSetup {
  /// The voice is loaded and speaks.
  ready,

  /// The voice files are missing and need download consent.
  needsDownload,

  /// Not ready yet: no connection, or the download stopped and continues on
  /// the next call.
  waiting,
}

/// Turns POJ text into speech audio.
abstract interface class TaigiSynthesizer {
  /// Loads the local voice, downloading missing files only with consent.
  /// [onPercent] gets 0..100 while downloading; 100 while the download is
  /// checked and the voice loaded. Safe to call again; it never throws.
  Future<VoiceSetup> prepare(
    ModelNetwork network, {
    bool allowDownload = false,
    void Function(int percent)? onPercent,
  });

  /// The size of the download, for the question.
  int get downloadBytes;

  /// WAV bytes for [words], or null while the voice is not ready.
  Future<Uint8List?> synthesize(String words);

  void dispose();
}

abstract interface class VoicePlayer {
  Future<void> play(Uint8List wav);
  Future<void> stop();
  void dispose();
}

/// Reads each new assistant card aloud in Taiwanese, and tracks getting the
/// voice onto the phone so the screen can show it.
///
/// Until the voice is on the phone, cards are shown without being read.
class TaigiVoice extends ChangeNotifier {
  TaigiVoice(this.assistant, this.synthesizer, this.player) {
    _shown = assistant.outcome;
    assistant.addListener(_changed);
  }

  final AssistantController assistant;
  final TaigiSynthesizer synthesizer;
  final VoicePlayer player;

  bool _enabled = false;
  bool get enabled => _enabled;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) stop();
    notifyListeners();
  }

  /// 0..100 while the voice downloads; null otherwise. 100 means the file is
  /// being checked and the voice loaded.
  int? downloadPercent;

  AssistantOutcome? _shown;

  /// Counts cards, so audio for a card that is already gone is not played.
  int _turn = 0;
  final _recent = <String, Uint8List>{};
  bool _disposed = false;

  /// See [TaigiSynthesizer.prepare].
  Future<VoiceSetup> prepare(
    ModelNetwork network, {
    bool allowDownload = false,
  }) async {
    final result = await synthesizer.prepare(
      network,
      allowDownload: allowDownload,
      onPercent: _progress,
    );
    if (_disposed) return result;
    downloadPercent = null;
    notifyListeners();
    return result;
  }

  void _progress(int percent) {
    if (_disposed || percent == downloadPercent) return;
    downloadPercent = percent;
    notifyListeners();
  }

  /// For example "114 MB".
  String get downloadSize => '${(synthesizer.downloadBytes / 1e6).round()} MB';

  /// Says [words] now, in place of whatever is being said.
  void say(String words) {
    if (_enabled) unawaited(_say(words, ++_turn));
  }

  /// Stops talking, for example before recording starts.
  void stop() => unawaited(_say(null, ++_turn));

  void _changed() {
    final outcome = assistant.outcome;
    if (identical(outcome, _shown)) return;
    _shown = outcome;
    if (!_enabled) return;
    final words = outcome == null ? null : taigiSpeech(outcome);
    if (outcome != null && words == null) {
      debugPrint('TaigiVoice: no Taiwanese for "${outcome.title}"');
    }
    unawaited(_say(words, ++_turn));
  }

  /// Stops what is playing, then says [words] unless a newer card came.
  Future<void> _say(String? words, int turn) async {
    try {
      await player.stop();
      if (words == null || _disposed || turn != _turn) return;
      final wav = _recent[words] ?? await synthesizer.synthesize(words);
      if (wav == null || _disposed || turn != _turn) return;
      _remember(words, wav);
      debugPrint('TaigiVoice: saying "$words"');
      await player.play(wav);
    } catch (error) {
      // The card on screen still says it.
      debugPrint('TaigiVoice: could not say "$words": $error');
    }
  }

  Future<void> _quiet() async {
    try {
      await player.stop();
    } catch (_) {}
  }

  /// Keeps the last few sentences, so a repeated one plays at once.
  void _remember(String words, Uint8List wav) {
    _recent.remove(words);
    _recent[words] = wav;
    if (_recent.length > 24) _recent.remove(_recent.keys.first);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    assistant.removeListener(_changed);
    unawaited(_quiet());
    player.dispose();
    synthesizer.dispose();
    super.dispose();
  }
}

/// 16-bit mono WAV. The model speaks softly, so the loudest sample is raised
/// to [peak], at most [maxGain] times louder.
Uint8List encodeWav(
  Float32List samples,
  int sampleRate, {
  double peak = 0.9,
  double maxGain = 4,
}) {
  var loudest = 0.0;
  for (final s in samples) {
    final level = s.abs();
    if (level > loudest) loudest = level;
  }
  final gain = loudest == 0 ? 1.0 : (peak / loudest).clamp(0.0, maxGain);
  final dataBytes = samples.length * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // size of the format chunk
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little); // bytes per second
  bytes.setUint16(32, 2, Endian.little); // bytes per frame
  bytes.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final value = (samples[i] * gain).clamp(-1.0, 1.0);
    bytes.setInt16(44 + i * 2, (value * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}
