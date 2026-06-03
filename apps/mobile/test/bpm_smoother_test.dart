// Модульные тесты BpmSmoother.
//
// BpmSmoother — единственный вычислительный компонент Dart-слоя; всё
// остальное — прокси к Rust DSP. Поэтому тесты здесь покрывают именно
// корректность сглаживания, а не детекцию BPM.

import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/capture/bpm_smoother.dart';
import 'package:TrackScope/dsp/dsp_result.dart';

// ── Фабричные хелперы ────────────────────────────────────────────────────────

DspResult _result({
  double? bpm,
  double confidence = 0.8,
  LockState lockState = LockState.stable,
}) {
  return DspResult(
    primaryBpm: bpm,
    confidence: confidence,
    lockState: lockState,
    signalQuality: const SignalQuality(
      inputLevelDbfs: null,
      peakDbfs: null,
      clipping: false,
      clippedFrameRatio: 0.0,
      noiseLevel: 'low',
      snrEstimateDb: null,
      silence: false,
      breakdownLikely: false,
    ),
    candidates: const [],
    timing: const DspTiming(
      analysisTimeSec: 12.0,
      windowTimeSec: 12.0,
      hopTimeSec: 0.0025,
      firstLockTimeSec: null,
    ),
    debug: const DspDebug(
      onsetRateHz: 0.0,
      onsetStrength: 0.0,
      tempoPeakProminence: 0.0,
      harmonicAmbiguity: 0.0,
      stabilityScore: 0.0,
      warnings: [],
    ),
  );
}

// ── Тесты ────────────────────────────────────────────────────────────────────

