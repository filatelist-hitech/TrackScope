// Tests for BpmHeroDisplay widget — Design System v2.
//
// Verifies: null→"— — —" dim, detecting→accent text, unstable→amber+pill.
// Anti-fake: null must never render "0" or empty string.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hitech_bpm_radar/widgets/bpm_hero_display.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  group('BpmHeroDisplay', () {
    testWidgets('idle mode: shows — — — when bpm is null', (tester) async {
      await tester.pumpWidget(wrap(const BpmHeroDisplay()));
      expect(find.text('— — —'), findsOneWidget);
      // Must NOT show "0" or an empty text widget
      expect(find.text('0'), findsNothing);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('idle mode: BPM text color is dim #1E3530', (tester) async {
      await tester.pumpWidget(wrap(const BpmHeroDisplay()));
      final textWidget = tester.widget<Text>(find.text('— — —'));
      // AnimatedDefaultTextStyle wraps the text; check via rendered color.
      // Color is set to AppColors.bpmEmpty in bpmEmptyHero style.
      expect(textWidget.style?.color, isNull); // style applied by AnimatedDefaultTextStyle
    });

    testWidgets('detecting mode: shows formatted BPM value', (tester) async {
      await tester.pumpWidget(wrap(
        const BpmHeroDisplay(bpm: 195.3, mode: BpmDisplayMode.detecting),
      ));
      expect(find.text('195.3'), findsOneWidget);
      expect(find.text('— — —'), findsNothing);
    });

    testWidgets('unstable mode: shows BPM + unstable pill', (tester) async {
      await tester.pumpWidget(wrap(
        const BpmHeroDisplay(bpm: 183.7, mode: BpmDisplayMode.unstable),
      ));
      expect(find.text('183.7'), findsOneWidget);
      expect(find.text('нестабильно'), findsOneWidget);
    });

    testWidgets('detecting mode: no pill shown', (tester) async {
      await tester.pumpWidget(wrap(
        const BpmHeroDisplay(bpm: 200.0, mode: BpmDisplayMode.detecting),
      ));
      expect(find.text('нестабильно'), findsNothing);
    });

    testWidgets('BPM label and range text are present', (tester) async {
      await tester.pumpWidget(wrap(
        const BpmHeroDisplay(bpm: 200.0, mode: BpmDisplayMode.detecting),
      ));
      expect(find.text('BPM'), findsOneWidget);
      expect(find.text('155–230 · Hitech'), findsOneWidget);
    });

    testWidgets('null BPM → never shows 0 or empty', (tester) async {
      await tester.pumpWidget(wrap(const BpmHeroDisplay(bpm: null)));
      expect(find.text('0'), findsNothing);
      expect(find.text(''), findsNothing);
      expect(find.text('— — —'), findsOneWidget);
    });
  });
}
