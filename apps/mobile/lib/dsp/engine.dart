// Dart-side wrapper around the hitech-bpm-ffi C ABI.
//
// Responsibilities:
//   - Own the native `HitechBpmEngine*` handle for its lifetime.
//   - Marshal `Float32List` PCM frames into pinned native memory and
//     pass them to `hitech_bpm_engine_push_samples`.
//   - Poll `hitech_bpm_engine_analyze_json` on a UI-rate timer (default
//     20 Hz) and emit parsed [DspResult] snapshots on a broadcast
//     stream.
//
// What this file does NOT do:
//   - No BPM math. All tempo / confidence / lock-state decisions stay
//     in the Rust DSP crate — this layer is a pure pass-through.
//   - No microphone capture. Mic input is the next patch; for now the
//     caller (test or future audio bridge) supplies PCM.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pffi;

import 'bindings.dart';
import 'dsp_result.dart';

/// Default filename of the shared library on each platform. Resolved
/// relative to the process search path unless [DspEngine.open] is given
/// an explicit path.
String defaultLibraryName() {
  if (Platform.isMacOS) return 'libhitech_bpm_ffi.dylib';
  if (Platform.isIOS) return 'hitech_bpm_ffi.framework/hitech_bpm_ffi';
  if (Platform.isAndroid) return 'libhitech_bpm_ffi.so';
  if (Platform.isLinux) return 'libhitech_bpm_ffi.so';
  if (Platform.isWindows) return 'hitech_bpm_ffi.dll';
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

/// Owns one native DSP engine instance and exposes its rolling state as
/// a broadcast [Stream] of [DspResult] snapshots.
class DspEngine {
  DspEngine._(this._ffi, this._handle, {required Duration pollInterval})
      : _pollInterval = pollInterval {
    _resultController = StreamController<DspResult>.broadcast(
      onListen: _startPolling,
      onCancel: _stopPollingIfIdle,
    );
  }

  /// Open the shared library at [libraryPath] (or the platform default
  /// search path) and allocate a fresh engine handle.
  factory DspEngine.open({
    String? libraryPath,
    Duration pollInterval = const Duration(milliseconds: 50),
  }) {
    final dylib = libraryPath != null
        ? ffi.DynamicLibrary.open(libraryPath)
        : ffi.DynamicLibrary.open(defaultLibraryName());
    return DspEngine.fromBindings(HitechBpmFfi(dylib),
        pollInterval: pollInterval);
  }

  /// Construct from already-resolved bindings. Useful for tests that
  /// share a single dylib across multiple engine instances.
  factory DspEngine.fromBindings(
    HitechBpmFfi bindings, {
    Duration pollInterval = const Duration(milliseconds: 50),
  }) {
    final handle = bindings.engineNew();
    if (handle == ffi.nullptr) {
      throw StateError('hitech_bpm_engine_new returned null');
    }
    return DspEngine._(bindings, handle, pollInterval: pollInterval);
  }

  final HitechBpmFfi _ffi;
  ffi.Pointer<HitechBpmEngine> _handle;
  final Duration _pollInterval;
  late final StreamController<DspResult> _resultController;
  Timer? _pollTimer;
  bool _disposed = false;

  /// Broadcast stream of rolling [DspResult] snapshots. The stream emits
  /// at [pollInterval]; subscribers receive the latest engine state, not
  /// a per-frame trace.
  Stream<DspResult> get results => _resultController.stream;

  /// Drop the rolling DSP state in place. The handle stays valid.
  void reset() {
    _ensureAlive();
    _ffi.engineReset(_handle);
  }

  /// Push a mono Float32 PCM frame at [sampleRate]. Allocation cost is
  /// one pinned native buffer per call; the caller may push as fast as
  /// audio frames arrive.
  ///
  /// Returns `false` if the FFI rejected the input (zero length, zero
  /// sample rate, etc.); the Rust side never panics on bad input.
  bool pushSamples(Float32List samples, int sampleRate) {
    _ensureAlive();
    if (samples.isEmpty) return false;
    final buffer = pffi.calloc<ffi.Float>(samples.length);
    try {
      final asFloats = buffer.asTypedList(samples.length);
      asFloats.setAll(0, samples);
      return _ffi.enginePushSamples(
          _handle, buffer, samples.length, sampleRate);
    } finally {
      pffi.calloc.free(buffer);
    }
  }

  /// Synchronously poll the current rolling [DspResult]. The wrapped
  /// stream calls this on a timer; tests can call it directly.
  DspResult analyze() => DspResult.parse(analyzeJson());

  /// Same as [analyze] but returns the raw JSON string the FFI emits.
  /// Useful for the DSP worker isolate, which forwards JSON to the main
  /// isolate without round-tripping through a typed object first.
  String analyzeJson() {
    _ensureAlive();
    final cstr = _ffi.engineAnalyzeJson(_handle);
    if (cstr == ffi.nullptr) {
      throw StateError('hitech_bpm_engine_analyze_json returned null');
    }
    try {
      return _readCString(cstr);
    } finally {
      _ffi.stringFree(cstr);
    }
  }

  /// Stop polling, release the native handle, close the stream.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_handle != ffi.nullptr) {
      _ffi.engineFree(_handle);
      _handle = ffi.nullptr;
    }
    await _resultController.close();
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(_pollInterval, (_) {
      if (_disposed) return;
      try {
        final snapshot = analyze();
        if (!_resultController.isClosed) {
          _resultController.add(snapshot);
        }
      } catch (e, st) {
        if (!_resultController.isClosed) {
          _resultController.addError(e, st);
        }
      }
    });
  }

  void _stopPollingIfIdle() {
    if (!_resultController.hasListener) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _ensureAlive() {
    if (_disposed || _handle == ffi.nullptr) {
      throw StateError('DspEngine has been disposed');
    }
  }

  static String _readCString(ffi.Pointer<ffi.Char> ptr) {
    final bytes = <int>[];
    final raw = ptr.cast<ffi.Uint8>();
    var i = 0;
    while (true) {
      final byte = raw[i];
      if (byte == 0) break;
      bytes.add(byte);
      i++;
    }
    return utf8.decode(bytes);
  }
}
