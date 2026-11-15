import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'speech_model.dart';
import 'model_download_stub.dart' if (dart.library.io) 'model_download.dart';

/// The native Breeze-ASR-26 recognizer and, on Android, its model download.
class BreezeChannel implements SpeechModelBackend {
  BreezeChannel() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static const _channel = MethodChannel('anxinban/breeze');

  /// Download progress reported by Android; null when nothing is downloading.
  final downloadPercent = ValueNotifier<int?>(null);

  Future<String> transcribe(String path) async =>
      (await _channel.invokeMethod<String>('transcribe', path))!;

  @override
  Future<ModelStatus?> status() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final path = (await _channel.invokeMethod<String>('modelPath'))!;
      return ModelStatus(
        ready: await modelExists(path),
        totalBytes: modelBytes,
        downloadedBytes: await partialModelBytes(path),
        network: _network((await _environment())['network']),
      );
    }
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final status = await _channel.invokeMapMethod<String, Object?>(
        'modelStatus',
      );
      if (status == null) return null;
      return ModelStatus(
        ready: status['ready'] == true,
        totalBytes: (status['totalBytes'] as num?)?.toInt() ?? 0,
        downloadedBytes: (status['downloadedBytes'] as num?)?.toInt() ?? 0,
        network: switch (status['network']) {
          'none' => ModelNetwork.none,
          'metered' => ModelNetwork.metered,
          _ => ModelNetwork.unmetered,
        },
      );
    } on MissingPluginException {
      // An Android build without "modelStatus" downloads the model during
      // the first transcription and reports progress through [downloadPercent].
      return null;
    }
  }

  @override
  Future<void> download(void Function(int percent) onPercent) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final path = (await _channel.invokeMethod<String>('modelPath'))!;
      final environment = await _environment();
      final partial = await partialModelBytes(path);
      final remaining = partial > modelBytes
          ? modelBytes
          : modelBytes - partial;
      final available = (environment['availableBytes'] as num?)?.toInt();
      if (available != null && available < remaining) {
        throw PlatformException(
          code: 'storage',
          message: '手機空間不夠，還需要 ${(remaining / 1e9).toStringAsFixed(1)} GB。',
        );
      }
      if (remaining > 0 &&
          _network(environment['network']) == ModelNetwork.none) {
        throw PlatformException(code: 'network', message: '連不上網路，請確認網路後再試一次。');
      }
      return downloadModel(path, onPercent);
    }
    void forward() {
      final percent = downloadPercent.value;
      if (percent != null) onPercent(percent);
    }

    downloadPercent.addListener(forward);
    try {
      await _channel.invokeMethod<void>('downloadModel');
    } finally {
      downloadPercent.removeListener(forward);
    }
  }

  Future<Map<String, Object?>> _environment() async =>
      await _channel.invokeMapMethod<String, Object?>('downloadEnvironment') ??
      {};

  ModelNetwork _network(Object? value) => switch (value) {
    'none' => ModelNetwork.none,
    'metered' => ModelNetwork.metered,
    _ => ModelNetwork.unmetered,
  };

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'downloadProgress') {
      downloadPercent.value = call.arguments as int?;
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    downloadPercent.dispose();
  }
}
