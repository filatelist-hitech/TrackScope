// WaveformPainter — amplitude vs time, synchronised with spectrogram time axis.
//
// Receives the 300-point downsampled PCM slice from VizController.waveCache
// and draws a centred waveform path. Colour is teal (#00BFA5) normally,
// red (#F44336) when signal_quality.clipping == true.
//
// RepaintBoundary in the parent ensures repaints are triggered only by new
// data, not by table/badge rebuilds.

import 'package:flutter/material.dart';

class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.samples,
    required this.isClipping,
  });

  final List<double> samples;
  final bool isClipping;

  static const _kAccent = Color(0xFF00BFA5);
  static const _kClip = Color(0xFFF44336);
  static const _kZeroLine = Color(0x22FFFFFF);
  static const _kBg = Color(0xFF0A0A0F);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _kBg,
    );

    // Zero-line
    final midY = size.height / 2;
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = _kZeroLine
        ..strokeWidth = 0.5,
    );

    if (samples.isEmpty) return;

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

  @override
  bool shouldRepaint(WaveformPainter old) =>
      !identical(samples, old.samples) || isClipping != old.isClipping;
}
