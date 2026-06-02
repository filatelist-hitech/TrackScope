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

    // Comparison rows (Design v2, localized).
    expect(find.text('BPM Range'), findsOneWidget);
    expect(find.text('Анализатор сигнала'), findsOneWidget);
    expect(find.text('История'), findsWidgets);
    expect(find.text('Export CSV/JSON'), findsOneWidget);

    // Column headers added in Design v2.
    expect(find.text('ФУНКЦИЯ'), findsOneWidget);
    expect(find.text('FREE'), findsWidgets);
    expect(find.text('PRO'), findsWidgets);

    // Value headline.
    expect(find.textContaining('Без ограничений'), findsOneWidget);

    // Purchase buttons.
    expect(find.textContaining('Lifetime'), findsOneWidget);
    expect(find.textContaining('Annual'), findsOneWidget);

    // Restore.
    expect(find.text('Восстановить покупки'), findsOneWidget);

    // Roadmap card (replaces widget tile).
    expect(find.text('COMING TO PRO'), findsOneWidget);
  });

  testWidgets('PaywallScreen shows feature name in title', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PaywallScreen(feature: 'history'),
    ));
    await tester.pump();

    expect(find.text('Upgrade to Pro'), findsOneWidget);
  });
}
