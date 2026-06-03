// Tests for AppTabBar widget — Design System v2.
//
// Verifies: 3 tabs render, active=accent, inactive=textMuted, onChanged fires.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:TrackScope/navigation/app_navigator.dart';
import 'package:TrackScope/widgets/app_tab_bar.dart';
import 'package:TrackScope/theme/app_colors.dart';

void main() {
  Widget wrap({
    required AppTab current,
    required ValueChanged<AppTab> onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: AppTabBar(current: current, onChanged: onChanged),
      ),
    );
  }

  group('AppTabBar', () {
    testWidgets('renders 3 tab items', (tester) async {
      await tester.pumpWidget(
        wrap(current: AppTab.radar, onChanged: (_) {}),
      );
      expect(find.text('РАДАР'), findsOneWidget);
      expect(find.text('ИСТОРИЯ'), findsOneWidget);
      expect(find.text('НАСТРОЙКИ'), findsOneWidget);
    });

    testWidgets('active tab label has accent color', (tester) async {
      await tester.pumpWidget(
        wrap(current: AppTab.radar, onChanged: (_) {}),
      );
      final radarText = tester.widget<Text>(find.text('РАДАР'));
      expect(radarText.style?.color, equals(AppColors.accent));
    });

    testWidgets('inactive tab label has textMuted color', (tester) async {
      await tester.pumpWidget(
        wrap(current: AppTab.radar, onChanged: (_) {}),
      );
      final historyText = tester.widget<Text>(find.text('ИСТОРИЯ'));
      expect(historyText.style?.color, equals(AppColors.textMuted));
    });

    testWidgets('tapping a tab calls onChanged with correct AppTab', (tester) async {
      AppTab? tapped;
      await tester.pumpWidget(
        wrap(current: AppTab.radar, onChanged: (t) => tapped = t),
      );
      await tester.tap(find.text('ИСТОРИЯ'));
      await tester.pump();
      expect(tapped, equals(AppTab.history));
    });

    testWidgets('tapping Settings calls onChanged with settings tab', (tester) async {
      AppTab? tapped;
      await tester.pumpWidget(
        wrap(current: AppTab.radar, onChanged: (t) => tapped = t),
      );
      await tester.tap(find.text('НАСТРОЙКИ'));
      await tester.pump();
      expect(tapped, equals(AppTab.settings));
    });

    testWidgets('current tab tapped does not crash', (tester) async {
      AppTab? tapped;
      await tester.pumpWidget(
        wrap(current: AppTab.radar, onChanged: (t) => tapped = t),
      );
      await tester.tap(find.text('РАДАР'));
      await tester.pump();
      expect(tapped, equals(AppTab.radar));
    });
  });
}
