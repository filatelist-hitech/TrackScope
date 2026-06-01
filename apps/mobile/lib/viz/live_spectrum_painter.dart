// LiveSpectrumPainter — smooth live FFT spectrum with gradient fill and peak hold.
//
// Renders the current FFT frame from VizController.latestNorms as a smooth
// animated curve with a gradient fill below it. Also draws peak-hold tick
// marks from VizController.peakHoldValues.
//
// Data contract:
//   • norms     — List<double> of (fftSize ~/ 2) values in [0, 1].
//                 Fixed-dBFS normalized (20*log10(mag/refMag) / 60 + 1).
//                 Published atomically by VizController each FFT hop.
//   • peakHold  — per-bin peak over the last ~1.5 s, same index space.
//                 Decays by ×0.90 per column after the hold window expires.
//
// X-axis: logarithmic, 20 Hz → 20 kHz.
// Y-axis: linear normalized [0, 1] (bottom = silence, top = full scale).
//
// Anti-fake: this painter reads only from VizController, which in turn reads
// only from raw PCM. No BPM maths, no hardcoded values.
//
// Performance notes:
//   • Curve drawn via Path.quadraticBezierTo with midpoint smoothing.
//     ~426 bins in the 20–20 kHz range → 426 bezier segments per repaint.
//   • Glow drawn twice (blur pass first, then crisp pass) — each is one
//     canvas.drawPath call.
//   • Gradient fill: one drawPath call with a LinearGradient shader.
//   • Peak-hold ticks: one drawRect per visible bin grouping.
//   • shouldRepaint checks List identity — skips repaint when norms unchanged.

import 'dart:math' as math;

import 'package:flutter/material.dart';

class LiveSpectrumPainter extends CustomPainter {
  const LiveSpectrumPainter({
    required this.norms,
    required this.peakHold,
    required this.accentColor,
    this.sampleRate = 48000.0,
    this.fftSize = 1024,
  });

  /// Normalized magnitudes [0, 1] — one entry per positive-frequency FFT bin.
  /// Empty when no audio is available.
  final List<double> norms;

  /// Per-bin peak-hold values [0, 1]. Same length as [norms].
  final List<double> peakHold;

  final Color accentColor;

  /// Sample rate used by VizController (default 48 000 Hz).
  final double sampleRate;

  /// FFT size (number of points, not bins). Default 1024.
  final int fftSize;

  // ── Display frequency range ───────────────────────────────────────────────────
  static const double _minFreq = 20.0;
  static const double _maxFreq = 20000.0;
  // ln(_maxFreq / _minFreq) = ln(20000 / 20) = ln(1000) ≈ 6.9078
  // Previous incorrect value 9.965784 ≈ ln(21286), causing the spectrum to
  // render only ~69% of the canvas width.
  static const double _logRange = 6.907755;

  // X-axis label anchors (Hz → label string)
  static const List<double> _xLabelFreqs = [50, 200, 1000, 4000, 16000];
  static const List<String> _xLabelStrings = ['50', '200', '1k', '4k', '16k'];

  static const _kLabelStyle = TextStyle(
    fontSize: 8,
    fontFamily: 'monospace',
    color: Color(0x55FFFFFF),
  );


  // ── Helpers ───────────────────────────────────────────────────────────────────

  /// Frequency of FFT bin [i].
  double _binFreq(int i) => i * sampleRate / fftSize;

  /// Log-scale X position for [freq] within [_minFreq, _maxFreq].
  double _freqToX(double freq, double width) {
    if (freq <= _minFreq) return 0;
    if (freq >= _maxFreq) return width;
    return width * math.log(freq / _minFreq) / _logRange;
  }

  // ── paint ─────────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Reserve ~14 px at the bottom for X-axis labels.
    const labelAreaH = 14.0;
    final drawH = h - labelAreaH;

    if (norms.isEmpty) return;

    final halfBins = norms.length;

    // ── Build visible bin list ────────────────────────────────────────────────
    // Collect (x, y) for bins whose frequency is in [_minFreq, _maxFreq].
    final List<double> xs = [];
    final List<double> ys = [];

