import 'package:flutter/material.dart';

import '../setlist/setlist_entry.dart';
import '../../theme/app_colors.dart';

/// CustomPainter that renders a 1080×1080 set-energy card from [entries].
///
/// Layout:
///   - Top 60%: BPM curve (polyline, time x-axis, BPM y-axis) + Camelot pills.
///   - Bottom 35%: polar energy arc (10 wedge segments coloured by avg level).
///   - Bottom-right: "TrackScope" watermark.
///
/// Data sources: entry.bpm, entry.camelotKey, entry.energyLevel, entry.timestamp.
/// No hardcoded BPM values — all values come from real DSP output in SetlistEntry.
class SetEnergyCardPainter extends CustomPainter {
  const SetEnergyCardPainter(this.entries);

  final List<SetlistEntry> entries;

  // ── Layout constants (relative to 1080-px canvas) ───────────────────────────
  static const double _padding = 72.0;
  static const double _curveAreaHeightRatio = 0.55;
  static const double _arcRadius = 160.0;
  static const double _arcStrokeWidth = 28.0;
  static const double _pillPad = 8.0;
  static const double _pillRadius = 6.0;
  static const double _pillFontSize = 22.0;
  static const double _watermarkFontSize = 20.0;
  static const double _bpmRangePad = 5.0; // min half-range when all BPM equal

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppColors.background,
    );

    if (entries.isEmpty) return;

    final curveBottom = size.height * _curveAreaHeightRatio;
    final curveRect = Rect.fromLTRB(_padding, _padding, size.width - _padding, curveBottom);

    _drawGrid(canvas, curveRect);
    _drawBpmCurve(canvas, curveRect);
    _drawCamelotPills(canvas, curveRect);
    _drawEnergyArc(canvas, size);
    _drawWatermark(canvas, size);
  }

  // ── BPM grid ──────────────────────────────────────────────────────────────

  void _drawGrid(Canvas canvas, Rect area) {
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1.0;

    // 4 horizontal grid lines
    for (int i = 1; i <= 4; i++) {
      final y = area.top + area.height * i / 4;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), gridPaint);
    }
  }

  // ── BPM curve ─────────────────────────────────────────────────────────────

  void _drawBpmCurve(Canvas canvas, Rect area) {
    if (entries.length == 1) {
      // Single dot at center
      canvas.drawCircle(
        Offset(area.left + area.width / 2, area.top + area.height / 2),
        6,
        Paint()..color = AppColors.accent,
      );
      return;
    }

    final (bpmMin, bpmMax) = _bpmRange();
    final tMin = entries.first.timestamp.millisecondsSinceEpoch.toDouble();
    final tMax = entries.last.timestamp.millisecondsSinceEpoch.toDouble();
    final tRange = (tMax - tMin) == 0 ? 1.0 : tMax - tMin;

    Offset _toCanvas(SetlistEntry e) {
      final tx = (e.timestamp.millisecondsSinceEpoch - tMin) / tRange;
      final ty = 1.0 - (e.bpm - bpmMin) / (bpmMax - bpmMin);
      return Offset(
        area.left + tx * area.width,
        area.top + ty * area.height,
      );
    }

    final path = Path()..moveTo(_toCanvas(entries.first).dx, _toCanvas(entries.first).dy);
    for (int i = 1; i < entries.length; i++) {
      final pt = _toCanvas(entries[i]);
      path.lineTo(pt.dx, pt.dy);
    }

    // Gradient fill under curve
    final fillPath = Path.from(path)
      ..lineTo(_toCanvas(entries.last).dx, area.bottom)
      ..lineTo(_toCanvas(entries.first).dx, area.bottom)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.accent.withAlpha(60), AppColors.accent.withAlpha(0)],
        ).createShader(area),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots at each point
    final dotPaint = Paint()..color = AppColors.accent;
    for (final e in entries) {
      canvas.drawCircle(_toCanvas(e), 4, dotPaint);
    }
  }

  // ── Camelot pills ─────────────────────────────────────────────────────────

  void _drawCamelotPills(Canvas canvas, Rect area) {
    if (entries.length < 2) return;

    final tMin = entries.first.timestamp.millisecondsSinceEpoch.toDouble();
    final tMax = entries.last.timestamp.millisecondsSinceEpoch.toDouble();
    final tRange = (tMax - tMin) == 0 ? 1.0 : tMax - tMin;

    String? lastKey;
    for (final e in entries) {
      if (e.camelotKey == null) continue;
      if (e.camelotKey == lastKey) continue;
      lastKey = e.camelotKey;

      final tx = (e.timestamp.millisecondsSinceEpoch - tMin) / tRange;
      final cx = area.left + tx * area.width;

      final tp = TextPainter(
        text: TextSpan(
          text: e.camelotKey,
          style: const TextStyle(
            fontFamily: 'IBM Plex Mono',
            fontSize: _pillFontSize,
            fontWeight: FontWeight.w700,
            color: AppColors.background,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final pillW = tp.width + _pillPad * 2;
      final pillH = tp.height + _pillPad * 1.4;
      final pillLeft = (cx - pillW / 2).clamp(area.left, area.right - pillW);
      final pillTop = area.top - pillH - 6;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(pillLeft, pillTop, pillW, pillH),
          const Radius.circular(_pillRadius),
        ),
        Paint()..color = AppColors.accent,
      );

      tp.paint(canvas, Offset(pillLeft + _pillPad, pillTop + _pillPad * 0.7));
    }
  }

  // ── Energy arc ────────────────────────────────────────────────────────────

  void _drawEnergyArc(Canvas canvas, Size size) {
    final energyEntries = entries.where((e) => e.energyLevel != null).toList();
    if (energyEntries.isEmpty) return;

    // Average energy level
    final avgLevel = energyEntries
            .map((e) => e.energyLevel!)
            .reduce((a, b) => a + b) /
        energyEntries.length;

    final center = Offset(size.width / 2, size.height * 0.80);
    const segments = 10;
    const sweepAngle = 2 * 3.14159265358979 / segments;
    // Start from top (-π/2)
    const startAngle = -3.14159265358979 / 2;

    for (int i = 0; i < segments; i++) {
      final filled = (i + 1) <= avgLevel.round();
      final color = filled ? _levelColor(avgLevel.round()) : AppColors.border;

      final paint = Paint()
        ..color = color
        ..strokeWidth = _arcStrokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCenter(center: center, width: _arcRadius * 2, height: _arcRadius * 2),
        startAngle + i * sweepAngle + 0.05,
        sweepAngle - 0.10,
        false,
        paint,
      );
    }

    // Level text in center
    final levelText = '${avgLevel.round()}';
    final tp = TextPainter(
      text: TextSpan(
        text: levelText,
        style: TextStyle(
          fontFamily: 'IBM Plex Mono',
          fontSize: 56,
          fontWeight: FontWeight.w700,
          color: _levelColor(avgLevel.round()),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center.translate(-tp.width / 2, -tp.height / 2));

    // "ENERGY" label below number
    final labelTp = TextPainter(
      text: const TextSpan(
        text: 'ENERGY',
        style: TextStyle(
          fontFamily: 'IBM Plex Mono',
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
          letterSpacing: 2.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelTp.paint(
      canvas,
      center.translate(-labelTp.width / 2, tp.height / 2 + 4),
    );
  }

  // ── Watermark ─────────────────────────────────────────────────────────────

  void _drawWatermark(Canvas canvas, Size size) {
    const text = 'TrackScope';
    final tp = TextPainter(
      text: const TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'IBM Plex Mono',
          fontSize: _watermarkFontSize,
          fontWeight: FontWeight.w400,
          color: AppColors.textMuted,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        size.width - tp.width - _padding / 2,
        size.height - tp.height - _padding / 2,
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  (double, double) _bpmRange() {
    final bpms = entries.map((e) => e.bpm).toList();
    var lo = bpms.reduce((a, b) => a < b ? a : b);
    var hi = bpms.reduce((a, b) => a > b ? a : b);
    if ((hi - lo) < _bpmRangePad * 2) {
      lo = lo - _bpmRangePad;
      hi = hi + _bpmRangePad;
    }
    return (lo, hi);
  }

  static Color _levelColor(int level) {
    if (level <= 3) return AppColors.danger;
    if (level <= 7) return AppColors.warning;
    return AppColors.accent;
  }

  @override
  bool shouldRepaint(SetEnergyCardPainter old) => old.entries != entries;
}
