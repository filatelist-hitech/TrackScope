// Typography tokens — Design System v2.2 (BPM Radar).
//
// Scale (IBM Plex Mono):
//   micro      11 px  — zone labels (WAVEFORM, SPECTRUM), section headers
//   caption    12 px  — meta text, listening indicator, time labels
//   body       14 px  — settings rows, stats labels, secondary info
//   value      18 px  — stats values in info card
//   subhead    15 px  — signal analyzer metrics labels
//   title      13 px  — AppBar subtitle, paywall feature labels
//   cta        12 px  semibold — buttons, badges
//   hero       72 px  — main BPM number (STABLE)
//   heroEmpty  58 px  — "— — —" placeholder
//
// All roles defined here — never construct GoogleFonts.ibmPlexMono() inline.

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

  // ── Type scale constants ──────────────────────────────────────────────────────
  /// 11 px — smallest visible label (zone labels, section headers)
  static const double szMicro = 11;

  /// 12 px — meta / caption text (indicator labels, time axis)
  static const double szCaption = 12;

  /// 14 px — body text (settings row labels, stats labels)
  static const double szBody = 14;

  /// 15 px — sub-heading (signal analyzer, section titles in screens)
  static const double szSubhead = 15;

  /// 18 px — numeric data values (info card stats)
  static const double szValue = 18;

  /// 13 px — app bar titles, feature list items
  static const double szTitle = 13;

  // ── Named roles ───────────────────────────────────────────────────────────────

  /// 72 px semibold teal — main BPM number when STABLE/LOCKING.
  static TextStyle get bpmHero =>
      mono(72, FontWeight.w600, AppColors.accent, letterSpacing: -2.5);

  /// Same geometry with custom colour (amber for UNSTABLE, etc.).
  static TextStyle bpmHeroWith(Color color) =>
      mono(72, FontWeight.w600, color, letterSpacing: -2.5);

  /// 58 px dimmed — "— — —" placeholder before first lock.
  static TextStyle get bpmEmptyHero =>
      mono(58, FontWeight.w600, AppColors.bpmEmpty, letterSpacing: -1.5);

  /// 10 px — AppBar nav title colour #7AB8AA.
  static TextStyle get navTitle =>
      mono(szCaption, FontWeight.w400, const Color(0xFF7AB8AA),
          letterSpacing: 3.0);

  /// 9 px caps dim — zone labels (WAVEFORM, LIVE SPECTRUM) outside panels.
  static TextStyle get sectionLabel =>
      mono(szMicro, FontWeight.w400, AppColors.textMuted, letterSpacing: 1.4);

  /// 15 px — numeric values in info card (BPM, dBFS, noise level, etc.).
  static TextStyle get statsValue =>
      mono(szValue, FontWeight.w400, AppColors.textSecondary);

  /// 10 px caps dim — metric labels above/below values in info card.
  static TextStyle get statsLabel =>
      mono(szCaption, FontWeight.w400, AppColors.textMuted, letterSpacing: 1.0);

  /// 12 px — settings row labels, body text throughout the app.
  static TextStyle get bodyRow =>
      mono(szBody, FontWeight.w400, AppColors.textSecondary);

  /// 12 px semibold black — primary CTA (paywall buttons).
  static TextStyle get ctaButton => mono(szCaption, FontWeight.w600, Colors.black);

  /// 10 px — general caption / meta text.
  static TextStyle get caption =>
      mono(szCaption, FontWeight.w400, AppColors.textMuted);
}
