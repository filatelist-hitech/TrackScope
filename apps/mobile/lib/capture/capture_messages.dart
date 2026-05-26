// Message envelopes exchanged between the main isolate and the DSP worker
// isolate. Kept deliberately simple so they round-trip through SendPort
// without custom codecs.
//
// The worker isolate owns the FFI handle and the engine poll loop. It
// never sees Flutter widgets, and the main isolate never sees raw PCM
// past the point where it ships bytes off via `sendPort.send`.

import 'dart:typed_data';

/// Sent main → worker once, immediately after spawn. Tells the worker
/// where to find the native library and the main isolate's reply port.
class WorkerInit {
  const WorkerInit({
    required this.replyPort,
    required this.libraryPath,
    required this.captureSampleRate,
    required this.pollIntervalMs,
  });

  /// Where the worker should send `DspResultMessage` snapshots and
  /// `WorkerError` events.
  final dynamic replyPort; // SendPort, but typed as dynamic to keep this file UI-free.
  final String? libraryPath;
  final int captureSampleRate;
  final int pollIntervalMs;
}

/// Main → worker: ingest a raw PCM byte chunk. Sample format is assumed
/// to match the capture config negotiated at start.
class PushPcm {
  const PushPcm(this.bytes, {required this.sampleRate, this.encoding = 'pcm16'});
  final Uint8List bytes;
  final int sampleRate;
  /// Either `pcm16` (little-endian signed 16-bit) or `pcm_f32le`.
  /// `record` 5.x emits `pcm16bits` by default on Android/iOS; we keep
  /// the field explicit so the worker rejects any surprise encoding.
  final String encoding;
}

/// Main → worker: drop rolling DSP state in place. Used on capture
/// restart or session reset.
class ResetEngine {
  const ResetEngine();
}

/// Main → worker: tear down. The worker frees the engine handle and
/// exits.
class StopWorker {
  const StopWorker();
}

/// Worker → main: a parsed `DspResult` snapshot. The JSON string is
/// forwarded raw so the typed view is constructed on the main isolate
/// where UI code lives.
class DspResultMessage {
  const DspResultMessage(this.json);
  final String json;
}

/// Worker → main: the worker is alive and ready to receive PCM.
class WorkerReady {
  const WorkerReady();
}

/// Worker → main: the worker hit an unrecoverable error (FFI load
/// failure, unsupported encoding, etc.). The capture loop must stop on
/// the main side too.
class WorkerError {
  const WorkerError(this.message, [this.stackTrace]);
  final String message;
  final StackTrace? stackTrace;
}
