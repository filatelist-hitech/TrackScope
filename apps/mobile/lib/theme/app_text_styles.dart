// Typography tokens — Design System v2 (BPM Radar Prototype.html).
//
// Font: IBM Plex Mono (google_fonts). All roles defined here;
// never construct GoogleFonts.ibmPlexMono() inline in widgets.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTextStyles {
  // ── Base factory ─────────────────────────────────────────────────────────────
  static TextStyle mono(
    double size,
    FontWeight weight,
    Color color, {
    double? letterSpacing,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  // ── Named roles ───────────────────────────────────────────────────────────────

  /// 72 px semibold teal — main BPM number when STABLE/LOCKING.
  static TextStyle get bpmHero =>
      mono(72, FontWeight.w600, AppColors.accent, letterSpacing: -2.5);

  /// Same geometry but custom colour (amber for UNSTABLE, etc.).
  static TextStyle bpmHeroWith(Color color) =>
      mono(72, FontWeight.w600, color, letterSpacing: -2.5);

  /// 58 px dimmed — "— — —" placeholder before first lock.
  static TextStyle get bpmEmptyHero =>
      mono(58, FontWeight.w600, AppColors.bpmEmpty, letterSpacing: -1.5);

  /// 10 px — tab labels.
  static TextStyle get navTitle =>
      mono(10, FontWeight.w400, const Color(0xFF7AB8AA), letterSpacing: 3.0);

  /// 7.5 px caps — zone labels (WAVEFORM, SPECTRUM, etc.).
  static TextStyle get sectionLabel =>
      mono(7.5, FontWeight.w400, AppColors.textMuted, letterSpacing: 2.5);

  /// 13 px — numeric data values in info card.
  static TextStyle get statsValue =>
      mono(13, FontWeight.w400, AppColors.textSecondary);

  /// 8 px — metric labels under values.
  static TextStyle get statsLabel =>
      mono(8, FontWeight.w400, AppColors.textMuted, letterSpacing: 1.2);

  /// 10 px semibold black — primary CTA (paywall buttons).
  static TextStyle get ctaButton => mono(10, FontWeight.w600, Colors.black);
}
