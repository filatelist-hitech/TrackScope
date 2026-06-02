// ТОЛЬКО для web preview. Не детектор, не production.
//
// Этот класс НЕ считает BPM по аудио — он генерирует синтетические
// снапшоты `DspResult` исключительно для итерации по UI в браузере, где
// нативный Rust/FFI DSP недоступен. Он НИКОГДА не импортируется из
// `lib/main.dart` (мобильный/продакшен-путь) — только из `main_web.dart`.
//
// Anti-fake: значения здесь — заведомо симулированные. Web-превью рисует
// баннер «PREVIEW · MOCK DATA», чтобы их нельзя было принять за реальный
// захват. На мобильном устройстве используется настоящий DSP-движок.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../dsp/dsp_result.dart';

/// Генератор симулированного потока `DspResult` для web-превью UI.
class MockDspStream {
  MockDspStream._();

  /// Целевой темп симуляции (произвольный hitech-диапазон, не хардкод
  /// продакшен-значения — это демонстрационный поток превью).
  static const double _targetBpm = 193.0;
  static final Random _rng = Random(0xB12);

  // PCM генератор — константы
  static const int _kSampleRate = 48000;
  static const int _kChunkSamples = 2400; // 50 ms при 48 kHz

  /// Симулирует трек, выходящий на стабильный захват ~193 BPM:
  /// SEARCHING → LOCKING → STABLE с нарастанием уверенности и лёгким
  /// джиттером BPM. `primaryBpm` остаётся `null` в SEARCHING (контракт
  /// «нет значения до захвата»).
  static Stream<DspResult> stable() async* {
    var confidence = 0.30;
    var state = LockState.searching;
    var elapsedSec = 0.0;
    double? firstLockSec;

    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      elapsedSec += 0.1;

      confidence = (confidence + 0.02).clamp(0.0, 0.92);
      if (confidence > 0.5 && state == LockState.searching) {
        state = LockState.locking;
        firstLockSec ??= elapsedSec;
      }
      if (confidence > 0.75 && state == LockState.locking) {
        state = LockState.stable;
      }

      final locked = state != LockState.searching;
      final bpm = _targetBpm + (_rng.nextDouble() - 0.5) * 0.4;
      final primaryBpm = locked ? bpm : null;

      yield DspResult(
        primaryBpm: primaryBpm,
        confidence: confidence,
        lockState: state,
        signalQuality: SignalQuality(
          inputLevelDbfs: -15.0 + (_rng.nextDouble() - 0.5) * 2,
          peakDbfs: -8.0 + (_rng.nextDouble() - 0.5) * 2,
          clipping: false,
          clippedFrameRatio: 0.0,
          noiseLevel: 'low',
          snrEstimateDb: 18.0 + (_rng.nextDouble() - 0.5) * 2,
          silence: false,
          breakdownLikely: false,
        ),
        candidates: [
          TempoCandidate(
            bpm: bpm,
            relation: 'main',
            score: confidence,
            rawScore: confidence,
            stabilityScore: confidence * 0.9,
            rangeScore: 1.0,
            sourceBpm: null,
          ),
          // half-time-кандидат всегда виден (anti-fake: не скрываем).
          TempoCandidate(
            bpm: bpm / 2,
            relation: 'half_time',
            score: confidence * 0.4,
            rawScore: confidence * 0.4,
            stabilityScore: confidence * 0.4,
            rangeScore: 0.1,
            sourceBpm: bpm,
          ),
        ],
        timing: DspTiming(
          analysisTimeSec: elapsedSec,
          windowTimeSec: 12.0,
          hopTimeSec: 0.0025,
          firstLockTimeSec: firstLockSec,
        ),
        debug: DspDebug(
          onsetRateHz: locked ? 3.3 : 0.0,
          onsetStrength: locked ? 0.025 : 0.0,
          tempoPeakProminence: locked ? confidence * 0.6 : 0.0,
          harmonicAmbiguity: 0.1,
          stabilityScore: confidence * 0.9,
          warnings: const [],
        ),
      );
    }
  }

  /// Синтетический поток PCM-16 LE mono для `VizController.attachRawPcm()`.
  ///
  /// Эмитит чанки 2400 сэмплов каждые 50 мс (48 кГц). Форма сигнала —
  /// kick+bass+hat+rumble, синхронизированные с `_targetBpm`, зеркалит
  /// `.claude/mockup/index.html oscSample()`. Подаётся как `rawPcm:` в
  /// `main_web.dart`, чтобы waveform и live-spectrum анимировались.
  ///
  /// ТОЛЬКО для web preview — никогда не импортировать из `lib/main.dart`.
  static Stream<Uint8List> rawPcm() {
    const hopMs = 60000.0 / _targetBpm; // мс на удар ~311 мс
    final rng = Random(0xC13);
    var tick = 0;

    return Stream<Uint8List>.periodic(
      const Duration(milliseconds: 50),
      (_) {
        final chunkStart = tick * _kChunkSamples;
        tick++;

        final bytes = Uint8List(_kChunkSamples * 2);
        for (var i = 0; i < _kChunkSamples; i++) {
          final sampleIdx = chunkStart + i;
          final elapsedMs = sampleIdx * 1000.0 / _kSampleRate;
          final beat = (elapsedMs % hopMs) / hopMs; // 0..1 внутри удара

          final kick = exp(-beat * 14.0) * sin(beat * pi * 18.0) * 0.75;
          final bass =
              exp(-beat * 3.0) * sin(2.0 * pi * elapsedMs / 1000.0 * 65.0) * 0.22;
          final hat = beat < 0.06 ? (rng.nextDouble() - 0.5) * 0.12 : 0.0;
          final rumble = sin(2.0 * pi * elapsedMs / 1000.0 * 32.0) * 0.06;

          final sample = (kick + bass + hat + rumble).clamp(-1.0, 1.0);

          // PCM-16 LE: two's complement little-endian
          var pcm = (sample * 32767.0).round().clamp(-32768, 32767);
          if (pcm < 0) pcm += 65536;
          bytes[i * 2] = pcm & 0xFF;
          bytes[i * 2 + 1] = (pcm >> 8) & 0xFF;
        }
        return bytes;
      },
    );
  }
}
