// Модульные тесты BpmDisplay.
//
// BpmDisplay — финальный display-layer EMA поверх сглаженного DspResult.
// Активен только в STABLE; снэпает к первому значению без задержки EMA.

import 'package:flutter_test/flutter_test.dart';
import 'package:hitech_bpm_radar/capture/bpm_display.dart';
import 'package:hitech_bpm_radar/dsp/dsp_result.dart';

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
  );
}

// ── Тесты ────────────────────────────────────────────────────────────────────

void main() {
  group('BpmDisplay', () {
    late BpmDisplay display;

    setUp(() => display = BpmDisplay());

    // 1. Не-STABLE состояния возвращают null.
    test('returns null for all non-STABLE lock states', () {
      for (final state in [
        LockState.searching,
        LockState.locking,
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

    // 2. Первый STABLE-кадр → немедленный снэп, без EMA-лага.
    test('snaps to first STABLE value without EMA delay', () {
      final result = display.update(_result(bpm: 195.0));
      expect(result, equals(195.0));
      expect(display.displayBpm, equals(195.0));
    });

    // 3. EMA-сглаживание на последующих STABLE-кадрах.
    //    display = 0.2 * new + 0.8 * prev
    test('applies EMA on subsequent STABLE frames', () {
      display.update(_result(bpm: 195.0)); // snap
      final result = display.update(_result(bpm: 196.0));
      // 0.2 * 196.0 + 0.8 * 195.0 = 195.2
      expect(result, closeTo(195.2, 0.01));
    });

    // 4. Выход из STABLE → сброс в null.
    test('resets to null when STABLE exits', () {
      display.update(_result(bpm: 195.0)); // snap
      display.update(_result(bpm: 195.0)); // EMA
      display.update(_result(bpm: null, lockState: LockState.locking));
      expect(display.displayBpm, isNull);
    });

    // 5. Повторный вход в STABLE → снэп к новому значению, без контаминации.
    test('snaps again on STABLE re-entry without history contamination', () {
      display.update(_result(bpm: 195.0)); // snap 195
      display.update(_result(bpm: 195.0)); // EMA
      // Выход из STABLE
      display.update(_result(bpm: null, lockState: LockState.searching));
      // Новый захват на 180 BPM
      final result = display.update(_result(bpm: 180.0));
      expect(result, equals(180.0)); // snap без влияния истории 195
    });

    // 6. Anti-fake: STABLE + null primary_bpm → null (не изобретаем значение).
    test('returns null if primaryBpm is null even in STABLE', () {
      final result = display.update(_result(bpm: null, lockState: LockState.stable));
      expect(result, isNull);
      expect(display.displayBpm, isNull);
    });

    // 7. reset() явно очищает состояние.
    test('reset() clears state', () {
      display.update(_result(bpm: 200.0)); // snap
      display.reset();
      expect(display.displayBpm, isNull);
      // После сброса следующий STABLE снова снэпает.
      final result = display.update(_result(bpm: 180.0));
      expect(result, equals(180.0));
    });

    // 8. EMA сходится: многократное обновление одинаковым значением
    //    стабилизируется на том же значении.
    test('EMA converges to constant input', () {
      display.update(_result(bpm: 200.0)); // snap
      for (var i = 0; i < 50; i++) {
        display.update(_result(bpm: 200.0));
      }
      expect(display.displayBpm, closeTo(200.0, 0.001));
    });
  });
}
