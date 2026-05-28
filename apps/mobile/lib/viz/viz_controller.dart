// VizController — main-isolate PCM ring buffer + async Dart-side FFT.
//
// Responsibilities:
//   • Subscribes to CaptureBridge.rawPcm (PCM-16 LE mono bytes).
//   • Maintains a ~4 s ring buffer of decoded f32 samples.
//   • Every ~50 ms of new samples triggers an FFT via compute() so the
//     computation runs in a separate Dart isolate, not the UI isolate.
//   • Emits notifyListeners() for the spectrogram columns (Int32List of LUT
//     indices) and a downsampled waveform slice (List<double>).
//
// Anti-fake: this controller never inspects DspResult, never estimates BPM.
// It only processes raw PCM for visualisation.

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color, Paint;
import 'package:fftea/fftea.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const _kFftSize = 1024;

/// Number of FFT magnitude bins shown (0 … kDisplayBins * sr / kFftSize Hz).
/// 128 bins × 46.9 Hz/bin ≈ 6 kHz, covering the kick, bass and lower harmonics.
const _kDisplayBins = 128;

/// Maximum time columns kept in the spectrogram ring (≈ 5 s at ~20 fps).
const _kMaxCols = 200;

/// Waveform display points (drawn as a scaled path).
const _kWaveformPoints = 300;

/// New-sample threshold before scheduling an FFT (~50 ms at 48 kHz).
const _kHopSamples = 2400;

/// PCM ring size in samples (~4 s at 48 kHz).
const _kMaxPcmSamples = 192000;

/// dB floor used for log-magnitude normalisation.
/// -45 dB gives good saturation at typical mic-to-speaker distances
/// (~30–60 cm, −25 to −15 dBFS input level). Was −60 dB which rendered
/// all bins near-black at normal club/rehearsal levels.
const _kFloorDb = -45.0;

/// Reference magnitude for normalisation (1024-pt FFT, f32 [-1,1] input,
/// full-scale sine after Hann windowing gives peak ≈ 256).
const _kRefMag = 256.0;

// ── LUT ──────────────────────────────────────────────────────────────────────
// 7 colour stops linearly interpolated into 256 entries.
// Confirmed at init time — never recomputed in the hot path.
//
// t=0/6  #0D0221 — silence, dark blue
// t=1/6  #1A1AFF — low energy, blue
// t=2/6  #00FFFF — medium, cyan
// t=3/6  #00FF88 — active, green
// t=4/6  #FFE600 — strong, yellow
// t=5/6  #FF4400 — peak onset, orange-red
// t=6/6  #FFFFFF — clipping-level transient, white

const _kStopTs = [0.0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 1.0];
const _kStopR = [0x0D, 0x1A, 0x00, 0x00, 0xFF, 0xFF, 0xFF];
const _kStopG = [0x02, 0x1A, 0xFF, 0xFF, 0xE6, 0x44, 0xFF];
const _kStopB = [0x21, 0xFF, 0xFF, 0x88, 0x00, 0x00, 0xFF];

List<Color> _buildLut() {
  final lut = List<Color>.filled(256, const Color(0xFF000000));
  for (var i = 0; i < 256; i++) {
    final t = i / 255.0;
    var lo = _kStopTs.length - 2;
    for (var s = 0; s < _kStopTs.length - 1; s++) {
      if (t <= _kStopTs[s + 1]) {
        lo = s;
        break;
      }
    }
    final span = _kStopTs[lo + 1] - _kStopTs[lo];
    final frac = span > 0 ? ((t - _kStopTs[lo]) / span).clamp(0.0, 1.0) : 0.0;
    final r = (_kStopR[lo] + (_kStopR[lo + 1] - _kStopR[lo]) * frac)
        .round()
        .clamp(0, 255);
    final g = (_kStopG[lo] + (_kStopG[lo + 1] - _kStopG[lo]) * frac)
        .round()
        .clamp(0, 255);
    final b = (_kStopB[lo] + (_kStopB[lo + 1] - _kStopB[lo]) * frac)
        .round()
        .clamp(0, 255);
    lut[i] = Color.fromARGB(255, r, g, b);
  }
  return lut;
}

// ── Top-level FFT worker (required signature for compute()) ──────────────────
// Receives a Hann-windowed Float64List of length kFftSize.
// Returns the first kFftSize/2 magnitude values (positive-frequency bins).
// Runs in a separate Dart isolate via compute() — not on the UI isolate.
// Uses fftea 1.x: FFT factory constructor + ComplexArray.magnitudes().
Float64List _fftWorker(Float64List windowed) {
  final fft = FFT(windowed.length);
  final spec = fft.realFft(windowed); // Float64x2List, length == windowed.length
  final allMags = spec.magnitudes(); // Float64List via ComplexArray extension
  return Float64List.sublistView(allMags, 0, windowed.length ~/ 2);
}

