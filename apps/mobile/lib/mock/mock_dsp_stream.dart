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

  // Контроллер для переключения режимов в реальном времени
  static final _modeController = StreamController<MockDspMode>.broadcast();
  static var _currentMode = MockDspMode.idle;

  /// Целевой темп симуляции (произвольный hitech-диапазон, не хардкод
  /// продакшен-значения — это демонстрационный поток превью).
  static const double _targetBpmActive = 174.4;
  static const double _targetBpmUnstable = 188.0;
  static final Random _rng = Random(0xB12);

  /// Управление режимом превью (idle, active, unstable)
  static Stream<MockDspMode> get modeStream => _modeController.stream;
  static void setMode(MockDspMode mode) {
    _currentMode = mode;
    _modeController.add(mode);
  }

  static MockDspMode get currentMode => _currentMode;

  // PCM генератор — константы
  static const int _kSampleRate = 48000;
  static const int _kChunkSamples = 2400; // 50 ms при 48 kHz

  /// Симулирует трек с переключаемыми режимами:
  /// - idle: SEARCHING, no capture, confidence ~8%
  /// - active: SEARCHING → LOCKING → STABLE ~174 BPM, confidence 77%
  /// - unstable: UNSTABLE, confidence 44%, BPM скачет
  ///
  /// Режимы переключаются через `setMode()` в реальном времени.
  static Stream<DspResult> stable() async* {
    var confidence = 0.0;
    var state = LockState.searching;
    var elapsedSec = 0.0;
    double? firstLockSec;
    var mode = _currentMode;
    late StreamSubscription<MockDspMode> modeSub;

    modeSub = modeStream.listen((newMode) {
      mode = newMode;
      // Reset state on mode change
      confidence = 0.0;
      state = LockState.searching;
      elapsedSec = 0.0;
      firstLockSec = null;
    });

    try {
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        elapsedSec += 0.05;

        // Mode-specific behavior
        switch (mode) {
          case MockDspMode.idle:
            confidence = 0.08; // Очень низкая
            state = LockState.searching;
            break;

          case MockDspMode.active:
            // Нарастание: SEARCHING → LOCKING → STABLE
            confidence = (confidence + 0.015).clamp(0.0, 0.77);
            if (confidence > 0.5 && state == LockState.searching) {
              state = LockState.locking;
              firstLockSec ??= elapsedSec;
            }
            if (confidence > 0.73 && state == LockState.locking) {
              state = LockState.stable;
            }
            break;

          case MockDspMode.unstable:
            // Скачущие значения, не достигает STABLE
            confidence = 0.44;
            state = LockState.unstable;
            break;
        }

        final locked = state != LockState.searching;
        final bpm = mode == MockDspMode.unstable
            ? _targetBpmUnstable + (_rng.nextDouble() - 0.5) * 4.0 // Больше джиттера
            : _targetBpmActive + (_rng.nextDouble() - 0.5) * 0.4;
        final primaryBpm = locked ? bpm : null;
        final inputLevel = mode == MockDspMode.idle ? -42.9 : -21.3;
        final noiseLevel = mode == MockDspMode.idle ? 'low' : 'medium';

        yield DspResult(
          primaryBpm: primaryBpm,
          confidence: confidence,
          lockState: state,
          signalQuality: SignalQuality(
            inputLevelDbfs: inputLevel + (_rng.nextDouble() - 0.5) * 0.5,
            peakDbfs: inputLevel + 5 + (_rng.nextDouble() - 0.5) * 2,
            clipping: false,
            clippedFrameRatio: 0.0,
            noiseLevel: noiseLevel,
            snrEstimateDb: 14.2 + (_rng.nextDouble() - 0.5) * 1,
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
    } finally {
      modeSub.cancel();
    }
  }

  /// Синтетический поток PCM-16 LE mono для `VizController.attachRawPcm()`.
  ///
  /// Эмитит чанки 2400 сэмплов каждые 50 мс (48 кГц). Форма сигнала —
  /// kick+bass+hat+rumble, синхронизированные с текущим режимом, зеркалит
  /// `.claude/mockup/index.html oscSample()`. Подаётся как `rawPcm:` в
  /// `main_web.dart`, чтобы waveform и live-spectrum анимировались.
  ///
  /// ТОЛЬКО для web preview — никогда не импортировать из `lib/main.dart`.
  static Stream<Uint8List> rawPcm() {
    final rng = Random(0xC13);
    var tick = 0;

    return Stream<Uint8List>.periodic(
      const Duration(milliseconds: 50),
      (_) {
        final chunkStart = tick * _kChunkSamples;
        tick++;

        // Выбор BPM в зависимости от режима
        final targetBpm = _currentMode == MockDspMode.unstable
            ? _targetBpmUnstable
            : _targetBpmActive;
        final hopMs = 60000.0 / targetBpm; // мс на удар

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

enum MockDspMode { idle, active, unstable }
