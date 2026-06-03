// Smoke tests for CamelotWheelWidget.
//
// Verifies: renders without crash for null and non-null keyResult,
// respects the given size, and wraps with RepaintBoundary.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:TrackScope/dsp/dsp_result.dart';
import 'package:TrackScope/widgets/camelot_wheel_widget.dart';

void main() {
  group('CamelotWheelWidget', () {
    testWidgets('renders without exception when keyResult is null', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: CamelotWheelWidget(keyResult: null),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exception for a valid camelot key', (tester) async {
      const keyResult = KeyResult(
        key: 'A',
        mode: 'Minor',
        camelot: '8A',
        confidence: 0.62,
      );
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: CamelotWheelWidget(keyResult: keyResult, size: 180),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('SizedBox has the specified size', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: CamelotWheelWidget(keyResult: null, size: 120),
        ),
      ));
      final box = tester.renderObject<RenderBox>(find.byType(SizedBox).last);
      expect(box.size.width, closeTo(120, 1));
      expect(box.size.height, closeTo(120, 1));
    });

    testWidgets('contains a RepaintBoundary', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: CamelotWheelWidget(keyResult: null),
        ),
      ));
      expect(find.byType(RepaintBoundary), findsAtLeast(1));
    });
  });
}
