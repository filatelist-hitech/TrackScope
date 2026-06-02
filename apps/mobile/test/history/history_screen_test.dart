// Smoke tests for redesigned HistoryScreen (Design System v2).
//
// Verifies: summary header, day grouping, BPM item styling,
// empty state, AppColors tokens (no AppTheme).

import 'package:flutter/material.dart' hide LockState;
import 'package:flutter_test/flutter_test.dart';

import 'package:hitech_bpm_radar/dsp/dsp_result.dart';
import 'package:hitech_bpm_radar/history/bpm_history.dart';
import 'package:hitech_bpm_radar/history/history_screen.dart';
import 'package:hitech_bpm_radar/history/session_history_controller.dart';
import 'package:hitech_bpm_radar/monetization/feature_flags.dart';

/// Builds a HistoryScreen inside MaterialApp with the given controller.
Widget buildScreen(SessionHistoryController ctrl, FeatureFlags flags) {
  return MaterialApp(
    home: HistoryScreen(
      controller: ctrl,
      flags: flags,
      onExportCsv: () {},
      onExportJson: () {},
    ),
  );
}

SessionHistoryController emptyController(FeatureFlags flags) {
  return SessionHistoryController(
    flags: flags,
    resultsStream: const Stream.empty(),
  );
}

void main() {
  final proFlags = const FeatureFlags(isPro: true);

  testWidgets('empty state renders without errors', (tester) async {
    final ctrl = emptyController(proFlags);
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(buildScreen(ctrl, proFlags));
    await tester.pump();
    expect(find.text('История пуста'), findsOneWidget);
  });

  testWidgets('summary header shows stats cells', (tester) async {
    final ctrl = emptyController(proFlags);
    addTearDown(ctrl.dispose);
    // Add some samples manually via history
    ctrl.history.add(BpmSample(
      bpm: 193.0,
      lockState: LockState.stable,
      timestamp: DateTime.now(),
      confidence: 0.88,
    ));
    ctrl.history.add(BpmSample(
      bpm: 187.0,
      lockState: LockState.stable,
      timestamp: DateTime.now(),
      confidence: 0.72,
    ));

    await tester.pumpWidget(buildScreen(ctrl, proFlags));
    await tester.pump();

    // Summary labels
    expect(find.text('СЭМПЛОВ'), findsOneWidget);
    expect(find.text('AVG BPM'), findsOneWidget);
    expect(find.text('ПЕРИОД'), findsOneWidget);
    // Sample count displayed
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('history item shows BPM value', (tester) async {
    final ctrl = emptyController(proFlags);
    addTearDown(ctrl.dispose);
    ctrl.history.add(BpmSample(
      bpm: 196.4,
      lockState: LockState.stable,
      timestamp: DateTime.now(),
      confidence: 0.85,
    ));

    await tester.pumpWidget(buildScreen(ctrl, proFlags));
    await tester.pump();

    // BPM appears in history row AND as avg in summary header
    expect(find.text('196.4'), findsAtLeast(1));
  });

  testWidgets('day group label СЕГОДНЯ appears for today samples', (tester) async {
    final ctrl = emptyController(proFlags);
    addTearDown(ctrl.dispose);
    ctrl.history.add(BpmSample(
      bpm: 200.0,
      lockState: LockState.stable,
      timestamp: DateTime.now(),
      confidence: 0.9,
    ));

    await tester.pumpWidget(buildScreen(ctrl, proFlags));
    await tester.pump();

    expect(find.text('СЕГОДНЯ'), findsOneWidget);
  });

  testWidgets('export button visible for Pro tier', (tester) async {
    final ctrl = emptyController(proFlags);
    addTearDown(ctrl.dispose);
    ctrl.history.add(BpmSample(
      bpm: 195.0,
      lockState: LockState.stable,
      timestamp: DateTime.now(),
      confidence: 0.8,
    ));

    await tester.pumpWidget(buildScreen(ctrl, proFlags));
    await tester.pump();

    expect(find.text('Экспорт'), findsOneWidget);
  });

  testWidgets('Free tier limit banner shown when at limit', (tester) async {
    final freeFlags = const FeatureFlags(isPro: false);
    final ctrl = emptyController(freeFlags);
    addTearDown(ctrl.dispose);

    // Fill up to limit
    for (int i = 0; i < freeFlags.maxHistorySamples; i++) {
      ctrl.history.add(BpmSample(
        bpm: 190.0 + i,
        lockState: LockState.stable,
        timestamp: DateTime.now().subtract(Duration(seconds: i)),
        confidence: 0.7,
      ));
    }

    await tester.pumpWidget(buildScreen(ctrl, freeFlags));
    await tester.pump();

    expect(find.textContaining('Upgrade'), findsOneWidget);
  });
}
