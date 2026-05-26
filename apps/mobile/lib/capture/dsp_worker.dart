// Background isolate entry point.
//
// Owns the `DspEngine` FFI handle and the PCM → f32 conversion that
// must NOT run on the UI thread. Receives raw PCM byte chunks from the
// main isolate, converts them to `Float32List` mono, pushes into the
// engine, polls rolling `DspResult` JSON snapshots, and ships them
// back to the main isolate which decodes them into typed objects for
// UI consumption.
//
// This file imports `dsp/engine.dart` directly because Dart isolates
// can each open the same shared library — `DspEngine.open` is safe to
// call once per isolate.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../dsp/engine.dart';
import 'capture_messages.dart';

/// Entry point passed to `Isolate.spawn`. The init message carries the
/// main isolate's reply port and library configuration.
void dspWorkerEntry(WorkerInit init) {
  final ReceivePort inbox = ReceivePort();
  final SendPort reply = init.replyPort as SendPort;
  reply.send(inbox.sendPort);

  late final DspEngine engine;
  try {
    engine = DspEngine.open(
      libraryPath: init.libraryPath,
      // The worker polls FFI itself, so the engine's own stream timer
      // is disabled by giving it a long interval — we never subscribe.
      pollInterval: const Duration(hours: 1),
    );
  } catch (e, st) {
    reply.send(WorkerError('failed to open native DSP: $e', st));
    inbox.close();
    return;
  }

  // The worker drives its own poll cadence and forwards raw JSON. This
  // avoids parsing on the worker and re-encoding for the wire: parsing
  // happens once, on the main isolate, when the UI consumes it.
  Timer? poll;
  void startPolling() {
    poll ??= Timer.periodic(Duration(milliseconds: init.pollIntervalMs),
        (_) {
      try {
        reply.send(DspResultMessage(engine.analyzeJson()));
      } catch (e, st) {
        reply.send(WorkerError('analyze failed: $e', st));
      }
    });
  }

  reply.send(const WorkerReady());
  startPolling();

  inbox.listen((message) async {
    if (message is PushPcm) {
      try {
        final samples = _decodeMono(message);
        if (samples.isNotEmpty) {
          engine.pushSamples(samples, message.sampleRate);
        }
      } catch (e, st) {
        reply.send(WorkerError('push failed: $e', st));
      }
    } else if (message is ResetEngine) {
      try {
        engine.reset();
      } catch (e, st) {
        reply.send(WorkerError('reset failed: $e', st));
      }
    } else if (message is StopWorker) {
      poll?.cancel();
      poll = null;
      await engine.dispose();
      inbox.close();
    }
  });
}

/// Decode an incoming raw PCM chunk into mono `Float32List` ready for
/// `DspEngine.pushSamples`. The `record` plugin's `pcm16bits` encoding
/// is signed little-endian 16-bit interleaved samples; mono capture
/// keeps interleaving moot. Future encodings can be added here without
/// touching the DSP.
Float32List _decodeMono(PushPcm chunk) {
  switch (chunk.encoding) {
    case 'pcm16':
    case 'pcm16bits':
      return _decodePcm16Mono(chunk.bytes);
    case 'pcm_f32le':
      return _decodeF32(chunk.bytes);
    default:
      throw ArgumentError('unsupported PCM encoding: ${chunk.encoding}');
  }
}

Float32List _decodePcm16Mono(Uint8List bytes) {
  // Floor to whole sample pairs in case the platform delivered an odd
  // tail (unlikely for pcm16 but cheap to guard).
  final sampleCount = bytes.length ~/ 2;
  final out = Float32List(sampleCount);
  final view = ByteData.sublistView(bytes, 0, sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    final s = view.getInt16(i * 2, Endian.little);
    out[i] = s / 32768.0;
  }
  return out;
}

Float32List _decodeF32(Uint8List bytes) {
  final sampleCount = bytes.length ~/ 4;
  final out = Float32List(sampleCount);
  final view = ByteData.sublistView(bytes, 0, sampleCount * 4);
  for (var i = 0; i < sampleCount; i++) {
    out[i] = view.getFloat32(i * 4, Endian.little);
  }
  return out;
}