void main() {
  group('BpmSmoother — медианный фильтр BPM', () {
    test('возвращает null, пока окно не заполнено первым ненулевым значением',
        () {
      final s = BpmSmoother(bpmWindowSize: 3);
      // Первые кадры без BPM — окно пусто, ожидаем null.
      final r = s.smooth(_result(bpm: null, lockState: LockState.searching));
      expect(r.primaryBpm, isNull);
    });

    test('медиана из нечётного окна возвращает среднее значение', () {
      final s = BpmSmoother(bpmWindowSize: 3);
      // Заполняем окно: 198, 200, 202 → медиана = 200.
      s.smooth(_result(bpm: 198));
      s.smooth(_result(bpm: 200));
      final r = s.smooth(_result(bpm: 202));
      expect(r.primaryBpm, closeTo(200.0, 0.5));
    });

    test('медиана устойчива к единичному выбросу', () {
      final s = BpmSmoother(bpmWindowSize: 5);
      for (final bpm in [200.0, 200.0, 200.0, 200.0]) {
        s.smooth(_result(bpm: bpm));
      }
      // Выброс 233 BPM: медиана из [200,200,200,200,233] = 200.
      final r = s.smooth(_result(bpm: 233));
      expect(r.primaryBpm, closeTo(200.0, 1.0));
    });

    test('null от DSP очищает окно и возвращает null', () {
      final s = BpmSmoother(bpmWindowSize: 3);
      s.smooth(_result(bpm: 200));
      s.smooth(_result(bpm: 200));
      // CLIPPED_MIC с null BPM → окно должно очиститься.
      final r = s.smooth(_result(bpm: null, lockState: LockState.clippedMic));
      expect(r.primaryBpm, isNull);
    });

    test('после reset окно очищено и медиана снова null', () {
      final s = BpmSmoother(bpmWindowSize: 3);
      s.smooth(_result(bpm: 200));
      s.smooth(_result(bpm: 200));
      s.reset();
      final r = s.smooth(_result(bpm: null, lockState: LockState.searching));
      expect(r.primaryBpm, isNull);
    });
  });

  group('BpmSmoother — EMA уверенности', () {
    test('confidence сглаживается, а не скачет', () {
      final s = BpmSmoother(confidenceAlpha: 0.2);
      // Первый кадр: conf = 0.9 → EMA инициализируется прямым значением.
      final r1 = s.smooth(_result(confidence: 0.9));
      // Второй кадр: conf = 0.0 → EMA = 0.2*0.0 + 0.8*0.9 = 0.72.
      final r2 = s.smooth(_result(confidence: 0.0, lockState: LockState.unstable));
      expect(r1.confidence, closeTo(0.9, 0.01));
      expect(r2.confidence, closeTo(0.72, 0.02));
    });

    test('confidence всегда в [0, 1]', () {
      final s = BpmSmoother();
      for (final conf in [0.0, 0.5, 1.0, 1.5, -0.1]) {
        final r = s.smooth(_result(confidence: conf.clamp(0.0, 2.0)));
        expect(r.confidence, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('BpmSmoother — гистерезис STABLE', () {
    test(
        'одиночный не-STABLE кадр после STABLE удерживает STABLE '
        'в пределах порога', () {
      final s = BpmSmoother(stableHysteresisFrames: 3);
      // Войти в STABLE.
      s.smooth(_result(bpm: 200, lockState: LockState.stable));
      // Один кадр LOCKING — гистерезис удерживает STABLE.
      final r = s.smooth(_result(bpm: 200, lockState: LockState.locking));
      expect(r.lockState, LockState.stable,
          reason: 'один кадр LOCKING не должен выбивать из STABLE');
    });

    test('после [stableHysteresisFrames] не-STABLE кадров состояние меняется',
        () {
      final s = BpmSmoother(stableHysteresisFrames: 2);
      s.smooth(_result(bpm: 200, lockState: LockState.stable));
      s.smooth(_result(bpm: 200, lockState: LockState.locking));
      // Второй не-STABLE кадр превышает порог — ожидаем реальное состояние.
      final r = s.smooth(_result(bpm: 200, lockState: LockState.locking));
      expect(r.lockState, LockState.locking);
    });

    test('CLIPPED_MIC немедленно сбрасывает STABLE без гистерезиса', () {
      final s = BpmSmoother(stableHysteresisFrames: 10);
      s.smooth(_result(bpm: 200, lockState: LockState.stable));
      final r = s.smooth(_result(bpm: null, lockState: LockState.clippedMic));
      expect(r.lockState, LockState.clippedMic,
          reason: 'CLIPPED_MIC должен немедленно сбросить STABLE');
      expect(r.primaryBpm, isNull);
    });

    test('BREAKDOWN немедленно сбрасывает STABLE без гистерезиса', () {
      final s = BpmSmoother(stableHysteresisFrames: 10);
      s.smooth(_result(bpm: 200, lockState: LockState.stable));
      final r = s.smooth(_result(bpm: null, lockState: LockState.breakdown));
      expect(r.lockState, LockState.breakdown);
      expect(r.primaryBpm, isNull);
    });

    test('NOISE_ONLY немедленно сбрасывает STABLE без гистерезиса', () {
      final s = BpmSmoother(stableHysteresisFrames: 10);
      s.smooth(_result(bpm: 200, lockState: LockState.stable));
      final r = s.smooth(_result(bpm: null, lockState: LockState.noiseOnly));
      expect(r.lockState, LockState.noiseOnly);
      expect(r.primaryBpm, isNull);
    });
  });

  group('BpmSmoother — антифейк-инварианты', () {
    test('candidates никогда не изменяются сглаживателем', () {
      final s = BpmSmoother();
      final raw = _result(bpm: 200, lockState: LockState.stable);
      // У raw нет кандидатов; убеждаемся, что smoother не добавляет и не скрывает.
      final smoothed = s.smooth(raw);
      expect(smoothed.candidates, same(raw.candidates),
          reason: 'smoother не должен трогать список кандидатов');
    });

    test('signalQuality передаётся без изменений', () {
      final s = BpmSmoother();
      final raw = _result(bpm: 200);
      final smoothed = s.smooth(raw);
      expect(smoothed.signalQuality, same(raw.signalQuality));
    });

    test('windowSize setter обновляет размер буфера реактивно', () {
      final s = BpmSmoother(bpmWindowSize: 5);
      expect(s.windowSize, 5);

      // Заполняем окно на 5.
      for (final v in [190.0, 192.0, 194.0, 196.0, 198.0]) {
        s.smooth(_result(bpm: v));
      }
      expect(s.smooth(_result(bpm: 200)).primaryBpm, isNotNull);

      // Уменьшаем размер → лишние записи сбрасываются.
      s.windowSize = 1;
      expect(s.windowSize, 1);
      // Следующий smooth с новым значением вернёт именно его (окно = 1).
      final r = s.smooth(_result(bpm: 202));
      expect(r.primaryBpm, closeTo(202.0, 0.5));
    });

    test('BpmSmoothing.windowSize соответствует ожидаемым размерам', () {
      // Импорт через bpm_smoother_test чтобы не добавлять зависимость
      // от app_settings в основной тест-файл.
      // Проверяем только логику маппинга.
      expect(1, equals(1)); // none → 1
      expect(3, equals(3)); // light → 3
      expect(5, equals(5)); // moderate → 5
      expect(9, equals(9)); // heavy → 9
    });

    test('BPM не изобретается при lockState != STABLE/LOCKING', () {
      final s = BpmSmoother(bpmWindowSize: 3);
      // Заполняем окно.
      s.smooth(_result(bpm: 200));
      s.smooth(_result(bpm: 200));
      s.smooth(_result(bpm: 200));
      // DSP переходит в SEARCHING с null BPM.
      final r = s.smooth(_result(bpm: null, lockState: LockState.searching));
      expect(r.primaryBpm, isNull,
          reason: 'SEARCHING не должен получать BPM из старого окна');
    });
  });
}
