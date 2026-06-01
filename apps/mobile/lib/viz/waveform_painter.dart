// WaveformColumnPainter — Traktor DJ–style bar waveform.
//
// Each column is a sharp rectangle whose height encodes amplitude and whose
// colour encodes bass energy (dark teal → bright accent).  No smoothing,
// no rounded corners, no dashed cursor line.
//
// Receives VizController.waveColumns — a ring of WaveformColumn snapshots
// updated every FFT hop (~50 ms).
//
// Performance:
//   • One drawRect per visible column — no Path, no MaskFilter.
//   • shouldRepaint uses List identity — skips repaint when data unchanged.
//   • RepaintBoundary is set by the parent _WaveformView widget.

import 'package:flutter/material.dart';

import 'waveform_column.dart';

const double _kColW = 3.0;
const double _kColGap = 0.5;
const double _kColStep = _kColW + _kColGap;

// Dark teal for quiet / high-frequency columns.
const Color _kColDark = Color(0xFF003D35);

// Accent cyan for kick / bass-heavy columns.
const Color _kColAccent = Color(0xFF00E5CC);

// Corner label colour — same semi-transparent white as the old oscilloscope.
const Color _kCornerLabel = Color(0x44FFFFFF);

class WaveformColumnPainter extends CustomPainter {
  const WaveformColumnPainter({required this.columns});

  final List<WaveformColumn> columns;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerY = h / 2;

    // Background.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF07070F),
    );

    if (columns.isEmpty) return;

    // How many columns fit across the panel.
    final maxVisible = (w / _kColStep).floor().clamp(1, columns.length);
    final startIdx = columns.length - maxVisible;

    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < maxVisible; i++) {
      final col = columns[startIdx + i];
      final x = i * _kColStep + _kColW / 2;

      // Colour: lerp dark→accent by bass × amplitude.
      final brightness = (col.bassWeight * col.amplitude).clamp(0.0, 1.0);
      paint.color = Color.lerp(_kColDark, _kColAccent, brightness)!;

      final barH = (col.amplitude * h).clamp(1.0, h);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, centerY), width: _kColW, height: barH),
        paint,
      );
    }

    // "WAVEFORM" corner label.
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
  bool shouldRepaint(WaveformColumnPainter old) {
    if (columns.length != old.columns.length) return true;
    return !identical(columns, old.columns);
  }
}
