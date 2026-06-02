import 'package:flutter/material.dart' show Color, EdgeInsets;

// Spacing and layout constants — Design System v2.1 (BPM Radar).
//
// Use these constants instead of magic numbers in Padding / SizedBox / EdgeInsets.
// Derived from the HTML prototype (.html files in design/).
//
// Usage:
//   Padding(padding: EdgeInsets.all(AppSpacing.md))
//   SizedBox(height: AppSpacing.sm)
//   EdgeInsets.symmetric(horizontal: AppSpacing.pagePad)

abstract final class AppSpacing {
  // ── Base unit ───────────────────────────────────────────────────────────────
  /// 4 px — atomic unit (xs).
  static const double xs = 4;

  /// 8 px — small gap between related elements.
  static const double sm = 8;

  /// 14 px — standard inter-element gap (used in stats grid, section gaps).
  static const double md = 14;

  /// 20 px — large gap (section padding, top-level spacing).
  static const double lg = 20;

  /// 32 px — page bottom padding, major section separation.
  static const double xl = 32;

  // ── Layout ──────────────────────────────────────────────────────────────────
  /// Horizontal page inset (screen edges).
  static const double pagePad = 14;

  /// Group card corner radius (sa-grp, hist-grp, s-grp).
  static const double cardRadius = 13;

  /// Small card corner radius (chips, badges).
  static const double chipRadius = 7;

  /// Standard inner padding for group card rows.
  static const EdgeInsets rowPad =
      EdgeInsets.symmetric(horizontal: 14, vertical: 11);

  /// Zone label row padding (WAVEFORM / LIVE SPECTRUM above viz panels).
  static const EdgeInsets zoneLabelPad =
      EdgeInsets.fromLTRB(2, 6, 2, 2);

  /// Section header padding (s-hdr outside cards).
  static const EdgeInsets sectionHeaderPad =
      EdgeInsets.fromLTRB(20, 14, 20, 4);

  // ── Confidence bar ──────────────────────────────────────────────────────────
  /// 7 px height — main radar screen confidence bar.
  static const double confBarHeight = 7;

  /// 3 px height — compact bars in history and signal analyzer.
  static const double confBarHeightCompact = 3;

  // ── Stat grid ───────────────────────────────────────────────────────────────
  /// Horizontal gap between 2-column stat cells.
  static const double statCellGap = 18;
}

// ── Divider constant ──────────────────────────────────────────────────────────
/// Standard in-group divider color (between sa-rows).
/// Usage: Divider(height: 1, thickness: 1, color: AppDivider.inGroup)
abstract final class AppDivider {
  static const inGroup = Color(0xFF080C09);
}
