// SpectrumBarsPainter — animated FFT spectrum analyser.
//
// Renders 48 log-spaced frequency bars (30 Hz → 6 kHz).
// Bar heights come from VizController.smoothedBars — a fast-attack /
// ~300 ms decay envelope computed from the latest FFT column.
//
// Colour is mapped from height through the thermal LUT:
//   quiet  →  dark-blue (#0D0221)
//   medium →  cyan / green
//   loud   →  yellow / orange-red (#FF4400)
//   peak   →  white (#FFFFFF)
//
// Paint objects are pre-allocated in VizController.lutPaints (256 entries)
// so no per-frame allocs occur in the hot path.
//
// RepaintBoundary in the parent ensures repaints only on new FFT data.
// shouldRepaint checks list identity: VizController replaces _smoothedBars
// atomically each column.

import 'package:flutter/material.dart';

class SpectrumBarsPainter extends CustomPainter {
  const SpectrumBarsPainter({
    required this.bars,
    required this.lutPaints,
  });

  /// 48 smoothed heights in [0, 1], as published by VizController.
  final List<double> bars;

  /// 256 pre-created Paint objects from the thermal LUT.
  final List<Paint> lutPaints;

  static const _kBg = Color(0xFF0A0A0F);
  static const _kBarRadius = Radius.circular(3);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _kBg,
    );

    if (bars.isEmpty) return;

    final n = bars.length;
    const gap = 2.0;
    const topPad = 6.0;
    final barW = (size.width - gap * (n - 1)) / n;
    final maxH = size.height - topPad;

    for (var i = 0; i < n; i++) {
      final h = bars[i];
      if (h < 0.005) continue; // skip near-zero bars

      final barH = h * maxH;
      final x = i * (barW + gap);
      final y = size.height - barH;
      final lutIdx = (h * 255).round().clamp(0, 255);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, barH),
          _kBarRadius,
        ),
        lutPaints[lutIdx],
      );
    }
  }

  @override
  bool shouldRepaint(SpectrumBarsPainter old) => !identical(bars, old.bars);
}