    for (var i = 1; i < halfBins; i++) {
      final freq = _binFreq(i);
      if (freq < _minFreq) continue;
      if (freq > _maxFreq) break;
      final x = _freqToX(freq, w);
      final y = drawH * (1.0 - norms[i].clamp(0.0, 1.0));
      xs.add(x);
      ys.add(y);
    }

    if (xs.isEmpty) return;

    // ── Build smooth line path ────────────────────────────────────────────────
    // Midpoint quadratic bezier between consecutive points for smoothness.
    // Start from x=0 at the same amplitude as the first visible bin so there
    // is no unfilled gap at the left edge (the first bin is at ~47 Hz, not 0).
    final linePath = Path();
    linePath.moveTo(0, ys.first);
    for (var k = 0; k < xs.length - 1; k++) {
      final mx = (xs[k] + xs[k + 1]) / 2.0;
      final my = (ys[k] + ys[k + 1]) / 2.0;
      linePath.quadraticBezierTo(xs[k], ys[k], mx, my);
    }
    linePath.lineTo(xs.last, ys.last);

    // ── Gradient fill ─────────────────────────────────────────────────────────
    // Extend the fill baseline to the full canvas width so no gap appears at
    // the right edge when the last visible bin is just below 20 kHz.
    final fillPath = Path()..addPath(linePath, Offset.zero);
    fillPath.lineTo(w, drawH);
    fillPath.lineTo(xs.first, drawH);
    fillPath.close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accentColor.withAlpha(120),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, drawH));
    canvas.drawPath(fillPath, fillPaint);

    // ── Glow pass (blurred stroke) ────────────────────────────────────────────
    final glowPaint = Paint()
      ..color = accentColor.withAlpha(90)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      // ignore: avoid_redundant_argument_values
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(linePath, glowPaint);

    // ── Crisp line pass ───────────────────────────────────────────────────────
    final linePaint = Paint()
      ..color = accentColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // ── Peak-hold ticks ───────────────────────────────────────────────────────
    // Draw a small horizontal tick (4 px wide × 2 px tall) at each bin's
    // peak-hold position. Alpha scales with the hold value itself, creating
    // a natural fade as the peak decays.
    if (peakHold.isNotEmpty && peakHold.length == halfBins) {
      final tickPaint = Paint()..style = PaintingStyle.fill;
      var visIdx = 0;
      for (var i = 1; i < halfBins; i++) {
        final freq = _binFreq(i);
        if (freq < _minFreq) continue;
        if (freq > _maxFreq) break;
        if (visIdx >= xs.length) break;

        final ph = peakHold[i];
        if (ph < 0.02) {
          visIdx++;
          continue; // skip near-zero peaks
        }
        final alpha = (ph * 0.7 * 255).round().clamp(0, 255);
        tickPaint.color = accentColor.withAlpha(alpha);
        final px = xs[visIdx];
        final py = drawH * (1.0 - ph.clamp(0.0, 1.0));
        canvas.drawRect(
          Rect.fromLTWH(px - 2, py, 4, 2),
          tickPaint,
        );
        visIdx++;
      }
    }

    // ── X-axis labels ─────────────────────────────────────────────────────────
    for (var i = 0; i < _xLabelFreqs.length; i++) {
      final freq = _xLabelFreqs[i];
      final x = _freqToX(freq, w);
      final tp = TextPainter(
        text: TextSpan(text: _xLabelStrings[i], style: _kLabelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = (x - tp.width / 2).clamp(0.0, w - tp.width);
      tp.paint(canvas, Offset(lx, drawH + 2));
    }

    // Zone label is now rendered as a Flutter widget (_ZoneLabelRow) above
    // this panel in main_screen.dart — do not duplicate it on the canvas.
  }

  @override
  bool shouldRepaint(LiveSpectrumPainter old) =>
      !identical(norms, old.norms) ||
      !identical(peakHold, old.peakHold) ||
      accentColor != old.accentColor;
}
