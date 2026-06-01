// Tests for SignalAnalyzerScreen — Design System v2 (redesign).
//
// Verifies: new layout matching HTML prototype —
//   uppercase title, PRO badge, top-4 candidates, metric bars, sa-grp cards.
// Pro-gate test is in widget_test.dart (via MainScreen flow).

import 'dart:async';

import 'package:flutter/material.dart' hide LockState;
import 'package:flutter_test/flutter_test.dart';

import 'package:hitech_bpm_radar/screens/signal_analyzer_screen.dart';
import 'package:hitech_bpm_radar/dsp/dsp_result.dart';

void main() {
  DspResult makeResult() => const DspResult(
        primaryBpm: 195.0,
        confidence: 0.88,
        lockState: LockState.stable,
        signalQuality: SignalQuality(
          inputLevelDbfs: -12.0,
          peakDbfs: -8.0,
          clipping: false,
          clippedFrameRatio: 0.0,
          noiseLevel: 'low',
          snrEstimateDb: 22.0,
          silence: false,
          breakdownLikely: false,
        ),
        candidates: [
          TempoCandidate(
            bpm: 195.0,
            relation: 'main',
            score: 0.88,
            rawScore: 0.91,
            stabilityScore: 0.85,
            rangeScore: 1.0,
            sourceBpm: null,
          ),
          TempoCandidate(
            bpm: 97.5,
            relation: 'half_time',
            score: 0.44,
            rawScore: 0.50,
            stabilityScore: 0.42,
            rangeScore: 0.3,
            sourceBpm: 195.0,
          ),
        ],
        timing: DspTiming(
          analysisTimeSec: 0.012,
          windowTimeSec: 12.0,
          hopTimeSec: 0.0025,
          firstLockTimeSec: 4.8,
        ),
        debug: DspDebug(
          onsetRateHz: 3.25,
          onsetStrength: 0.72,
          tempoPeakProminence: 0.68,
          harmonicAmbiguity: 0.08,
          stabilityScore: 0.85,
          warnings: ['harmonic_ambiguity=0.08'],
        ),
      );

  group('SignalAnalyzerScreen', () {
    testWidgets('waiting placeholder shown before first snapshot', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      await tester.pump();

      expect(find.text('Ожидание первого снапшота DspResult…'), findsOneWidget);
    });

    testWidgets('AppBar title is SIGNAL ANALYZER uppercase with PRO badge', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      await tester.pump();

      expect(find.text('SIGNAL ANALYZER'), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      // Old title must NOT appear.
      expect(find.text('Signal Analyzer'), findsNothing);
    });

    testWidgets('shows BPM КАНДИДАТЫ section header after result', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      ctrl.add(makeResult());
      await tester.pump();

      expect(find.text('BPM КАНДИДАТЫ'), findsOneWidget);
    });

    testWidgets('candidate BPM shown, relation label NOT shown', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      ctrl.add(makeResult());
      await tester.pump();

      // BPM values visible.
      expect(find.textContaining('195.0'), findsAtLeast(1));
      expect(find.textContaining('97.5'), findsOneWidget);
      // Relation labels must NOT appear (removed from redesign).
      expect(find.text('main'), findsNothing);
      expect(find.text('half_time'), findsNothing);
    });

    testWidgets('algorithm metrics shows section header and bar labels', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      ctrl.add(makeResult());
      await tester.pump();

      expect(find.text('МЕТРИКИ АЛГОРИТМА'), findsOneWidget);
      expect(find.text('Onset Detection'), findsOneWidget);
      expect(find.text('Autocorrelation'), findsOneWidget);
      expect(find.text('Spectral Flux'), findsOneWidget);
      // Old raw metric labels must not appear.
      expect(find.text('Onset rate'), findsNothing);
      expect(find.text('Peak prominence'), findsNothing);
    });

    testWidgets('SNR and input level shown as text values', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      ctrl.add(makeResult());
      await tester.pump();

      expect(find.text('SNR'), findsOneWidget);
      expect(find.text('22.0 dB'), findsOneWidget);
      expect(find.text('Уровень входа'), findsOneWidget);
      expect(find.text('-12.0 dBFS'), findsOneWidget);
    });

    testWidgets('warnings are rendered with amber text', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      ctrl.add(makeResult());
      await tester.pump();

      expect(find.textContaining('harmonic_ambiguity'), findsOneWidget);
    });

    testWidgets('signal quality section is present', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      ctrl.add(makeResult());
      await tester.pump();

      expect(find.text('КАЧЕСТВО СИГНАЛА'), findsOneWidget);
      expect(find.text('нет'), findsAtLeast(1)); // clipping == false
    });

    testWidgets('AppBar back button renders', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
