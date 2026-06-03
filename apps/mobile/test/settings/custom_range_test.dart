// Tests for AppSettings custom BPM range (customMin, customMax, setCustomRange,
// effectiveBpmRange). SharedPreferences writes are not tested here — only the
// in-memory validation logic and field values, which are synchronously updated.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:TrackScope/features/genre_preset/genre_preset.dart';
import 'package:TrackScope/settings/app_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Reset instance state before each test.
    AppSettings.instance
      ..customMin = 155.0
      ..customMax = 230.0
      ..selectedGenre = GenrePreset.hitechPsy;
  });

  group('AppSettings custom range defaults', () {
    test('customMin defaults to 155.0', () {
      expect(AppSettings.instance.customMin, 155.0);
    });

    test('customMax defaults to 230.0', () {
      expect(AppSettings.instance.customMax, 230.0);
    });
  });

  group('AppSettings.setCustomRange validation', () {
    test('valid range updates customMin and customMax', () async {
      await AppSettings.instance.setCustomRange(160.0, 220.0);
      expect(AppSettings.instance.customMin, 160.0);
      expect(AppSettings.instance.customMax, 220.0);
    });

    test('min == max is rejected (no-op)', () async {
      await AppSettings.instance.setCustomRange(200.0, 200.0);
      expect(AppSettings.instance.customMin, 155.0); // unchanged
      expect(AppSettings.instance.customMax, 230.0); // unchanged
    });

    test('min > max is rejected (no-op)', () async {
      await AppSettings.instance.setCustomRange(220.0, 180.0);
      expect(AppSettings.instance.customMin, 155.0);
      expect(AppSettings.instance.customMax, 230.0);
    });

    test('min < 80 is rejected (no-op)', () async {
      await AppSettings.instance.setCustomRange(70.0, 200.0);
      expect(AppSettings.instance.customMin, 155.0);
      expect(AppSettings.instance.customMax, 230.0);
    });

    test('max > 300 is rejected (no-op)', () async {
      await AppSettings.instance.setCustomRange(155.0, 310.0);
      expect(AppSettings.instance.customMin, 155.0);
      expect(AppSettings.instance.customMax, 230.0);
    });

    test('exactly min=80, max=300 is accepted', () async {
      await AppSettings.instance.setCustomRange(80.0, 300.0);
      expect(AppSettings.instance.customMin, 80.0);
      expect(AppSettings.instance.customMax, 300.0);
    });
  });

  group('AppSettings.effectiveBpmRange', () {
    test('returns customMin/customMax when selectedGenre == custom', () async {
      await AppSettings.instance.setCustomRange(170.0, 210.0);
      AppSettings.instance.selectedGenre = GenrePreset.custom;
      final (min, max) = AppSettings.instance.effectiveBpmRange;
      expect(min, 170.0);
      expect(max, 210.0);
    });

    test('returns preset bpmRange for non-custom genres', () {
      AppSettings.instance.selectedGenre = GenrePreset.psytrance;
      final (min, max) = AppSettings.instance.effectiveBpmRange;
      expect(min, 130.0);
      expect(max, 160.0);
    });

    test('hitechPsy effectiveBpmRange is (155, 230)', () {
      AppSettings.instance.selectedGenre = GenrePreset.hitechPsy;
      expect(AppSettings.instance.effectiveBpmRange, (155.0, 230.0));
    });
  });
}
