// WaveformColumnPainter — Traktor DJ–style bar waveform.
//
// Each column is a sharp rectangle whose height encodes amplitude and whose
// colour encodes bass energy (dark teal → bright accent).
//
// Reference grid (faint):
//   • Horizontal centre line at y = h/2 (zero-crossing reference).
//   • "NOW →" label at right edge.
//   • Faint time labels: "−5s" left edge, "−2.5s" midpoint (approximate).
//     Timing is based on hopMs * visible columns.
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

// Grid / label colours.
const Color _kGridLine  = Color(0x22FFFFFF); // faint centre line
const Color _kTimeLabel = Color(0x44AADDCC); // time tick labels

// Hop duration (ms) assumed for time-axis labels.
// Matches VizController._kHopSamples / 48000 = 2400/48000 = 50 ms.
const double _kHopMs = 50.0;



class WaveformColumnPainter extends CustomPainter {
  const WaveformColumnPainter({
    required this.columns,
    this.hopMs = _kHopMs,
  });

  final List<WaveformColumn> columns;
  final double hopMs;

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

    // ── Reference grid ────────────────────────────────────────────────────────
    // Faint horizontal centre line.
    canvas.drawLine(
      Offset(0, centerY),
      Offset(w, centerY),
      Paint()
        ..color = _kGridLine
        ..strokeWidth = 0.5,
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

    // ── Time-axis labels ──────────────────────────────────────────────────────
    // "NOW" at the right edge; "−Xs" labels at equal intervals.
    const labelStyle = TextStyle(
      fontSize: 7,
      fontFamily: 'monospace',
      color: _kTimeLabel,
    );

    // Total visible time in seconds.
    final totalSec = (maxVisible * hopMs / 1000).roundToDouble();

    // Label positions: left edge and midpoint.
    final timeLabels = <(double, String)>[
      (w - 4, 'NOW'),
      if (totalSec >= 2) (w / 2, '−${(totalSec / 2).round()}s'),
      (4, '−${totalSec.round()}s'),
    ];

    for (final (lx, txt) in timeLabels) {
      final tp = TextPainter(
        text: TextSpan(text: txt, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      // Align "NOW" to the right of the anchor, others centred.
      final drawX = txt == 'NOW'
          ? (lx - tp.width).clamp(0.0, w - tp.width)
          : (lx - tp.width / 2).clamp(0.0, w - tp.width);
      tp.paint(canvas, Offset(drawX, h - tp.height - 2));
    }

    // Zone label is now rendered as a Flutter widget (_ZoneLabelRow) above
    // this panel in main_screen.dart — do not duplicate it on the canvas.
  }

  @override
  bool shouldRepaint(WaveformColumnPainter old) {
    if (columns.length != old.columns.length) return true;
    return !identical(columns, old.columns);
  }
}
