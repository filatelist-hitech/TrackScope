// PaywallScreen smoke test — renders v2 comparison table (Design System v2),
// purchase buttons (Lifetime + Annual с 14-day trial), Restore и Roadmap card.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/monetization/paywall_screen.dart';

void main() {
  testWidgets('PaywallScreen renders comparison table (Design v2)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PaywallScreen(feature: 'debug_screen'),
    ));
    await tester.pump();

    // Comparison rows (Design v2, localized).
    expect(find.text('BPM Range'), findsOneWidget);
    expect(find.text('Multi-Genre'), findsOneWidget);
    expect(find.text('Анализатор сигнала'), findsOneWidget);
    expect(find.text('История'), findsWidgets);
    expect(find.text('Setlist Tracker'), findsOneWidget);
    expect(find.text('Export CSV/JSON'), findsOneWidget);

    // Column headers added in Design v2.
    expect(find.text('ФУНКЦИЯ'), findsOneWidget);
    expect(find.text('FREE'), findsWidgets);
    expect(find.text('PRO'), findsWidgets);

    // Value headline.
    expect(find.textContaining('Без ограничений'), findsOneWidget);

    // Roadmap card (coming-soon features).
    expect(find.text('COMING TO PRO'), findsOneWidget);

    // Purchase buttons
    expect(find.textContaining('Lifetime'), findsOneWidget);
    expect(find.textContaining('Annual'), findsOneWidget);

    // 14-day trial badge в Annual кнопке
    expect(find.text('14 дней бесплатно'), findsOneWidget);

    // Restore.
    expect(find.text('Восстановить покупки'), findsOneWidget);
  });

  testWidgets('PaywallScreen shows Upgrade to Pro in title', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PaywallScreen(feature: 'history'),
    ));
    await tester.pump();

    expect(find.text('Upgrade to Pro'), findsOneWidget);
  });

  testWidgets('PaywallScreen v2 multi-genre and setlist rows', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PaywallScreen(feature: 'setlist'),
    ));
    await tester.pump();

    expect(find.text('Setlist Tracker'), findsOneWidget);
    expect(find.text('Multi-Genre'), findsOneWidget);
    expect(find.text('3 жанра'), findsOneWidget);
    expect(find.text('7 + Custom'), findsOneWidget);
  });
}
