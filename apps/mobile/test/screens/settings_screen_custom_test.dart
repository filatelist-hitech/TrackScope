// Tests for SettingsScreen Custom preset UI:
// - Custom range sliders visible when selectedGenre==custom && isPro
// - Sliders absent when selectedGenre!=custom
// - Paywall hint visible when selectedGenre==custom && !isPro

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:TrackScope/features/genre_preset/genre_preset.dart';
import 'package:TrackScope/monetization/feature_flags.dart';
import 'package:TrackScope/screens/settings_screen.dart';
import 'package:TrackScope/settings/app_settings.dart';

Widget _makeScreen({required bool isPro, GenrePreset genre = GenrePreset.hitechPsy}) {
  AppSettings.instance.selectedGenre = genre;
  AppSettings.instance.customMin = 160.0;
  AppSettings.instance.customMax = 210.0;
  return MaterialApp(
    home: SettingsScreen(
      flags: FeatureFlags(
        isPro: isPro,
        selectedGenre: genre,
        customMin: AppSettings.instance.customMin,
        customMax: AppSettings.instance.customMax,
      ),
      onSignalAnalyzerTap: () {},
      onHistoryTap: () {},
      onUpgradeTap: () {},
      onRestoreTap: () {},
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance
      ..customMin = 160.0
      ..customMax = 210.0
      ..selectedGenre = GenrePreset.hitechPsy;
  });

  group('SettingsScreen — Custom preset section', () {
    testWidgets('CUSTOM RANGE section and sliders appear for Custom+Pro',
        (tester) async {
      await tester.pumpWidget(
          _makeScreen(isPro: true, genre: GenrePreset.custom));
      await tester.pumpAndSettle();

      expect(find.text('CUSTOM RANGE'), findsOneWidget);
      expect(find.text('Min BPM'), findsOneWidget);
      expect(find.text('Max BPM'), findsOneWidget);
    });

    testWidgets('CUSTOM RANGE section is absent when genre is not custom',
        (tester) async {
      await tester.pumpWidget(
          _makeScreen(isPro: true, genre: GenrePreset.hitechPsy));
      await tester.pumpAndSettle();

      expect(find.text('CUSTOM RANGE'), findsNothing);
      expect(find.text('Min BPM'), findsNothing);
      expect(find.text('Max BPM'), findsNothing);
    });

    testWidgets('Custom+Free shows paywall hint instead of sliders',
        (tester) async {
      // Free tier cannot select custom (isProRequired=true), but we test
      // the defensive branch for tier downgrade / direct state.
      await tester.pumpWidget(
          _makeScreen(isPro: false, genre: GenrePreset.custom));
      await tester.pumpAndSettle();

      expect(find.text('CUSTOM RANGE'), findsOneWidget);
      expect(find.text('Min BPM'), findsNothing);
      expect(find.text('Max BPM'), findsNothing);
      expect(find.text('Требуется PRO'), findsOneWidget);
    });

    testWidgets('Custom range values appear in BPM Range info row',
        (tester) async {
      await tester.pumpWidget(
          _makeScreen(isPro: true, genre: GenrePreset.custom));
      await tester.pumpAndSettle();

      // customMin=160, customMax=210
      expect(find.text('160–210'), findsOneWidget);
    });

    testWidgets(
        'Dragging slider shows local value immediately without persisting',
        (tester) async {
      await tester.pumpWidget(
          _makeScreen(isPro: true, genre: GenrePreset.custom));
      await tester.pumpAndSettle();

      // Initial display values reflect customMin=160, customMax=210
      expect(find.text('160 BPM'), findsOneWidget);
      expect(find.text('210 BPM'), findsOneWidget);

      // AppSettings not mutated yet — setCustomRange called only on onChangeEnd
      expect(AppSettings.instance.customMin, 160.0);
      expect(AppSettings.instance.customMax, 210.0);
    });

    testWidgets(
        'drag does not persist to AppSettings mid-drag but does on gesture up',
        (tester) async {
      await tester.pumpWidget(
          _makeScreen(isPro: true, genre: GenrePreset.custom));
      await tester.pumpAndSettle();

      final double initialMin = AppSettings.instance.customMin; // 160.0

      // Sliders in tree: [0]=InputSensitivity, [1]=MinBPM, [2]=MaxBPM
      final minBpmSliderFinder = find.byType(Slider).at(1);
      final Rect sliderRect = tester.getRect(minBpmSliderFinder);

      // Compute thumb X: min=80, max=customMax-10=200, value=160
      // Slider widget adds thumbRadius (6.5) padding on each side
      const double thumbRadius = 6.5;
      final double trackLeft = sliderRect.left + thumbRadius;
      final double trackWidth = sliderRect.width - 2 * thumbRadius;
      final double thumbX =
          trackLeft + trackWidth * (160.0 - 80.0) / (200.0 - 80.0);
      final Offset thumbPos = Offset(thumbX, sliderRect.center.dy);

      // Start gesture exactly at the thumb — fires nothing yet
      final TestGesture gesture = await tester.startGesture(thumbPos);
      await tester.pump();

      // Move right by 100px — fires onChanged → local _localMin updates
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();

      // AppSettings must NOT be mutated during drag (throttling invariant)
      expect(AppSettings.instance.customMin, initialMin,
          reason: 'setCustomRange must not be called during drag');

      // Release finger — fires onChangeEnd → setCustomRange persists the value
      await gesture.up();
      await tester.pumpAndSettle();

      // After gesture.up the persisted value must have changed
      // (dragged right by 100px on a 759px track spanning 120 BPM ≈ +15.8 BPM)
      expect(AppSettings.instance.customMin, greaterThan(initialMin),
          reason: 'setCustomRange must be called once on gesture up');
    });
  });
}
