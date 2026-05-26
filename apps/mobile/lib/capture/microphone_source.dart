// Production audio source: opens `package:record` and exposes a raw
// PCM byte stream the `CaptureBridge` forwards into the DSP worker.
//
// Format reconciliation (see docs/MOBILE_AUDIO.md):
//   - Android: `record` uses AudioRecord, emits PCM 16-bit signed
//     little-endian mono at the requested sample rate (48 kHz here).
//   - iOS: `record` uses AVAudioEngine with the same wire format.
//   - The DSP expects mono f32 in [-1, 1]; the bridge worker converts
//     PCM16 → f32 via `s / 32768.0` per sample. No resampling needed
//     because we ask the platform for the DSP's preferred 48 kHz.
//
// This file does not import any UI or DSP code — it is a thin wrapper
// around the recorder package so the bridge can stay UI-free.

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

class MicrophoneSource {
  MicrophoneSource({this.sampleRate = 48000});

  final int sampleRate;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  StreamController<Uint8List>? _ctrl;

  /// True wire encoding the worker should expect. Kept here so the
  /// bridge negotiates encoding instead of hardcoding it.
  static const String encoding = 'pcm16';

  /// Start capture. Caller is responsible for having checked the
  /// microphone permission first — this method does NOT request it,
  /// because permission UI belongs in the widget layer.
  Future<Stream<Uint8List>> start() async {
    if (_ctrl != null) {
      throw StateError('MicrophoneSource already started');
    }
    final ctrl = StreamController<Uint8List>(
      onCancel: () async => stop(),
    );
    _ctrl = ctrl;
    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
    );
    final raw = await _recorder.startStream(config);
    _sub = raw.listen(
      ctrl.add,
      onError: ctrl.addError,
      onDone: ctrl.close,
    );
    return ctrl.stream;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {
      // Recorder may already be torn down; nothing else to do.
    }
    await _ctrl?.close();
    _ctrl = null;
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
