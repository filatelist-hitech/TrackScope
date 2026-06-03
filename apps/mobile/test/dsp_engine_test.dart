// FFI smoke test: drive synthetic 200 BPM PCM through the Dart-side
// `DspEngine` wrapper and assert the Rust DSP reaches STABLE with
// primary_bpm ≈ 200. Mirrors `core/ffi/tests/ffi_contract.rs` but
// exercises the Dart binding layer end-to-end.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/dsp/dsp_result.dart';
import 'package:TrackScope/dsp/engine.dart';

import 'helpers/native_library.dart';
import 'helpers/synthetic_pulse.dart';

void main() {
  late NativeLibrary nativeLib;

  setUpAll(() async {
    nativeLib = await NativeLibrary.ensureBuilt();
  });

  test('engine reaches STABLE on 13 s of clean 200 BPM PCM', () async {
    final engine = DspEngine.open(libraryPath: nativeLib.path);
    addTearDown(engine.dispose);

    // 100 ms chunks, 13 s total — by contract the streaming engine must
    // reach STABLE within 12 s on a clean signal.
    const chunkSec = 0.1;
    final chunkLen = (kSampleRate * chunkSec).round();
    final pcm = pulseTrack(bpm: 200.0, durationSec: 13.0);

    for (var offset = 0; offset < pcm.length; offset += chunkLen) {
      final end = offset + chunkLen <= pcm.length ? offset + chunkLen : pcm.length;
      final chunk = Float32List.sublistView(pcm, offset, end);
      final ok = engine.pushSamples(chunk, kSampleRate);
      expect(ok, isTrue, reason: 'pushSamples rejected a valid chunk');
    }

    final result = engine.analyze();

    expect(result.lockState, LockState.stable,
        reason: '13 s of clean 200 BPM must reach STABLE — got '
            '${result.lockState.wireName}');
    expect(result.primaryBpm, isNotNull,
        reason: 'primary_bpm must be set when STABLE');
    expect((result.primaryBpm! - 200.0).abs() <= 2.0, isTrue,
        reason: 'primary_bpm = ${result.primaryBpm}, want 200 ± 2');
    expect(result.confidence, inInclusiveRange(0.0, 1.0));

    // Half/double candidates must remain visible — UI never hides them.
    final hasHalfEvidence = result.candidates
        .any((c) => (c.bpm - 100.0).abs() < 5.0);
    expect(hasHalfEvidence, isTrue,
        reason: 'half-time candidate near 100 BPM must remain visible');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('engine never reports STABLE on 14 s of silence', () async {
    final engine = DspEngine.open(libraryPath: nativeLib.path);
    addTearDown(engine.dispose);

    const chunkSec = 0.1;
    final chunkLen = (kSampleRate * chunkSec).round();
    final zeros = Float32List(chunkLen);
    final totalChunks = (14 / chunkSec).round();
    for (var i = 0; i < totalChunks; i++) {
      final ok = engine.pushSamples(zeros, kSampleRate);
      expect(ok, isTrue);
    }

    final result = engine.analyze();
    expect(result.lockState, isNot(LockState.stable),
        reason: 'silence must never reach STABLE — got '
            '${result.lockState.wireName}');
    expect(result.primaryBpm, isNull,
        reason: 'silence must yield null primary_bpm');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('stream emits parsed DspResult snapshots while subscribed', () async {
    final engine = DspEngine.open(
      libraryPath: nativeLib.path,
      pollInterval: const Duration(milliseconds: 20),
    );
    addTearDown(engine.dispose);

    const chunkSec = 0.1;
    final chunkLen = (kSampleRate * chunkSec).round();
    final pcm = pulseTrack(bpm: 200.0, durationSec: 1.0);
    for (var offset = 0; offset < pcm.length; offset += chunkLen) {
      final end = offset + chunkLen <= pcm.length ? offset + chunkLen : pcm.length;
      final chunk = Float32List.sublistView(pcm, offset, end);
      engine.pushSamples(chunk, kSampleRate);
    }

    final snapshot =
        await engine.results.first.timeout(const Duration(seconds: 2));
    // 1 s is not enough for STABLE — we only assert the wire shape, not
    // a specific lock state.
    expect(snapshot.candidates, isA<List<TempoCandidate>>());
    expect(snapshot.signalQuality.noiseLevel, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 10)));
}
