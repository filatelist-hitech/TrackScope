// Tests for ConfidenceBar widget — Design System v2.
//
// Verifies: 7 px height, red < 30 %, yellow 30–70 %, teal > 70 %.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:TrackScope/widgets/confidence_bar.dart';
import 'package:TrackScope/theme/app_colors.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, child: child),
        ),
      );

  group('ConfidenceBar', () {
    testWidgets('renders without errors at 0 confidence', (tester) async {
      await tester.pumpWidget(wrap(const ConfidenceBar(confidence: 0.0)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without errors at 1.0 confidence', (tester) async {
      await tester.pumpWidget(wrap(const ConfidenceBar(confidence: 1.0)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows percentage text at 10% → red color', (tester) async {
      await tester.pumpWidget(wrap(const ConfidenceBar(confidence: 0.10)));
      await tester.pump();
      // Text shows "10%"
      expect(find.text('10%'), findsOneWidget);
      // Color should be danger (red) for < 30 %
      final textWidget = tester.widget<Text>(find.text('10%'));
      expect(textWidget.style?.color, equals(AppColors.danger));
    });

    testWidgets('shows 50% → yellow color', (tester) async {
      await tester.pumpWidget(wrap(const ConfidenceBar(confidence: 0.50)));
      await tester.pump();
      expect(find.text('50%'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('50%'));
      expect(textWidget.style?.color, equals(AppColors.yellow));
    });

    testWidgets('shows 80% → accent (teal) color', (tester) async {
      await tester.pumpWidget(wrap(const ConfidenceBar(confidence: 0.80)));
      await tester.pump();
      expect(find.text('80%'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('80%'));
      expect(textWidget.style?.color, equals(AppColors.accent));
    });

    testWidgets('confidence bar track is 7 px tall', (tester) async {
      await tester.pumpWidget(wrap(const ConfidenceBar(confidence: 0.5)));
      // Find the SizedBox that sets the bar height to 7.
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final barBox = sizedBoxes.firstWhere(
        (sb) => sb.height == 7,
        orElse: () => throw TestFailure('No SizedBox with height=7 found'),
      );
      expect(barBox.height, 7.0);
    });

    testWidgets('confidence > 1.0 clamped to 100%', (tester) async {
      await tester.pumpWidget(wrap(const ConfidenceBar(confidence: 1.5)));
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('confidence < 0.0 clamped to 0%', (tester) async {
      await tester.pumpWidget(wrap(const ConfidenceBar(confidence: -0.5)));
      expect(find.text('0%'), findsOneWidget);
    });
  });
}
