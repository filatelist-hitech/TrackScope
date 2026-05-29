// WaveformPainter — oscilloscope-style rolling PCM waveform.
//
// Phase 7.1 redesign: glowing accent line on dark grid, "WAVEFORM" corner
// label, dashed "Now" cursor at right edge.
//
// Receives VizController.waveCache — 300 downsampled f32 PCM samples ∈ [-1,1].
// Colour is accentColor normally; _kClip (#FF4444) when isClipping == true.
//
// Performance notes:
//   • Grid: 4 horizontal + 6 vertical drawLine calls — negligible.
//   • Glow pass: one drawPath with MaskFilter.blur, then one crisp drawPath.
//   • "Now" cursor: series of short drawLine calls (dashes).
//   • shouldRepaint checks List identity — skips repaint when samples unchanged.

import 'package:flutter/material.dart';

class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.samples,
    required this.accentColor,
    this.isClipping = false,
  });

  /// Downsampled PCM slice from VizController.waveCache (300 points, [-1, 1]).
  final List<double> samples;

  /// Accent colour for the waveform line (normally AppTheme.accent).
  final Color accentColor;

  /// When true, line colour changes to red to warn of clipping.
  final bool isClipping;

  // Clipping warning colour — same red as AppTheme.danger.
  static const _kClip = Color(0xFFFF4444);

  // Grid / label colours — fully self-contained, no design_tokens dependency.
  static const _kGridLine    = Color(0x08FFFFFF);
  static const _kCentreRef   = Color(0x0CFFFFFF);
  static const _kCornerLabel = Color(0x44FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Background ────────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF07070F),
    );

    // ── Grid — horizontal dividers ────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = _kGridLine
      ..strokeWidth = 0.5;
    for (var i = 1; i < 4; i++) {
      final y = h * i / 4;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // ── Grid — vertical dividers ──────────────────────────────────────────────
    for (var i = 1; i < 6; i++) {
      final x = w * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }

    // ── Centre reference line (slightly brighter than grid) ───────────────────
    canvas.drawLine(
      Offset(0, h / 2),
      Offset(w, h / 2),
      Paint()
        ..color = _kCentreRef
        ..strokeWidth = 0.5,
    );

    // ── Waveform ──────────────────────────────────────────────────────────────
    if (samples.isNotEmpty) {
      final waveColor = isClipping ? _kClip : accentColor;
      final stepX = w / (samples.length - 1).clamp(1, 99999);
      final midY = h / 2;

      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final x = i * stepX;
        final y = midY - samples[i].clamp(-1.0, 1.0) * (midY * 0.86);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      // Glow pass
      canvas.drawPath(
        path,
        Paint()
          ..color = waveColor.withAlpha(90)
          ..strokeWidth = 5.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          // ignore: avoid_redundant_argument_values
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0),
      );

      // Crisp line
      canvas.drawPath(
        path,
        Paint()
          ..color = waveColor
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── "Now" cursor — dashed vertical at right edge ──────────────────────────
    final nowPaint = Paint()
      ..color = accentColor.withAlpha(115) // ~0.45 alpha
      ..strokeWidth = 1.0;
    const dashLen = 4.0;
    const gapLen  = 4.0;
    var dy = 0.0;
    while (dy < h) {
      final endY = (dy + dashLen).clamp(0.0, h);
      canvas.drawLine(Offset(w - 1, dy), Offset(w - 1, endY), nowPaint);
      dy += dashLen + gapLen;
    }

    // ── "WAVEFORM" label (top-left) ───────────────────────────────────────────
    final tp = TextPainter(
      text: const TextSpan(
        text: 'WAVEFORM',
        style: TextStyle(
          fontSize: 8,
          fontFamily: 'monospace',
          color: _kCornerLabel,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(4, 4));
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      !identical(samples, old.samples) ||
      isClipping != old.isClipping ||
      accentColor != old.accentColor;
}
