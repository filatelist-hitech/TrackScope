// FeatureFlags unit tests — Free vs Pro gates.

import 'package:flutter_test/flutter_test.dart';
import 'package:hitech_bpm_radar/monetization/feature_flags.dart';

void main() {
  group('Free tier (isPro: false)', () {
    const flags = FeatureFlags(isPro: false);

    test('minBpm is 170', () {
      expect(flags.minBpm, 170.0);
    });

    test('maxBpm is 230', () {
      expect(flags.maxBpm, 230.0);
    });

    test('canAccessDebugScreen is false', () {
      expect(flags.canAccessDebugScreen, isFalse);
    });

    test('canExport is false', () {
      expect(flags.canExport, isFalse);
    });

    test('canAccessWidget is false', () {
      expect(flags.canAccessWidget, isFalse);
    });

    test('maxHistoryDuration is 30 seconds', () {
      expect(flags.maxHistoryDuration, const Duration(seconds: 30));
    });

    test('maxHistorySamples is 30', () {
      expect(flags.maxHistorySamples, 30);
    });
  });

  group('Pro tier (isPro: true)', () {
    const flags = FeatureFlags(isPro: true);

    test('minBpm is 155', () {
      expect(flags.minBpm, 155.0);
    });

    test('maxBpm is 230', () {
      expect(flags.maxBpm, 230.0);
    });

    test('canAccessDebugScreen is true', () {
      expect(flags.canAccessDebugScreen, isTrue);
    });

    test('canExport is true', () {
      expect(flags.canExport, isTrue);
    });

    test('canAccessWidget is true', () {
      expect(flags.canAccessWidget, isTrue);
    });

    test('maxHistoryDuration is 24 hours', () {
      expect(flags.maxHistoryDuration, const Duration(hours: 24));
    });

    test('maxHistorySamples is 86400', () {
      expect(flags.maxHistorySamples, 86400);
    });
  });
}
