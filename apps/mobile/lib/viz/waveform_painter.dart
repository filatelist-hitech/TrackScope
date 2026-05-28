// WaveformPainter — amplitude vs time, synchronised with spectrogram time axis.
//
// Receives the 300-point downsampled PCM slice from VizController.waveCache
// and draws a centred waveform path. Colour is teal (#00BFA5) normally,
// red (#F44336) when signal_quality.clipping == true.
//
// inputLevel (0..1 from −60 dBFS → 0 dBFS) drives a 4 px level-meter bar on
// the right edge: green / yellow / red as level approaches 0 dBFS.
//
// RepaintBoundary in the parent ensures repaints are triggered only by new
// data, not by table/badge rebuilds.

import 'package:flutter/material.dart';

class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.samples,
    required this.isClipping,
    this.inputLevel = 0.0,
  });

  final List<double> samples;
  final bool isClipping;

  /// Normalised input level: 0.0 = −60 dBFS, 1.0 = 0 dBFS.
  /// Drives the right-edge level-meter bar.
  final double inputLevel;

  static const _kAccent = Color(0xFF00BFA5);
  static const _kClip = Color(0xFFF44336);
  static const _kZeroLine = Color(0x22FFFFFF);
  static const _kBg = Color(0xFF0A0A0F);
  static const _kMeterBg = Color(0x33FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _kBg,
    );

    // ── Zero-line ────────────────────────────────────────────────────────────
    final midY = size.height / 2;
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = _kZeroLine
        ..strokeWidth = 0.5,
    );

    // ── Waveform path ────────────────────────────────────────────────────────
    if (samples.isNotEmpty) {
      final waveColor = isClipping ? _kClip : _kAccent;
      final paint = Paint()
        ..color = waveColor
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final stepX = size.width / (samples.length - 1).clamp(1, 9999);
      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final x = i * stepX;
        final y = midY - samples[i].clamp(-1.0, 1.0) * (midY * 0.9);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    // ── Level meter (right edge, 4 px, drawn over waveform) ─────────────────
    const mW = 4.0;
    const mPad = 4.0;
    final mX = size.width - mW - mPad;
    final mH = size.height - mPad * 2;

    // Background track
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(mX, mPad, mW, mH),
        const Radius.circular(2),
      ),
      Paint()..color = _kMeterBg,
    );

    if (inputLevel > 0.01) {
      final fillH = mH * inputLevel.clamp(0.0, 1.0);
      final meterColor = inputLevel > 0.85
          ? const Color(0xCCF44336) // red: near clipping
          : inputLevel > 0.6
              ? const Color(0xCCFFD600) // yellow: moderate
              : const Color(0xCC00C853); // green: healthy
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(mX, mPad + mH - fillH, mW, fillH),
          const Radius.circular(2),
        ),
        Paint()..color = meterColor,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      !identical(samples, old.samples) ||
      isClipping != old.isClipping ||
      inputLevel != old.inputLevel;
}
