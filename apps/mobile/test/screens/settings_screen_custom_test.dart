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
  });
}
