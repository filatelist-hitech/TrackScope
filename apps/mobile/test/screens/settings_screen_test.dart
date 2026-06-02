// Tests for SettingsScreen — Design System v2.
//
// Verifies: section headers render, toggles visible, BPM range by tier,
// reset dialog appears.
// Note: SettingsScreen uses ListView; items below fold are not built
// until scrolled into view.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hitech_bpm_radar/screens/settings_screen.dart';
import 'package:hitech_bpm_radar/monetization/feature_flags.dart';

void main() {
  Widget makeScreen({bool isPro = false}) => MaterialApp(
        home: SettingsScreen(
          flags: FeatureFlags(isPro: isPro),
          onSignalAnalyzerTap: () {},
          onHistoryTap: () {},
          onUpgradeTap: () {},
        ),
      );

  group('SettingsScreen', () {
    testWidgets('АУДИО and ВИЗУАЛИЗАЦИЯ sections render', (tester) async {
      await tester.pumpWidget(makeScreen());
      expect(find.text('АУДИО'), findsOneWidget);
      expect(find.text('ВИЗУАЛИЗАЦИЯ'), findsOneWidget);
    });

    testWidgets('Free tier shows BPM Range 170–230 with PRO badge', (tester) async {
      await tester.pumpWidget(makeScreen(isPro: false));
      expect(find.text('170–230'), findsOneWidget);
      expect(find.text('PRO'), findsAtLeast(1));
    });

    testWidgets('Pro tier shows BPM Range 155–230', (tester) async {
      await tester.pumpWidget(makeScreen(isPro: true));
      expect(find.text('155–230'), findsOneWidget);
    });

    testWidgets('Visualization toggles are rendered', (tester) async {
      await tester.pumpWidget(makeScreen());
      expect(find.text('Волноформа'), findsOneWidget);
      expect(find.text('Спектр'), findsOneWidget);
      expect(find.text('Не гасить экран'), findsOneWidget);
    });

    testWidgets('Анализатор сигнала nav row is rendered (may need scroll)', (tester) async {
      await tester.pumpWidget(makeScreen());
      // Scroll to find PRO-ФУНКЦИИ section
      await tester.scrollUntilVisible(
        find.text('Анализатор сигнала'), 80,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Анализатор сигнала'), findsOneWidget);
    });

    testWidgets('История сессий nav row is rendered', (tester) async {
      await tester.pumpWidget(makeScreen());
      await tester.scrollUntilVisible(
        find.text('История сессий'), 80,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('История сессий'), findsOneWidget);
    });

    testWidgets('Free tier shows Upgrade to Pro link', (tester) async {
      await tester.pumpWidget(makeScreen(isPro: false));
      await tester.scrollUntilVisible(
        find.text('Upgrade to Pro'), 80,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Upgrade to Pro'), findsOneWidget);
    });

    testWidgets('Pro tier does NOT show Upgrade to Pro link', (tester) async {
      await tester.pumpWidget(makeScreen(isPro: true));
      await tester.pump();
      // Fully render the list
      await tester.drag(find.byType(Scrollable), const Offset(0, -600));
      await tester.pump();
      expect(find.text('Upgrade to Pro'), findsNothing);
    });

    testWidgets('tapping Сбросить данные shows confirmation dialog', (tester) async {
      await tester.pumpWidget(makeScreen());
      // Scroll with large step + ensureVisible so element is fully in viewport.
      await tester.scrollUntilVisible(
        find.text('Сбросить данные'), 120,
        scrollable: find.byType(Scrollable),
      );
      await tester.ensureVisible(find.text('Сбросить данные'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сбросить данные'));
      await tester.pumpAndSettle();
      expect(find.text('Сбросить данные?'), findsOneWidget);
    });

    testWidgets('tapping Отмена dismisses dialog', (tester) async {
      await tester.pumpWidget(makeScreen());
      await tester.scrollUntilVisible(
        find.text('Сбросить данные'), 120,
        scrollable: find.byType(Scrollable),
      );
      await tester.ensureVisible(find.text('Сбросить данные'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сбросить данные'));
      await tester.pumpAndSettle();
      // Use byWidgetPredicate to find Отмена in dialog
      final cancelButtons = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Отмена'),
      );
      expect(cancelButtons, findsOneWidget);
      await tester.tap(cancelButtons);
      await tester.pumpAndSettle();
      expect(find.text('Сбросить данные?'), findsNothing);
    });

    testWidgets('PRO-ФУНКЦИИ section header renders (via scroll)', (tester) async {
      await tester.pumpWidget(makeScreen());
      await tester.scrollUntilVisible(
        find.text('PRO-ФУНКЦИИ'), 80,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('PRO-ФУНКЦИИ'), findsOneWidget);
    });
  });
}
