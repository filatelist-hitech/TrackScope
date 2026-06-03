// SetlistScreen widget tests.
//
// Smoke render, Pro-gate (Free → PaywallScreen), REC/STOP toggle,
// Phase 2.4: _EntryRow camelot/energy display.

import 'package:flutter/material.dart' hide LockState;
import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/dsp/dsp_result.dart';
import 'package:TrackScope/features/setlist/setlist_screen.dart';
import 'package:TrackScope/features/setlist/setlist_service.dart';
import 'package:TrackScope/monetization/feature_flags.dart';
import 'package:TrackScope/monetization/paywall_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

DspResult _stableResult({
  double bpm = 200.0,
  KeyResult? keyResult,
  EnergyResult? energyResult,
}) =>
    DspResult(
      primaryBpm: bpm,
      confidence: 0.9,
      lockState: LockState.stable,
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
        analysisTimeSec: 5.0,
        windowTimeSec: 12.0,
        hopTimeSec: 0.0025,
        firstLockTimeSec: 4.2,
      ),
      debug: const DspDebug(
        onsetRateHz: 0.0,
        onsetStrength: 0.0,
        tempoPeakProminence: 0.0,
        harmonicAmbiguity: 0.0,
        stabilityScore: 0.0,
        warnings: [],
      ),
      keyResult: keyResult,
      energyResult: energyResult,
    );

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

  // Phase 2.4: _EntryRow camelot/energy display

  group('_EntryRow camelot and energy display', () {
    testWidgets('shows camelot key when entry.camelotKey != null',
        (tester) async {
      final service = SetlistService()..startRecording();
      service.onDspResult(_stableResult(
        keyResult: const KeyResult(
          key: 'A',
          mode: 'Minor',
          camelot: '8A',
          confidence: 0.72,
        ),
      ));
      await tester.pumpWidget(_wrap(SetlistScreen(
        service: service,
        flags: const FeatureFlags(isPro: true),
      )));
      expect(find.text('8A'), findsOneWidget);
      service.dispose();
    });

    testWidgets('shows energy level when entry.energyLevel != null',
        (tester) async {
      final service = SetlistService()..startRecording();
      service.onDspResult(_stableResult(
        energyResult: const EnergyResult(
          level: 7,
          rmsDbfs: -8.0,
          spectralFlux: 0.05,
          onsetDensityHz: 3.5,
        ),
      ));
      await tester.pumpWidget(_wrap(SetlistScreen(
        service: service,
        flags: const FeatureFlags(isPro: true),
      )));
      expect(find.text('E7'), findsOneWidget);
      service.dispose();
    });

    testWidgets('renders entry without camelot and energy when both null',
        (tester) async {
      final service = SetlistService()..startRecording();
      service.onDspResult(_stableResult());
      await tester.pumpWidget(_wrap(SetlistScreen(
        service: service,
        flags: const FeatureFlags(isPro: true),
      )));
      // BPM is shown
      expect(find.text('200.0'), findsOneWidget);
      // No camelot or energy chip rendered
      expect(find.textContaining(RegExp(r'^\d+[AB]$')), findsNothing);
      expect(find.textContaining(RegExp(r'^E\d+$')), findsNothing);
      service.dispose();
    });
  });
}
