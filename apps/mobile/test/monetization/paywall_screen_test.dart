// PaywallScreen smoke test — renders v2 comparison table (10 rows),
// purchase buttons (Lifetime + Annual с 14-day trial), и Restore.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitech_bpm_radar/monetization/paywall_screen.dart';

void main() {
  testWidgets('PaywallScreen renders all 10 comparison rows',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PaywallScreen(feature: 'debug_screen'),
    ));
    await tester.pump();

    // Все 10 строк таблицы сравнения
    expect(find.text('BPM Range'), findsOneWidget);
    expect(find.text('Multi-Genre'), findsOneWidget);
    expect(find.text('Debug Screen'), findsOneWidget);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Setlist Tracker'), findsOneWidget);
    expect(find.text('Export CSV/JSON'), findsOneWidget);
    expect(find.text('Key + Camelot'), findsOneWidget);
    expect(find.text('Energy Level'), findsOneWidget);
    expect(find.text('Apple Watch'), findsOneWidget);
    expect(find.text('Lock-screen Widget'), findsOneWidget);

    // 4 «Скоро» строки (Key, Energy, Watch, Widget)
    expect(find.text('Скоро'), findsNWidgets(4));

    // Purchase buttons
    expect(find.textContaining('Lifetime'), findsOneWidget);
    expect(find.textContaining('Annual'), findsOneWidget);

    // 14-day trial badge в Annual кнопке
    expect(find.text('14 дней бесплатно'), findsOneWidget);

    // Restore
    expect(find.text('Restore purchases'), findsOneWidget);
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
