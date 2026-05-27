// Deterministic synthetic 200 BPM kick pulse for FFI smoke tests.
//
// Mirrors the generator in `core/ffi/tests/ffi_contract.rs::pulse_200_bpm`
// so the Dart side drives the engine with the exact same waveform the
// Rust integration test already validated. The math lives in Rust DSP;
// this helper only synthesizes audio.

import 'dart:math' as math;
import 'dart:typed_data';

const int kSampleRate = 48000;

Float32List pulseTrack({
  required double bpm,
  required double durationSec,
  int sampleRate = kSampleRate,
}) {
  final total = (durationSec * sampleRate).round();
  final samples = Float32List(total);
  final beatPeriod = 60.0 / bpm;
  final kickLen = (sampleRate * 0.012).round();
  var beat = 0.0;
  while (beat < durationSec) {
    final start = (beat * sampleRate).round();
    for (var i = 0; i < kickLen; i++) {
      final idx = start + i;
      if (idx >= samples.length) break;
      final phase = i / sampleRate;
      final env = math.exp(-phase * 90.0);
      final osc = math.sin(2 * math.pi * 60.0 * phase);
      samples[idx] += 0.9 * env * osc;
    }
    beat += beatPeriod;
  }
  return samples;
}
