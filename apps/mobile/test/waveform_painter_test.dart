// Smoke tests for WaveformColumnPainter (Phase 8.2).
//
// The painter is a CustomPainter that renders band-split energy bars. It is the
// only public visual surface that takes a typed input list, so it is unit-testable
// directly (unlike the private widgets inside main_screen.dart, which are exercised
// through MainScreen in widget_test.dart). These tests assert the painter never
// throws — empty buffer (production guards this upstream, but the painter must be
// safe) and a full mock buffer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/viz/waveform_column.dart';
import 'package:TrackScope/viz/waveform_painter.dart';

Widget _paint(List<WaveformColumn> columns) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 375,
          height: 100,
          child: CustomPaint(
            painter: WaveformColumnPainter(columns: columns),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

void main() {
  group('WaveformColumnPainter', () {
    testWidgets('renders without exception with an empty buffer', (tester) async {
      await tester.pumpWidget(_paint(const <WaveformColumn>[]));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exception with a full mock buffer',
        (tester) async {
      final columns = List<WaveformColumn>.generate(
        100,
        (i) => WaveformColumn(
          amplitude: i / 100.0,
          bassWeight: 0.6,
          midWeight: 0.3,
          highWeight: 0.1,
        ),
      );
      await tester.pumpWidget(_paint(columns));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles WaveformColumn.empty sentinel', (tester) async {
      await tester.pumpWidget(
        _paint(List<WaveformColumn>.filled(50, WaveformColumn.empty)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
