// BpmHistory unit tests — add/cap (Free 30s vs Pro), isAtLimit.

import 'package:flutter_test/flutter_test.dart';
import 'package:hitech_bpm_radar/dsp/dsp_result.dart';
import 'package:hitech_bpm_radar/history/bpm_history.dart';
import 'package:hitech_bpm_radar/monetization/feature_flags.dart';

void main() {
  group('BpmHistory', () {
    test('adds samples', () {
      final history = BpmHistory(const FeatureFlags(isPro: true));
      history.add(BpmSample(
        bpm: 200.0,
        lockState: LockState.stable,
        timestamp: DateTime.now(),
      ));

      expect(history.samples.length, 1);
      expect(history.samples.first.bpm, 200.0);
    });

    test('clear removes all samples', () {
      final history = BpmHistory(const FeatureFlags(isPro: true));
      history.add(BpmSample(
        bpm: 200.0,
        lockState: LockState.stable,
        timestamp: DateTime.now(),
      ));
      history.clear();

      expect(history.samples.isEmpty, isTrue);
    });

    test('Free tier caps at maxHistorySamples (30)', () {
      final history = BpmHistory(const FeatureFlags(isPro: false));
      final now = DateTime.now();

      for (var i = 0; i < 50; i++) {
        history.add(BpmSample(
          bpm: 200.0,
          lockState: LockState.stable,
          timestamp: now, // same timestamp → no duration trimming
        ));
      }

      expect(history.samples.length, 30);
    });

    test('Pro tier caps at maxHistorySamples (86400)', () {
      final history = BpmHistory(const FeatureFlags(isPro: true));
      final now = DateTime.now();

      // Add 100 samples — should not be capped by count for Pro.
      for (var i = 0; i < 100; i++) {
        history.add(BpmSample(
          bpm: 200.0,
          lockState: LockState.stable,
          timestamp: now,
        ));
      }

      expect(history.samples.length, 100);
    });

    test('isAtLimit returns false for empty history', () {
      final history = BpmHistory(const FeatureFlags(isPro: false));
      expect(history.isAtLimit, isFalse);
    });

    test('isAtLimit returns true when maxHistorySamples reached', () {
      final history = BpmHistory(const FeatureFlags(isPro: false));
      final now = DateTime.now();

      for (var i = 0; i < 30; i++) {
        history.add(BpmSample(
          bpm: 200.0,
          lockState: LockState.stable,
          timestamp: now,
        ));
      }

      expect(history.isAtLimit, isTrue);
    });

    test('samples list is immutable', () {
      final history = BpmHistory(const FeatureFlags(isPro: true));
      history.add(BpmSample(
        bpm: 200.0,
        lockState: LockState.stable,
        timestamp: DateTime.now(),
      ));

      expect(
        () => history.samples.add(BpmSample(
          bpm: 180.0,
          lockState: LockState.stable,
          timestamp: DateTime.now(),
        )),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
