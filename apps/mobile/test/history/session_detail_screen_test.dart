// Smoke tests for SessionDetailScreen.

import 'package:flutter/material.dart' hide LockState;
import 'package:flutter_test/flutter_test.dart';

import 'package:TrackScope/dsp/dsp_result.dart';
import 'package:TrackScope/history/session.dart';
import 'package:TrackScope/history/session_detail_screen.dart';

Session _makeSession({int snapCount = 3}) {
  final snaps = List.generate(
    snapCount,
    (i) => SessionSnapshot(
      timestamp: DateTime(2026, 6, 4, 14, i * 5, 0),
      bpm: 180.0 + i * 5.0,
      confidence: 0.8 + i * 0.03,
      lockState: LockState.stable,
    ),
  );
  return Session(
    id: 'test-session',
    startTime: DateTime(2026, 6, 4, 14, 0, 0),
    endTime: DateTime(2026, 6, 4, 14, 13, 0),
    snapshots: snaps,
  );
}

void main() {
  testWidgets('renders without error for session with snapshots', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SessionDetailScreen(session: _makeSession()),
    ));
    await tester.pump();
    // stats bar appears
    expect(find.text('ДЛИТ'), findsOneWidget);
    expect(find.text('BPM'), findsAtLeast(1));
    expect(find.text('СНИМКОВ'), findsOneWidget);
  });

  testWidgets('shows correct snapshot count', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SessionDetailScreen(session: _makeSession(snapCount: 4)),
    ));
    await tester.pump();
    expect(find.text('4'), findsAtLeast(1));
  });

  testWidgets('shows BPM range', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SessionDetailScreen(session: _makeSession()),
    ));
    await tester.pump();
    // minBpm=180, maxBpm=190 → "180–190" in stats bar
    expect(find.textContaining('180'), findsAtLeast(1));
    expect(find.textContaining('190'), findsAtLeast(1));
  });

  testWidgets('empty session shows Нет данных', (tester) async {
    final emptySession = Session(
      id: 'empty',
      startTime: DateTime(2026, 6, 4, 12, 0, 0),
    );
    await tester.pumpWidget(MaterialApp(
      home: SessionDetailScreen(session: emptySession),
    ));
    await tester.pump();
    expect(find.text('Нет данных'), findsOneWidget);
  });

  testWidgets('back button navigates pop', (tester) async {
    bool popped = false;
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => SessionDetailScreen(session: _makeSession()),
        ),
        observers: [
          _PopObserver(() => popped = true),
        ],
      ),
    ));
    await tester.pump();
    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();
    expect(popped, isTrue);
  });
}

class _PopObserver extends NavigatorObserver {
  _PopObserver(this.onPop);
  final VoidCallback onPop;

  @override
  void didPop(Route route, Route? previousRoute) => onPop();
}
