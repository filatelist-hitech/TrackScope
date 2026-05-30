// PaywallScreen smoke test — renders comparison table, purchase buttons,
// restore, and "Скоро" widget tile.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitech_bpm_radar/monetization/paywall_screen.dart';

void main() {
  testWidgets('PaywallScreen renders comparison table and buttons',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PaywallScreen(feature: 'debug_screen'),
    ));
    await tester.pump();

    // Comparison rows.
    expect(find.text('BPM Range'), findsOneWidget);
    expect(find.text('Debug Screen'), findsOneWidget);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Export CSV/JSON'), findsOneWidget);
    expect(find.text('Lock-screen Widget'), findsWidgets);

    // Purchase buttons.
    expect(find.textContaining('Lifetime'), findsOneWidget);
    expect(find.textContaining('Annual'), findsOneWidget);

    // Restore.
    expect(find.text('Restore purchases'), findsOneWidget);

    // "Скоро" widget tile.
    expect(find.textContaining('Скоро'), findsWidgets);
  });

  testWidgets('PaywallScreen shows feature name in title', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PaywallScreen(feature: 'history'),
    ));
    await tester.pump();

    expect(find.text('Upgrade to Pro'), findsOneWidget);
  });
}