// ── VizController ─────────────────────────────────────────────────────────────

class VizController extends ChangeNotifier {
  VizController() {
    _lut = _buildLut();
    // Pre-cache Paint objects — one per LUT entry.
    // Created once here; never allocated in the paint() hot path.
    lutPaints = List.generate(256, (i) => Paint()..color = _lut[i]);
  }

  late final List<Color> _lut;

  /// 256 pre-created Paint objects indexed by LUT entry.
  /// Read directly by SpectrogramPainter.
  late final List<Paint> lutPaints;

  // PCM ring buffer — decoded f32 samples.
  final Queue<double> _pcmQueue = Queue();
  int _newSampleCount = 0;
  bool _fftInFlight = false;

  // Spectrogram: ring of LUT-index columns.
  // Each Int32List is one time column, length == _kDisplayBins.
  final List<Int32List> _specCols = [];

  /// Read-only view used by SpectrogramPainter.
  List<Int32List> get specCols => _specCols;

  /// Downsampled PCM slice for WaveformPainter (300 points).
  List<double> _waveCache = const [];
  List<double> get waveCache => _waveCache;

  bool get hasData => _pcmQueue.isNotEmpty;

  StreamSubscription<Uint8List>? _sub;

  void attachRawPcm(Stream<Uint8List> stream) {
    _sub?.cancel();
    _sub = stream.listen(_onPcmChunk, onError: (_) {});
  }

  // ── PCM ingestion ──────────────────────────────────────────────────────────

  void _onPcmChunk(Uint8List bytes) {
    final count = bytes.length ~/ 2;
    if (count == 0) return;

    // Decode PCM-16 LE signed → f32 in [-1, 1].
    for (var i = 0; i < count; i++) {
      final lo = bytes[i * 2];
      final hi = bytes[i * 2 + 1];
      var raw = (hi << 8) | lo;
      if (raw >= 0x8000) raw -= 0x10000;
      _pcmQueue.addLast(raw / 32768.0);
    }
    _newSampleCount += count;

    // Trim ring to 4 s.
    while (_pcmQueue.length > _kMaxPcmSamples) {
      _pcmQueue.removeFirst();
    }

    _updateWaveCache();

    if (_newSampleCount >= _kHopSamples && !_fftInFlight) {
      _newSampleCount = 0;
      _scheduleFFT();
    } else {
      notifyListeners();
    }
  }

  void _updateWaveCache() {
    if (_pcmQueue.isEmpty) {
      _waveCache = const [];
      return;
    }
    final list = _pcmQueue.toList();
    final step = list.length / _kWaveformPoints;
    _waveCache = List<double>.generate(_kWaveformPoints, (i) {
      final idx = (i * step).toInt().clamp(0, list.length - 1);
      return list[idx];
    });
  }

  // ── FFT scheduling ─────────────────────────────────────────────────────────

  Future<void> _scheduleFFT() async {
    _fftInFlight = true;
    try {
      if (_pcmQueue.length < _kFftSize) return;

      final list = _pcmQueue.toList();
      final start = list.length - _kFftSize;

      // Apply Hann window on the main isolate (fast, no alloc in hot path
      // since we already have the list); send windowed Float64List to the
      // compute isolate.
      final windowed = Float64List(_kFftSize);
      for (var i = 0; i < _kFftSize; i++) {
        final w = 0.5 * (1.0 - math.cos(2 * math.pi * i / (_kFftSize - 1)));
        windowed[i] = list[start + i] * w;
      }

      final mags = await compute(_fftWorker, windowed);

      // Convert magnitudes to LUT indices.
      final col = Int32List(_kDisplayBins);
      for (var i = 0; i < _kDisplayBins; i++) {
        col[i] = _magToLutIdx(mags[i]);
      }

      _specCols.add(col);
      while (_specCols.length > _kMaxCols) {
        _specCols.removeAt(0);
      }
      notifyListeners();
    } catch (_) {
      // FFT failure is non-fatal — skip this column.
    } finally {
      _fftInFlight = false;
    }
  }

  int _magToLutIdx(double mag) {
    if (mag <= 0) return 0;
    final norm = (mag / _kRefMag).clamp(1e-7, 1.0);
    final db = 20.0 * math.log(norm) / math.ln10;
    final t = ((db - _kFloorDb) / (-_kFloorDb)).clamp(0.0, 1.0);
    return (t * 255).round().clamp(0, 255);
  }

  // ── Session reset ──────────────────────────────────────────────────────────

  void reset() {
    _pcmQueue.clear();
    _specCols.clear();
    _waveCache = const [];
    _newSampleCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
