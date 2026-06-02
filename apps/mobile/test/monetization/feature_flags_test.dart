// FeatureFlags unit tests — Free vs Pro gates + genre preset wiring.

import 'package:flutter_test/flutter_test.dart';
import 'package:hitech_bpm_radar/features/genre_preset/genre_preset.dart';
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

    test('canAccessSetlist is false', () {
      expect(flags.canAccessSetlist, isFalse);
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

    test('canAccessSetlist is true', () {
      expect(flags.canAccessSetlist, isTrue);
    });

    test('maxHistoryDuration is 24 hours', () {
      expect(flags.maxHistoryDuration, const Duration(hours: 24));
    });

    test('maxHistorySamples is 86400', () {
      expect(flags.maxHistorySamples, 86400);
    });
  });

  group('Genre preset wiring', () {
    test('Free + psytrance: minBpm uses genre range 130', () {
      const flags = FeatureFlags(isPro: false, selectedGenre: GenrePreset.psytrance);
      expect(flags.minBpm, 130.0);
      expect(flags.maxBpm, 160.0);
    });

    test('Free + darkpsy: minBpm uses genre range 145', () {
      const flags = FeatureFlags(isPro: false, selectedGenre: GenrePreset.darkpsy);
      expect(flags.minBpm, 145.0);
      expect(flags.maxBpm, 180.0);
    });

    test('Free + hitechPsy: minBpm still 170 (tier gate)', () {
      const flags = FeatureFlags(isPro: false, selectedGenre: GenrePreset.hitechPsy);
      expect(flags.minBpm, 170.0);
    });

    test('Pro + psytrance: minBpm 130, maxBpm 160', () {
      const flags = FeatureFlags(isPro: true, selectedGenre: GenrePreset.psytrance);
      expect(flags.minBpm, 130.0);
      expect(flags.maxBpm, 160.0);
    });

    test('Pro + drumAndBass: minBpm 160, maxBpm 185', () {
      const flags = FeatureFlags(isPro: true, selectedGenre: GenrePreset.drumAndBass);
      expect(flags.minBpm, 160.0);
      expect(flags.maxBpm, 185.0);
    });

    test('Free + Pro-only genre falls back to hitechPsy range with tier gate', () {
      const flags = FeatureFlags(isPro: false, selectedGenre: GenrePreset.drumAndBass);
      // Fallback to hitechPsy Free → 170–230
      expect(flags.minBpm, 170.0);
      expect(flags.maxBpm, 230.0);
    });

    test('canAccessGenrePicker is true for both tiers', () {
      expect(const FeatureFlags(isPro: false).canAccessGenrePicker, isTrue);
      expect(const FeatureFlags(isPro: true).canAccessGenrePicker, isTrue);
    });

    test('availablePresets: Free has 3 presets, Pro has 7', () {
      expect(const FeatureFlags(isPro: false).availablePresets.length, 3);
      expect(const FeatureFlags(isPro: true).availablePresets.length, 7);
    });
  });

  group('GenrePreset enum', () {
    test('hitechPsy range is 155–230', () {
      expect(GenrePreset.hitechPsy.bpmRange, (155.0, 230.0));
    });

    test('psytrance range is 130–160', () {
      expect(GenrePreset.psytrance.bpmRange, (130.0, 160.0));
    });

    test('drumAndBass requires Pro', () {
      expect(GenrePreset.drumAndBass.isProRequired, isTrue);
    });

    test('free presets are not Pro-required', () {
      for (final p in GenrePreset.freePresets) {
        expect(p.isProRequired, isFalse, reason: '${p.name} should be free');
      }
    });

    test('freePresets count is 3', () {
      expect(GenrePreset.freePresets.length, 3);
    });

    test('allPresets count is 7', () {
      expect(GenrePreset.allPresets.length, 7);
    });
  });
}
