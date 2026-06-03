// Camelot Wheel CustomPainter.
//
// Draws 24 segments: inner ring = A (minor), outer ring = B (major).
// Positions 1–12 clockwise starting at top (12 o'clock).
// Active segment highlighted with accent; 3 harmonic neighbors at 28% opacity;
// remaining segments use surfaceHigh fill.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Returns the 3 harmonically compatible Camelot neighbors of [camelot].
///
/// Rules:
/// - Same number, other letter (A↔B): relative major/minor
/// - Number − 1, same letter (wrap 1 → 12): semitone down
/// - Number + 1, same letter (wrap 12 → 1): semitone up
///
/// Examples:
/// - "8A" → ["7A", "9A", "8B"]
/// - "1A" → ["12A", "2A", "1B"]
/// - "12B" → ["11B", "1B", "12A"]
List<String> camelotNeighbors(String camelot) {
  final match = RegExp(r'^(\d+)([AB])$').firstMatch(camelot);
  if (match == null) return const [];
  final n = int.parse(match.group(1)!);
  final l = match.group(2)!;
  if (n < 1 || n > 12) return const [];
  final prev = n == 1 ? 12 : n - 1;
  final next = n == 12 ? 1 : n + 1;
  final other = l == 'A' ? 'B' : 'A';
  return ['$prev$l', '$next$l', '$n$other'];
}

class CamelotWheelPainter extends CustomPainter {
  const CamelotWheelPainter({this.activeKey});

  /// Active Camelot position, e.g. "8A". Null → all segments unlit.
  final String? activeKey;

  // Radii as fraction of the paint area's min half-dimension.
  static const double _innerRingStart = 0.33;
  static const double _innerRingEnd = 0.58;
  static const double _outerRingStart = 0.61;
  static const double _outerRingEnd = 0.88;

  // Visual gap between adjacent segments (degrees).
  static const double _gapDeg = 1.8;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy);

    final neighbors = activeKey != null ? camelotNeighbors(activeKey!) : const <String>[];

    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int p = 1; p <= 12; p++) {
      _drawSegment(canvas, cx, cy, r, p, 'A', fillPaint, neighbors);
      _drawSegment(canvas, cx, cy, r, p, 'B', fillPaint, neighbors);
    }
  }

  void _drawSegment(
    Canvas canvas,
    double cx,
    double cy,
    double r,
    int position,
    String letter,
    Paint paint,
    List<String> neighbors,
  ) {
    final key = '$position$letter';
    final isActive = key == activeKey;
    final isNeighbor = neighbors.contains(key);
    final isInner = letter == 'A';

    // ── Fill colour ───────────────────────────────────────────────────────────
    final Color fill;
    if (isActive) {
      fill = AppColors.accent;
    } else if (isNeighbor) {
      fill = AppColors.accent.withAlpha(71); // ~28%
    } else {
      fill = AppColors.surfaceHigh;
    }

    final r1 = (isInner ? _innerRingStart : _outerRingStart) * r;
    final r2 = (isInner ? _innerRingEnd : _outerRingEnd) * r;

    // ── Angles ────────────────────────────────────────────────────────────────
    // Position 1 at top (−π/2), clockwise by π/6 per step.
    final baseStart = (position - 1) * math.pi / 6 - math.pi / 2;
    const gapRad = _gapDeg * math.pi / 180;
    final startAngle = baseStart + gapRad / 2;
    final sweepAngle = math.pi / 6 - gapRad;

    // ── Path (annular sector) ─────────────────────────────────────────────────
    final path = Path()
      ..moveTo(cx + r2 * math.cos(startAngle), cy + r2 * math.sin(startAngle))
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: r2),
        startAngle, sweepAngle, false,
      )
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: r1),
        startAngle + sweepAngle, -sweepAngle, false,
      )
      ..close();

    paint.color = fill;
    canvas.drawPath(path, paint);

    // ── Label ─────────────────────────────────────────────────────────────────
    final midAngle = baseStart + math.pi / 12; // center of 30° segment
    final midR = (r1 + r2) / 2;
    final tx = cx + midR * math.cos(midAngle);
    final ty = cy + midR * math.sin(midAngle);

    final Color textColor;
    if (isActive) {
      textColor = AppColors.background;
    } else if (isNeighbor) {
      textColor = AppColors.accent;
    } else {
      textColor = AppColors.textSecondary;
    }

    final fontSize = (r * 0.115).clamp(7.0, 13.0);
    final tp = TextPainter(
      text: TextSpan(
        text: key,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          color: textColor,
          fontFamily: 'IBMPlexMono',
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(tx - tp.width / 2, ty - tp.height / 2));
  }

  @override
  bool shouldRepaint(CamelotWheelPainter old) => old.activeKey != activeKey;
}
