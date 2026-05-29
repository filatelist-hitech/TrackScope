// Design tokens for hitech-bpm-radar Phase 7 UI.
//
// Single source of truth for colours and monospace typography.
// Import this file wherever AppTheme is needed; never redeclare colours
// in individual widgets.
//
// Colour naming convention:
//   <role>      – full-strength colour (for text / fills)
//   <role>Dim   – 20 % alpha overlay (for badge backgrounds)

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTheme {
  // ── Backgrounds ──────────────────────────────────────────────────────────────
  /// Page background — nearly-black with a blue tint.
  static const background = Color(0xFF07070F);

  /// Card/panel surface.
  static const surface = Color(0xFF0F0F1A);

  /// Elevated surface (e.g. badge fill for neutral states).
  static const surfaceHigh = Color(0xFF161625);

  // ── Accent (one colour for the entire app) ───────────────────────────────────
  static const accent = Color(0xFF00E5CC);
  static const accentDim = Color(0x3300E5CC); // 20 % alpha

  // ── Semantic states ───────────────────────────────────────────────────────────
  static const danger = Color(0xFFFF4444);
  static const dangerDim = Color(0x33FF4444);

  static const warning = Color(0xFFFFB300);
  static const warningDim = Color(0x33FFB300);

  static const success = Color(0xFF00C853);
  static const successDim = Color(0x3300C853);

  static const noisePurple = Color(0xFF9B59B6);
  static const noiseDim = Color(0x336A0DAD);

  // ── Text ─────────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFF0F0FF);
  static const textSecondary = Color(0xFF8888AA);
  static const textDim = Color(0xFF44445A);

  // ── Typography ───────────────────────────────────────────────────────────────
  /// JetBrains Mono — used for BPM numerals and all numeric metric values.
  /// Falls back to the system monospace font when the Google Fonts asset is
  /// unavailable (e.g. offline first launch, widget tests).
  static TextStyle mono({
    double fontSize = 13,
    Color? color,
    FontWeight? weight,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        color: color ?? textPrimary,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
      );
}
