// SetlistScreen widget tests.
//
// Smoke render, Pro-gate (Free → PaywallScreen), REC/STOP toggle.

import 'package:flutter/material.dart' hide LockState;
import 'package:flutter_test/flutter_test.dart';
import 'package:hitech_bpm_radar/features/setlist/setlist_screen.dart';
import 'package:hitech_bpm_radar/features/setlist/setlist_service.dart';
import 'package:hitech_bpm_radar/monetization/feature_flags.dart';
import 'package:hitech_bpm_radar/monetization/paywall_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('SetlistScreen Pro-gate', () {
    test('canAccessSetlist Free → false', () {
      const flags = FeatureFlags(isPro: false);
      expect(flags.canAccessSetlist, isFalse);
    });

    test('canAccessSetlist Pro → true', () {
      const flags = FeatureFlags(isPro: true);
      expect(flags.canAccessSetlist, isTrue);
    });

    testWidgets('Free tier shows PaywallScreen', (tester) async {
      final service = SetlistService();
      await tester.pumpWidget(_wrap(SetlistScreen(
        service: service,
        flags: const FeatureFlags(isPro: false),
      )));
      expect(find.byType(PaywallScreen), findsOneWidget);
      service.dispose();
    });

    testWidgets('Pro tier shows СЕТЛИСТ appbar', (tester) async {
      final service = SetlistService();
      await tester.pumpWidget(_wrap(SetlistScreen(
        service: service,
        flags: const FeatureFlags(isPro: true),
      )));
      expect(find.text('СЕТЛИСТ'), findsOneWidget);
      expect(find.byType(PaywallScreen), findsNothing);
      service.dispose();
    });
  });

  group('SetlistScreen REC/STOP', () {
    testWidgets('starts in ОСТАНОВЛЕНО state', (tester) async {
      final service = SetlistService();
      await tester.pumpWidget(_wrap(SetlistScreen(
        service: service,
        flags: const FeatureFlags(isPro: true),
      )));
      expect(find.text('ОСТАНОВЛЕНО'), findsOneWidget);
      expect(find.text('REC'), findsOneWidget);
      service.dispose();
    });

    testWidgets('tap REC switches to ЗАПИСЬ', (tester) async {
      final service = SetlistService();
      await tester.pumpWidget(_wrap(SetlistScreen(
        service: service,
        flags: const FeatureFlags(isPro: true),
      )));
      await tester.tap(find.text('REC'));
      await tester.pump();
      expect(find.text('ЗАПИСЬ'), findsOneWidget);
      expect(find.text('СТОП'), findsOneWidget);
      service.dispose();
    });

    testWidgets('tap СТОП returns to ОСТАНОВЛЕНО', (tester) async {
      final service = SetlistService()..startRecording();
      await tester.pumpWidget(_wrap(SetlistScreen(
        service: service,
        flags: const FeatureFlags(isPro: true),
      )));
      await tester.tap(find.text('СТОП'));
      await tester.pump();
      expect(find.text('ОСТАНОВЛЕНО'), findsOneWidget);
      service.dispose();
    });
  });
}
