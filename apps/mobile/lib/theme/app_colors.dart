// Design tokens — Design System v2 (BPM Radar Prototype.html).
//
// Source of truth: #050807 background, #0c1410 surface, #00dfb0 accent.
// Keep this file import-only. Never redeclare these colours in widgets.

import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── Backgrounds ──────────────────────────────────────────────────────────────
  static const background = Color(0xFF050807);
  static const surface = Color(0xFF0C1410);
  static const surface2 = Color(0xFF0D1712);
  static const surfaceHigh = Color(0xFF0F1810); // elevated surface (badge fills)

  // ── Accent ───────────────────────────────────────────────────────────────────
  static const accent = Color(0xFF00DFB0);
  static const accentDim = Color(0x1A00DFB0); // 10 % alpha

  // ── Semantic ─────────────────────────────────────────────────────────────────
  static const amber = Color(0xFFC8A020);
  static const amberText = Color(0xFFFFE090);
  static const amberBg = Color(0x1EC8A020); // 12 % alpha
  static const danger = Color(0xFFE04040);
  static const dangerDim = Color(0x33E04040); // 20 % alpha
  static const yellow = Color(0xFFE0B020);
  static const warning = Color(0xFFE0B020);     // alias for yellow
  static const warningDim = Color(0x33E0B020);  // 20 % alpha
  static const success = Color(0xFF00C853);
  static const successDim = Color(0x3300C853);  // 20 % alpha
  static const noisePurple = Color(0xFF9B59B6);
  static const noiseDim = Color(0x339B59B6);    // 20 % alpha

  // ── Text ─────────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFC8DCD8);
  static const textSecondary = Color(0xFF3A6858);
  static const textMuted = Color(0xFF1A3028);

  // ── Borders ──────────────────────────────────────────────────────────────────
  static const border = Color(0xFF182820);
  static const borderFaint = Color(0xFF0F1712);

  // ── BPM empty state ───────────────────────────────────────────────────────────
  static const bpmEmpty = Color(0xFF1E3530);

  // ── Dynamic helpers ───────────────────────────────────────────────────────────

  /// Confidence bar / percentage colour by threshold.
  static Color confidence(double pct) {
    if (pct < 30) return danger;
    if (pct < 70) return yellow;
    return accent;
  }

  /// BPM text colour driven by display state.
  static Color bpmText({required bool hasValue, required bool isUnstable}) {
    if (!hasValue) return bpmEmpty;
    if (isUnstable) return amberText;
    return accent;
  }
}
