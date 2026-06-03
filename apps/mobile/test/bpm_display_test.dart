// Модульные тесты BpmDisplay.
//
// BpmDisplay — финальный display-layer EMA поверх сглаженного DspResult.
// В режиме allowLocking=true (дефолт) возвращает raw primaryBpm при LOCKING,
// EMA-сглаженное при STABLE; снэпает к первому значению без задержки EMA.

import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/capture/bpm_display.dart';
import 'package:TrackScope/dsp/dsp_result.dart';

// ── Фабричные хелперы ────────────────────────────────────────────────────────

DspResult _result({
  double? bpm,
  double confidence = 0.85,
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
  group('BpmDisplay (allowLocking=true, default)', () {
    late BpmDisplay display;

    setUp(() => display = BpmDisplay());

    // 1. Не-STABLE/LOCKING состояния возвращают null.
    test('returns null for all non-STABLE/non-LOCKING lock states', () {
      for (final state in [
        LockState.searching,
        LockState.unstable,
        LockState.breakdown,
        LockState.clippedMic,
        LockState.noiseOnly,
      ]) {
        final result = display.update(_result(bpm: 195.0, lockState: state));
        expect(result, isNull, reason: 'Expected null for $state');
        expect(display.displayBpm, isNull);
      }
    });

    // 2. LOCKING возвращает raw primaryBpm без EMA.
    test('returns raw primaryBpm during LOCKING without EMA', () {
      final result = display.update(_result(bpm: 195.0, lockState: LockState.locking));
      expect(result, equals(195.0));
      expect(display.displayBpm, equals(195.0));
      expect(display.isLockingDisplay, isTrue);
    });

    // 3. LOCKING → LOCKING: каждый кадр возвращает raw, без накопления EMA.
    test('LOCKING frames return raw bpm, no EMA accumulation', () {
      display.update(_result(bpm: 195.0, lockState: LockState.locking));
      final result = display.update(_result(bpm: 196.0, lockState: LockState.locking));
      expect(result, equals(196.0)); // raw, без EMA
      expect(display.isLockingDisplay, isTrue);
    });

    // 4. LOCKING → STABLE: снэп к первому STABLE-значению без EMA-лага.
    test('snaps to first STABLE value after LOCKING without EMA delay', () {
      display.update(_result(bpm: 195.0, lockState: LockState.locking));
      final result = display.update(_result(bpm: 196.0));
      expect(result, equals(196.0)); // снэп, без EMA
      expect(display.isLockingDisplay, isFalse);
    });

    // 5. Первый STABLE-кадр → немедленный снэп, без EMA-лага.
    test('snaps to first STABLE value without EMA delay', () {
      final result = display.update(_result(bpm: 195.0));
      expect(result, equals(195.0));
      expect(display.displayBpm, equals(195.0));
      expect(display.isLockingDisplay, isFalse);
    });

    // 6. EMA-сглаживание на последующих STABLE-кадрах.
    //    display = 0.2 * new + 0.8 * prev
    test('applies EMA on subsequent STABLE frames', () {
      display.update(_result(bpm: 195.0)); // snap
      final result = display.update(_result(bpm: 196.0));
      // 0.2 * 196.0 + 0.8 * 195.0 = 195.2
      expect(result, closeTo(195.2, 0.01));
    });

    // 7. Выход из STABLE → сброс в null.
    test('resets to null when STABLE exits to non-LOCKING state', () {
      display.update(_result(bpm: 195.0)); // snap
      display.update(_result(bpm: 195.0)); // EMA
      display.update(_result(bpm: null, lockState: LockState.unstable));
      expect(display.displayBpm, isNull);
      expect(display.isLockingDisplay, isFalse);
    });

    // 8. Повторный вход в STABLE → снэп к новому значению, без контаминации.
    test('snaps again on STABLE re-entry without history contamination', () {
      display.update(_result(bpm: 195.0)); // snap 195
      display.update(_result(bpm: 195.0)); // EMA
      // Выход из STABLE
      display.update(_result(bpm: null, lockState: LockState.searching));
      // Новый захват на 180 BPM
      final result = display.update(_result(bpm: 180.0));
      expect(result, equals(180.0)); // snap без влияния истории 195
    });

    // 9. Anti-fake: STABLE + null primary_bpm → null (не изобретаем значение).
    test('returns null if primaryBpm is null even in STABLE', () {
      final result = display.update(_result(bpm: null, lockState: LockState.stable));
      expect(result, isNull);
      expect(display.displayBpm, isNull);
    });

    // 10. Anti-fake: LOCKING + null primary_bpm → null.
    test('returns null if primaryBpm is null even in LOCKING', () {
      final result = display.update(_result(bpm: null, lockState: LockState.locking));
      expect(result, isNull);
      expect(display.displayBpm, isNull);
    });

    // 11. reset() явно очищает состояние.
    test('reset() clears state', () {
      display.update(_result(bpm: 200.0)); // snap
      display.reset();
      expect(display.displayBpm, isNull);
      expect(display.isLockingDisplay, isFalse);
      // После сброса следующий STABLE снова снэпает.
      final result = display.update(_result(bpm: 180.0));
      expect(result, equals(180.0));
    });

    // 12. EMA сходится: многократное обновление одинаковым значением
    //     стабилизируется на том же значении.
    test('EMA converges to constant input', () {
      display.update(_result(bpm: 200.0)); // snap
      for (var i = 0; i < 50; i++) {
        display.update(_result(bpm: 200.0));
      }
      expect(display.displayBpm, closeTo(200.0, 0.001));
    });
  });

  group('BpmDisplay (allowLocking=false)', () {
    late BpmDisplay display;

    setUp(() => display = BpmDisplay(allowLocking: false));

    // LOCKING возвращает null когда allowLocking=false.
    test('returns null for LOCKING when allowLocking=false', () {
      final result = display.update(_result(bpm: 195.0, lockState: LockState.locking));
      expect(result, isNull);
      expect(display.displayBpm, isNull);
      expect(display.isLockingDisplay, isFalse);
    });

    // STABLE работает нормально при allowLocking=false.
    test('STABLE still works with allowLocking=false', () {
      final result = display.update(_result(bpm: 195.0));
      expect(result, equals(195.0));
      expect(display.isLockingDisplay, isFalse);
    });
  });
}
