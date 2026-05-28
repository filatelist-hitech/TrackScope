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
const _kFloorDb = -60.0;

/// Reference magnitude for normalisation (1024-pt FFT, f32 [-1,1] input,
/// full-scale sine after Hann windowing gives peak ≈ 256).
const _kRefMag = 256.0;

/// Number of animated spectrum bars.
const _kBarCount = 48;

/// Lowest frequency for log-spaced bar grouping (Hz).
const _kBarMinFreq = 30.0;

/// Highest frequency for log-spaced bar grouping (Hz).
const _kBarMaxFreq = 6000.0;

/// Sample rate assumed for bar-to-bin mapping (must match the audio source).
const _kBarSampleRate = 48000.0;

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

// Pre-compute log-spaced bin ranges for each spectrum bar.
// Each entry is (binLo, binHi) — exclusive upper bound.
List<(int, int)> _buildBarBinRanges() {
  const binHz = _kBarSampleRate / _kFftSize; // ≈ 46.9 Hz / bin
  final logRatio = math.log(_kBarMaxFreq / _kBarMinFreq);
  return List.generate(_kBarCount, (bar) {
    final fLo = _kBarMinFreq * math.exp(logRatio * bar / (_kBarCount - 1));
    final fHi = _kBarMinFreq * math.exp(logRatio * (bar + 1) / (_kBarCount - 1));
    final binLo = (fLo / binHz).floor().clamp(0, _kDisplayBins - 1);
    final binHi = (fHi / binHz).ceil().clamp(binLo + 1, _kDisplayBins);
    return (binLo, binHi);
  });
}

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
    _barBinRanges = _buildBarBinRanges();
  }

  late final List<Color> _lut;

  /// 256 pre-created Paint objects indexed by LUT entry.
  /// Read directly by SpectrogramPainter.
  late final List<Paint> lutPaints;

  // PCM ring buffer — decoded f32 samples.
  final Queue<double> _pcmQueue = Queue();
  int _newSampleCount = 0;
  bool _fftInFlight = false;

  // Spectrum bars: log-spaced bin groups + smoothed heights.
  late final List<(int, int)> _barBinRanges;

  // Mutable smooth state (one double per bar, updated in-place for decay).
  final _barSmoothData = List<double>.filled(_kBarCount, 0.0);

  // Public snapshot — replaced atomically so shouldRepaint(identical) fires.
  List<double> _smoothedBars = const <double>[];

  /// 48 smoothed bar heights in [0, 1], fast attack / ~300 ms decay.
  /// Replaced on every FFT column — use identity check in shouldRepaint.
  List<double> get smoothedBars => _smoothedBars;

  // Beat energy: chunk RMS with fast-attack / slow-decay envelope.
  // Driven exclusively by incoming PCM — reflects real audio transients.
  // Used by WaveformPainter and main_screen for beat-reactive glow.
  double _beatDecay = 0.0;

  /// Beat energy in [0, 1]. Fast attack (immediate), decay ~200 ms per chunk.
  double get beatDecay => _beatDecay;

  // Adaptive spectrogram normalisation: tracks the rolling peak magnitude
  // so the full LUT colour range is used even at modest input levels.
  double _adaptiveMaxMag = _kRefMag;

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
    // Accumulate sum-of-squares inline for chunk RMS (zero extra pass).
    var sumSq = 0.0;
    for (var i = 0; i < count; i++) {
      final lo = bytes[i * 2];
      final hi = bytes[i * 2 + 1];
      var raw = (hi << 8) | lo;
      if (raw >= 0x8000) raw -= 0x10000;
      final s = raw / 32768.0;
      _pcmQueue.addLast(s);
      sumSq += s * s;
    }
    _newSampleCount += count;

    // Beat-energy envelope: fast attack, ~0.88^1 ≈ 88% per chunk (~200 ms decay).
    final chunkRms = math.sqrt(sumSq / count).clamp(0.0, 1.0);
    _beatDecay = math.max(chunkRms, _beatDecay * 0.88).clamp(0.0, 1.0);

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

      // Adaptive peak normalisation: fast attack (immediate max), slow decay
      // (~0.997 per column ≈ full decay in ~250 columns = ~12 s at 20 fps).
      // Prevents the display from being dominated by a single loud frequency.
      double colMax = 0.0;
      for (var i = 0; i < _kDisplayBins; i++) {
        if (mags[i] > colMax) colMax = mags[i];
      }
      _adaptiveMaxMag = math.max(
        math.max(colMax, _kRefMag * 0.02), // keep a minimum floor
        _adaptiveMaxMag * 0.997,
      );

      // Convert magnitudes to LUT indices.
      final col = Int32List(_kDisplayBins);
      for (var i = 0; i < _kDisplayBins; i++) {
        col[i] = _magToLutIdx(mags[i]);
      }

      _specCols.add(col);
      while (_specCols.length > _kMaxCols) {
        _specCols.removeAt(0);
      }
      // ── Animated spectrum bars ────────────────────────────────────────────
      // Group linear FFT bins into log-spaced bars (30 Hz → 6 kHz),
      // apply fast-attack / slow-decay envelope (~300 ms at 20 fps).
      for (var bar = 0; bar < _kBarCount; bar++) {
        final (binLo, binHi) = _barBinRanges[bar];
        var peak = 0.0;
        for (var b = binLo; b < binHi; b++) {
          if (mags[b] > peak) peak = mags[b];
        }
        final norm = _magToNorm(peak);
        _barSmoothData[bar] =
            math.max(norm, _barSmoothData[bar] * 0.80).clamp(0.0, 1.0);
      }
      // Publish an immutable snapshot so shouldRepaint(identical) fires.
      _smoothedBars = List<double>.unmodifiable(_barSmoothData);

      notifyListeners();
    } catch (_) {
      // FFT failure is non-fatal — skip this column.
    } finally {
      _fftInFlight = false;
    }
  }

  /// Returns normalised energy in [0, 1] using log scale + adaptive peak.
  double _magToNorm(double mag) {
    if (mag <= 0) return 0.0;
    final n = (mag / _adaptiveMaxMag).clamp(1e-7, 1.0);
    final db = 20.0 * math.log(n) / math.ln10;
    return ((db - _kFloorDb) / (-_kFloorDb)).clamp(0.0, 1.0);
  }

  int _magToLutIdx(double mag) => (_magToNorm(mag) * 255).round().clamp(0, 255);

  // ── Session reset ──────────────────────────────────────────────────────────

  void reset() {
    _pcmQueue.clear();
    _specCols.clear();
    _waveCache = const [];
    _newSampleCount = 0;
    _beatDecay = 0.0;
    _adaptiveMaxMag = _kRefMag;
    _barSmoothData.fillRange(0, _kBarCount, 0.0);
    _smoothedBars = const <double>[];
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
