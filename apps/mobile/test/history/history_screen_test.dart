// Smoke tests for redesigned HistoryScreen (session-based, Design System v2).

import 'package:flutter/material.dart' hide LockState;
import 'package:flutter_test/flutter_test.dart';

import 'package:TrackScope/dsp/dsp_result.dart';
import 'package:TrackScope/history/history_screen.dart';
import 'package:TrackScope/history/session.dart';
import 'package:TrackScope/history/session_history_controller.dart';
import 'package:TrackScope/monetization/feature_flags.dart';

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

void _addSnapshot(SessionHistoryController ctrl, double bpm,
    {double confidence = 0.8, LockState lockState = LockState.stable}) {
  ctrl.currentSession.snapshots.add(SessionSnapshot(
    timestamp: DateTime.now(),
    bpm: bpm,
    confidence: confidence,
    lockState: lockState,
  ));
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

  testWidgets('summary header shows СЕССИЙ stat', (tester) async {
    final ctrl = emptyController(proFlags);
    addTearDown(ctrl.dispose);
    _addSnapshot(ctrl, 193.0);

    await tester.pumpWidget(buildScreen(ctrl, proFlags));
    await tester.pump();

    expect(find.text('СЕССИЙ'), findsOneWidget);
    expect(find.text('AVG BPM'), findsOneWidget);
    expect(find.text('ПЕРИОД'), findsOneWidget);
    // 1 session (current) with data
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('session card appears with BPM range', (tester) async {
    final ctrl = emptyController(proFlags);
    addTearDown(ctrl.dispose);
    _addSnapshot(ctrl, 180.0);
    _addSnapshot(ctrl, 200.0);

    await tester.pumpWidget(buildScreen(ctrl, proFlags));
    await tester.pump();

    // BPM range shown in session card
    expect(find.textContaining('180'), findsWidgets);
    expect(find.textContaining('200'), findsWidgets);
  });

  testWidgets('empty session not shown in list', (tester) async {
    final ctrl = emptyController(proFlags);
    addTearDown(ctrl.dispose);
    // No snapshots added

    await tester.pumpWidget(buildScreen(ctrl, proFlags));
    await tester.pump();

    expect(find.text('История пуста'), findsOneWidget);
  });

  testWidgets('export button visible for Pro tier', (tester) async {
    final ctrl = emptyController(proFlags);
    addTearDown(ctrl.dispose);
    _addSnapshot(ctrl, 195.0);

    await tester.pumpWidget(buildScreen(ctrl, proFlags));
    await tester.pump();

    expect(find.text('Экспорт'), findsOneWidget);
  });

  testWidgets('session card shows snapshot count', (tester) async {
    final ctrl = emptyController(proFlags);
    addTearDown(ctrl.dispose);
    _addSnapshot(ctrl, 190.0);
    _addSnapshot(ctrl, 195.0);
    _addSnapshot(ctrl, 200.0);

    await tester.pumpWidget(buildScreen(ctrl, proFlags));
    await tester.pump();

    expect(find.text('3'), findsWidgets);
    expect(find.text('снимков'), findsOneWidget);
  });

  testWidgets('session card shows peak confidence', (tester) async {
    final ctrl = emptyController(proFlags);
    addTearDown(ctrl.dispose);
    _addSnapshot(ctrl, 200.0, confidence: 0.92);

    await tester.pumpWidget(buildScreen(ctrl, proFlags));
    await tester.pump();

    expect(find.textContaining('92%'), findsOneWidget);
  });
}
