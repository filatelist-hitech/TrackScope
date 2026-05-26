// Main-isolate orchestrator. Spawns the DSP worker isolate, forwards
// raw PCM byte chunks from a caller-supplied audio source into the
// worker via SendPort, and re-emits parsed `DspResult` snapshots on a
// broadcast stream the UI subscribes to.
//
// This class never inspects audio bytes. It never derives BPM. All
// detection runs in the worker; UI sees only typed `DspResult`.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../dsp/dsp_result.dart';
import '../dsp/engine.dart' show defaultLibraryName;
import 'capture_messages.dart';
import 'dsp_worker.dart';

/// Surfaced to the UI when the capture path or the DSP worker hits an
/// unrecoverable error. UI must render this — never swallow it and
/// never substitute synthetic audio.
class CaptureError {
  const CaptureError(this.message, [this.stackTrace]);
  final String message;
  final StackTrace? stackTrace;

  @override
  String toString() => 'CaptureError($message)';
}

class CaptureBridge {
  CaptureBridge({
    this.libraryPath,
    this.pollInterval = const Duration(milliseconds: 50),
  });

  final String? libraryPath;
  final Duration pollInterval;

  Isolate? _worker;
  SendPort? _workerInbox;
  ReceivePort? _fromWorker;
  StreamSubscription<dynamic>? _pcmSub;
  final StreamController<DspResult> _resultsCtrl =
      StreamController<DspResult>.broadcast();
  final StreamController<CaptureError> _errorsCtrl =
      StreamController<CaptureError>.broadcast();
  Completer<void>? _readyCompleter;
  bool _disposed = false;

  /// Broadcast stream of rolling `DspResult` snapshots. UI subscribes
  /// here; no other state source is allowed.
  Stream<DspResult> get results => _resultsCtrl.stream;

  /// Broadcast stream of capture / worker errors. UI must render these
  /// (e.g., a banner) — silent fallback to a synthetic source is
  /// explicitly forbidden by the anti-fake rules.
  Stream<CaptureError> get errors => _errorsCtrl.stream;

  bool get isRunning => _worker != null;

  /// Spawn the worker if not already running, then bind [pcmStream] as
  /// the live audio source. The bridge forwards each chunk into the
  /// worker; encoding is announced explicitly so the worker rejects
  /// surprise formats instead of guessing.
  Future<void> start({
    required Stream<Uint8List> pcmStream,
    required int sampleRate,
    String encoding = 'pcm16',
  }) async {
    _ensureAlive();
    if (_worker == null) {
      await _spawnWorker(sampleRate: sampleRate);
    }
    // Drop any previous source.
    await _pcmSub?.cancel();
    _pcmSub = pcmStream.listen(
      (chunk) {
        final inbox = _workerInbox;
        if (inbox == null || chunk.isEmpty) return;
        inbox.send(
            PushPcm(chunk, sampleRate: sampleRate, encoding: encoding));
      },
      onError: (Object e, StackTrace st) =>
          _errorsCtrl.add(CaptureError('audio source error: $e', st)),
      cancelOnError: false,
    );
  }

  /// Detach the audio source and ask the worker to drop rolling state.
  /// The worker stays alive so a subsequent `start` is fast.
  Future<void> stop() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    _workerInbox?.send(const ResetEngine());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _pcmSub?.cancel();
    _pcmSub = null;
    _workerInbox?.send(const StopWorker());
    // Give the worker a brief window to free its FFI handle cleanly.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _fromWorker?.close();
    _fromWorker = null;
    _workerInbox = null;
    await _resultsCtrl.close();
    await _errorsCtrl.close();
  }

  Future<void> _spawnWorker({required int sampleRate}) async {
    _readyCompleter = Completer<void>();
    _fromWorker = ReceivePort();
    _fromWorker!.listen(_handleWorkerMessage);
    final init = WorkerInit(
      replyPort: _fromWorker!.sendPort,
      libraryPath: libraryPath ?? _platformDefaultLibrary(),
      captureSampleRate: sampleRate,
      pollIntervalMs: pollInterval.inMilliseconds,
    );
    _worker = await Isolate.spawn<WorkerInit>(
      dspWorkerEntry,
      init,
      debugName: 'hitech-bpm-dsp-worker',
      errorsAreFatal: true,
    );
    await _readyCompleter!.future
        .timeout(const Duration(seconds: 5), onTimeout: () {
      throw StateError('DSP worker did not signal ready within 5s');
    });
  }

  void _handleWorkerMessage(dynamic message) {
    if (message is SendPort) {
      _workerInbox = message;
    } else if (message is WorkerReady) {
      if (!(_readyCompleter?.isCompleted ?? true)) {
        _readyCompleter!.complete();
      }
    } else if (message is DspResultMessage) {
      try {
        final parsed = DspResult.parse(message.json);
        if (!_resultsCtrl.isClosed) _resultsCtrl.add(parsed);
      } catch (e, st) {
        _errorsCtrl.add(CaptureError('failed to parse DspResult: $e', st));
      }
    } else if (message is WorkerError) {
      _errorsCtrl.add(CaptureError(message.message, message.stackTrace));
      if (!(_readyCompleter?.isCompleted ?? true)) {
        _readyCompleter!.completeError(StateError(message.message));
      }
    }
  }

  void _ensureAlive() {
    if (_disposed) {
      throw StateError('CaptureBridge has been disposed');
    }
  }

  String _platformDefaultLibrary() {
    try {
      return defaultLibraryName();
    } catch (_) {
      // On hosts where we don't recognize the platform, let the worker
      // try the literal default — it'll surface a load failure via
      // WorkerError, which UI must render.
      return 'libhitech_bpm_ffi';
    }
  }
}
