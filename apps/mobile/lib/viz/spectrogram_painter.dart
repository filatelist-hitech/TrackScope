// SpectrogramPainter — scrolling FFT waterfall.
//
// Draws the spectrogram ring from VizController: time flows left→right,
// frequency bottom→top, brightness = log-magnitude mapped through the LUT.
//
// Performance notes:
//   • 200 cols × 128 bins = 25 600 drawRect calls per repaint.
//   • Paint objects are pre-allocated in VizController.lutPaints (256 entries)
//     — no Color.lerp or object creation during paint().
//   • RepaintBoundary + ListenableBuilder in the parent widget ensure this
//     repaints only when VizController notifies (new FFT column), not when
//     the table or badge rebuild.
//   • shouldRepaint checks list identity so identical data skips repaint.
//
// Placeholder ("Ожидание микрофона…") is rendered by the parent widget as a
// real Flutter Text widget (not Canvas), so it's findable by widget tests.

import 'dart:typed_data';

import 'package:flutter/material.dart';

class SpectrogramPainter extends CustomPainter {
  const SpectrogramPainter({
    required this.cols,
    required this.lutPaints,
  });

  final List<Int32List> cols;
  final List<Paint> lutPaints;

  // Total display bins — kept in sync with viz_controller.dart _kDisplayBins.
  static const int _displayBins = 128;

  @override
  void paint(Canvas canvas, Size size) {
    if (cols.isEmpty) return;

    final colW = size.width / cols.length;
    final binH = size.height / _displayBins;

    for (var c = 0; c < cols.length; c++) {
      final col = cols[c];
      final x = c * colW;
      for (var bin = 0; bin < _displayBins; bin++) {
        final lutIdx = col[bin].clamp(0, 255);
        // bin 0 = lowest frequency → bottom of image
        final y = size.height - (bin + 1) * binH;
        canvas.drawRect(
          Rect.fromLTWH(x, y, colW + 0.5, binH + 0.5),
          lutPaints[lutIdx],
        );
      }
    }

    // "Now" cursor — semi-transparent white vertical line at the right edge.
    // Anchors the viewer's eye at the "present" column as time scrolls left.
    canvas.drawLine(
      Offset(size.width - 1, 0),
      Offset(size.width - 1, size.height),
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(SpectrogramPainter old) => !identical(cols, old.cols);
}
