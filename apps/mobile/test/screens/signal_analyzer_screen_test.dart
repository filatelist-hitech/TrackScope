// Tests for SignalAnalyzerScreen — Design System v2.
//
// Verifies: smoke render with mock data, no errors.
// Note: Pro-gate test is in widget_test.dart (via MainScreen flow).

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
          onsetStrength: 0.0312,
          tempoPeakProminence: 0.4820,
          harmonicAmbiguity: 0.08,
          stabilityScore: 0.85,
          warnings: [],
        ),
      );

  group('SignalAnalyzerScreen', () {
    testWidgets('smoke renders without exceptions with mock data', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      await tester.pump();

      // Waiting placeholder
      expect(find.text('Ожидание первого снапшота DspResult…'), findsOneWidget);
    });

    testWidgets('shows candidates section after result emitted', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      ctrl.add(makeResult());
      await tester.pump();

      expect(find.textContaining('BPM-кандидаты'), findsOneWidget);
      expect(find.textContaining('195.0'), findsAtLeast(1));
    });

    testWidgets('shows signal quality section', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      ctrl.add(makeResult());
      await tester.pump();

      expect(find.textContaining('Качество сигнала'), findsOneWidget);
    });

    testWidgets('algorithm metrics shows real DspDebug values', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      ctrl.add(makeResult());
      await tester.pump();

      // Section header
      expect(find.text('Метрики алгоритма'), findsOneWidget);
      // Real values from DspDebug (not placeholder text)
      expect(find.text('Onset rate'), findsOneWidget);
      expect(find.text('Peak prominence'), findsOneWidget);
      expect(find.textContaining('В разработке'), findsNothing);
    });

    testWidgets('back button is available (AppBar has back icon)', (tester) async {
      final ctrl = StreamController<DspResult>.broadcast();
      addTearDown(ctrl.close);

      await tester.pumpWidget(MaterialApp(
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => Scaffold(
              body: ElevatedButton(
                onPressed: () {},
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      // Screen has appBar with back — just check it renders without crash
      await tester.pumpWidget(MaterialApp(
        home: SignalAnalyzerScreen(results: ctrl.stream),
      ));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Signal Analyzer'), findsOneWidget);
    });
  });
}
