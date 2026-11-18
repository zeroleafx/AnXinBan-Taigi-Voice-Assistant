import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'model_download.dart';
import 'speech_model.dart';
import 'taigi_voice.dart';

/// Meta MMS-TTS Min Nan (facebook/mms-tts-nan, CC-BY-NC-4.0), converted to
/// ONNX for sherpa-onnx. Pinned to one revision so the hashes stay valid.
const _revision = '4f49fc254f11ddb0e35fbf25b6e48b04463a6779';
const _source =
    'https://huggingface.co/willwade/mms-tts-multilingual-models-onnx/resolve/$_revision/nan';
const _files = [
  (
    name: 'model.onnx',
    bytes: 114024708,
    sha256: '2b0e5eba284bf54cb99c7ac5c117b9a35c1f177c535d118699a9f3421391f73a',
  ),
  (
    name: 'tokens.txt',
    bytes: 474,
    sha256: '552c7e173ff6deb99224ab59f19feb4292d8d64c7943fe5b0eb01401688b8366',
  ),
];

/// 1.0 is the model's own pace; below 1 is slower (0.85 was tried).
const _speed = 1.0;

/// Android only for now: iOS shares its audio session with the recorder's
/// Bluetooth routing, which has not been tried with a second player.
TaigiSynthesizer? createTaigiSynthesizer() =>
    Platform.isAndroid ? DeviceTaigiSynthesizer() : null;

VoicePlayer? createVoicePlayer() =>
    Platform.isAndroid ? DeviceVoicePlayer() : null;

/// Downloads the voice (114 MB) on Wi-Fi, or on mobile data once allowed,
/// then runs it on a background isolate so the screen does not stall while
/// a sentence is made.
class DeviceTaigiSynthesizer implements TaigiSynthesizer {
  _Worker? _worker;
  Future<VoiceSetup>? _preparing;
  bool _mobileDataAllowed = false;
  bool _disposed = false;
  String? _lastLog;

  @override
  int get downloadBytes => _files.fold(0, (sum, file) => sum + file.bytes);

  @override
  void allowMobileData() => _mobileDataAllowed = true;

  @override
  Future<VoiceSetup> prepare(
    ModelNetwork network, {
    void Function(int percent)? onPercent,
  }) async {
    // An earlier attempt may be downloading: let it finish first.
    final running = _preparing;
    if (running != null) await running;
    if (_worker != null) return VoiceSetup.ready;
    return _preparing ??= _prepare(
      network,
      onPercent ?? (_) {},
    ).whenComplete(() => _preparing = null);
  }

  Future<VoiceSetup> _prepare(
    ModelNetwork network,
    void Function(int percent) onPercent,
  ) async {
    if (_disposed) return VoiceSetup.waiting;
    try {
      final support = await getApplicationSupportDirectory();
      final folder = Directory('${support.path}/taigi_tts');
      await folder.create(recursive: true);
      for (final file in _files) {
        final path = '${folder.path}/${file.name}';
        final existing = File(path);
        if (await existing.exists() && await existing.length() == file.bytes) {
          continue;
        }
        if (network == ModelNetwork.none) {
          _log('voice not on the phone yet; no connection');
          return VoiceSetup.waiting;
        }
        if (network == ModelNetwork.metered && !_mobileDataAllowed) {
          _log('voice not on the phone yet; on mobile data, asking first');
          return VoiceSetup.askMobileData;
        }
        _log('downloading ${file.name} (${file.bytes} bytes)');
        onPercent(file.name == 'model.onnx' ? 0 : 100);
        await downloadModel(
          path,
          (percent) {
            if (percent % 10 == 0) _log('${file.name} $percent%');
            // The model is nearly all of it; the token list is tiny.
            onPercent(file.name == 'model.onnx' ? percent : 100);
          },
          source: Uri.parse('$_source/${file.name}'),
          expectedBytes: file.bytes,
          expectedSha256: file.sha256,
        );
        if (_disposed) return VoiceSetup.waiting;
      }
      _log('loading the voice');
      final worker = await _Worker.start(
        '${folder.path}/model.onnx',
        '${folder.path}/tokens.txt',
      );
      if (_disposed) {
        worker.dispose();
        return VoiceSetup.waiting;
      }
      _worker = worker;
      _log('ready');
      return VoiceSetup.ready;
    } catch (error) {
      // An interrupted download continues on the next call.
      _log('not ready: $error');
      return VoiceSetup.waiting;
    }
  }

  @override
  Future<Uint8List?> synthesize(String words) async {
    final worker = _worker;
    if (worker == null) {
      _log('not ready yet, so this card is not read aloud');
      return null;
    }
    return worker.synthesize(words);
  }

  /// Shown in the Android Studio Run/Debug tab; each message once in a row.
  void _log(String message) {
    if (message == _lastLog) return;
    _lastLog = message;
    debugPrint('TaigiVoice: $message');
  }

  @override
  void dispose() {
    _disposed = true;
    _worker?.dispose();
    _worker = null;
  }
}

class DeviceVoicePlayer implements VoicePlayer {
  final _player = AudioPlayer();

  @override
  Future<void> play(Uint8List wav) =>
      _player.play(BytesSource(wav, mimeType: 'audio/wav'));

  @override
  Future<void> stop() => _player.stop();

  @override
  void dispose() => unawaited(_player.dispose());
}

/// The voice on its own isolate. One sentence at a time.
class _Worker {
  _Worker(this._isolate, this._requests);

  final Isolate _isolate;
  final SendPort _requests;

  static Future<_Worker> start(String model, String tokens) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_serve, (
      ready.sendPort,
      model,
      tokens,
    ), errorsAreFatal: false);
    final reply = await ready.first.timeout(const Duration(seconds: 30));
    if (reply is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      throw StateError('Taiwanese voice did not start: $reply');
    }
    return _Worker(isolate, reply);
  }

  Future<Uint8List?> synthesize(String words) async {
    final reply = ReceivePort();
    _requests.send((words, reply.sendPort));
    try {
      final result = await reply.first.timeout(const Duration(seconds: 30));
      if (result is TransferableTypedData) {
        return result.materialize().asUint8List();
      }
      debugPrint('TaigiVoice: could not make "$words": $result');
      return null;
    } finally {
      reply.close();
    }
  }

  void dispose() => _isolate.kill(priority: Isolate.immediate);
}

void _serve((SendPort, String, String) setup) {
  final (ready, model, tokens) = setup;
  final sherpa.OfflineTts tts;
  try {
    sherpa.initBindings();
    tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(model: model, tokens: tokens),
          numThreads: 2,
        ),
      ),
    );
  } catch (error) {
    ready.send('$error');
    return;
  }
  final requests = ReceivePort();
  ready.send(requests.sendPort);
  requests.listen((message) {
    final (words, reply) = message as (String, SendPort);
    try {
      // The model's letters are lower case.
      final audio = tts.generate(text: words.toLowerCase(), speed: _speed);
      reply.send(
        audio.samples.isEmpty
            ? 'no audio came out'
            : TransferableTypedData.fromList([
                encodeWav(audio.samples, audio.sampleRate),
              ]),
      );
    } catch (error) {
      reply.send('$error');
    }
  });
}
