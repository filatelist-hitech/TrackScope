// SpectrogramPainter — scrolling FFT waterfall with metric axes.
//
// Draws the spectrogram ring from VizController: time flows left→right,
// frequency bottom→top, brightness = log-magnitude mapped through the LUT.
//
// Phase 7 additions:
//   • Y-axis: Hz gridlines + labels at octave-spaced frequencies (63–4000 Hz).
//   • X-axis: time gridlines + labels (−8s … 0) based on hopSec.
//   • "SPECTROGRAM" label in the top-left corner.
//   • "Now" cursor colour updated to accent with alpha 0.6.
//
// Performance notes:
//   • 200 cols × 128 bins = 25 600 drawRect calls per repaint — same as before.
//   • Axis TextPainter objects are created per paint() call. There are only
//     12 labels total (~7 Hz + 5 time), so at 20 fps this is 240 allocs/s —
//     acceptable for a non-audio-thread painter.
//   • shouldRepaint checks list identity so identical data skips repaint.
//   • RepaintBoundary in the parent widget ensures this repaints only when
//     VizController notifies (new FFT column).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

class SpectrogramPainter extends CustomPainter {
  const SpectrogramPainter({
    required this.cols,
    required this.lutPaints,
    required this.accentColor,
    this.hopSec = 0.05,
  });

  final List<Int32List> cols;
  final List<Paint> lutPaints;

  /// Colour of the "now" cursor and accent-coloured grid elements.
  final Color accentColor;

  /// Duration of one FFT hop in seconds. Used to position time-axis labels.
  /// Default matches VizController._kHopSamples / 48 kHz = 2400/48000 = 0.05 s.
  final double hopSec;

  // Total display bins — kept in sync with viz_controller.dart _kDisplayBins.
  static const int _displayBins = 128;

  // Frequency range of the display (0 to 6 kHz for 128 bins × 46.9 Hz/bin).
  static const double _minFreq = 30.0; // avoids log(0); lower than lowest bin
  static const double _maxFreq = 6000.0;

  // Hz labels — all within the 0–6 kHz display range.
  // 8 kHz and above are outside the 128-bin window and are omitted.
  static const List<int> _freqLabels = [63, 125, 250, 500, 1000, 2000, 4000];
  static const List<String> _freqStrings = [
    '63', '125', '250', '500', '1k', '2k', '4k'
  ];

  // Time labels in seconds from "now" (0 = current column, right edge).
  static const List<double> _timeSec = [-8, -6, -4, -2, 0];
  static const List<String> _timeStrings = ['-8s', '-6s', '-4s', '-2s', '0'];

  // ── Axis paint helpers ────────────────────────────────────────────────────────

  static const _kGridLineHz = Color(0x22FFFFFF);   // Y-axis gridlines
  static const _kGridLineTime = Color(0x15FFFFFF);  // X-axis gridlines
  static const _kLabelHz = Color(0x88FFFFFF);       // Y-axis labels
  static const _kLabelTime = Color(0x66FFFFFF);     // X-axis labels
  static const _kCornerLabel = Color(0x44FFFFFF);   // 'SPECTROGRAM' label

  static const _kAxisTextStyle = TextStyle(
    fontSize: 9,
    fontFamily: 'monospace',
    letterSpacing: 0.0,
  );

  // ── Y-axis helpers ────────────────────────────────────────────────────────────

  /// Log-scale Y position for a given frequency within [_minFreq, _maxFreq].
  /// Returns 0 at _maxFreq (top), height at _minFreq (bottom).
  double _freqToY(double freq, double height) {
    final logRange = math.log(_maxFreq / _minFreq);
    return height * (1.0 - math.log(freq / _minFreq) / logRange);
  }

  // ── X-axis helpers ────────────────────────────────────────────────────────────

  /// X position for a column that is [secondsBack] seconds before "now".
  /// Returns null if the offset is beyond the available history.
  double? _timeToX(double secondsBack, int numCols, double width) {
    if (numCols == 0) return null;
    final colsBack = secondsBack / hopSec;
    final colIdx = numCols - 1 - colsBack;
    if (colIdx < 0) return null;
    final colW = width / numCols;
    return colIdx * colW;
  }

  // ── paint ─────────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Waterfall tiles ───────────────────────────────────────────────────────
    if (cols.isNotEmpty) {
      final colW = w / cols.length;
      final binH = h / _displayBins;

      for (var c = 0; c < cols.length; c++) {
        final col = cols[c];
        final x = c * colW;
        for (var bin = 0; bin < _displayBins; bin++) {
          final lutIdx = col[bin].clamp(0, 255);
          // bin 0 = lowest frequency → bottom of image
          final y = h - (bin + 1) * binH;
          canvas.drawRect(
            Rect.fromLTWH(x, y, colW + 0.5, binH + 0.5),
            lutPaints[lutIdx],
          );
        }
      }
    }

    // ── Y-axis gridlines + labels ─────────────────────────────────────────────
    final gridPaintHz = Paint()
      ..color = _kGridLineHz
      ..strokeWidth = 0.5;

    for (var i = 0; i < _freqLabels.length; i++) {
      final freq = _freqLabels[i].toDouble();
      final y = _freqToY(freq, h);
      if (y < 0 || y > h) continue;

      // Gridline
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaintHz);

      // Label (right side, inside the panel)
      final tp = TextPainter(
        text: TextSpan(
          text: _freqStrings[i],
          style: _kAxisTextStyle.copyWith(color: _kLabelHz),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w - tp.width - 3, y - tp.height));
    }

    // ── X-axis gridlines + labels ─────────────────────────────────────────────
    final gridPaintTime = Paint()
      ..color = _kGridLineTime
      ..strokeWidth = 0.5;

    for (var i = 0; i < _timeSec.length; i++) {
      final x = _timeToX(-_timeSec[i], cols.length, w);
      if (x == null || x < 0 || x > w) continue;

      // Gridline
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaintTime);

      // Label (bottom, inside the panel)
      final tp = TextPainter(
        text: TextSpan(
          text: _timeStrings[i],
          style: _kAxisTextStyle.copyWith(color: _kLabelTime),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelX = (x - tp.width / 2).clamp(0.0, w - tp.width);
      tp.paint(canvas, Offset(labelX, h - tp.height - 1));
    }

    // ── "Now" cursor ──────────────────────────────────────────────────────────
    // Semi-transparent accent vertical line at the right edge (current time).
    canvas.drawLine(
      Offset(w - 1, 0),
      Offset(w - 1, h),
      Paint()
        ..color = accentColor.withAlpha(153) // ~0.6 alpha
        ..strokeWidth = 1.0,
    );

    // ── "SPECTROGRAM" label (top-left) ────────────────────────────────────────
    final labelTp = TextPainter(
      text: const TextSpan(
        text: 'SPECTROGRAM',
        style: TextStyle(
          fontSize: 8,
          fontFamily: 'monospace',
          color: _kCornerLabel,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelTp.paint(canvas, const Offset(4, 4));
  }

  @override
  bool shouldRepaint(SpectrogramPainter old) =>
      !identical(cols, old.cols) || accentColor != old.accentColor;
}
