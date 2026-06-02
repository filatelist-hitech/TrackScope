// Design tokens — Phase 7 legacy compatibility shim.
//
// AppTheme now forwards 1:1 to AppColors and AppTextStyles (Design System v2).
// New code should import AppColors / AppTextStyles directly.
// This file is kept so existing imports in main_screen.dart / paywall_screen.dart
// continue to compile without changes.

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

// Re-export so callers only need one import.
export '../theme/app_colors.dart';
export '../theme/app_text_styles.dart';

abstract final class AppTheme {
  // ── Backgrounds ──────────────────────────────────────────────────────────────
  static const background  = AppColors.background;
  static const surface     = AppColors.surface;
  static const surfaceHigh = AppColors.surfaceHigh;

  // ── Accent ───────────────────────────────────────────────────────────────────
  static const accent    = AppColors.accent;
  static const accentDim = AppColors.accentDim;

  // ── Semantic states ───────────────────────────────────────────────────────────
  static const danger     = AppColors.danger;
  static const dangerDim  = AppColors.dangerDim;
  static const warning    = AppColors.warning;
  static const warningDim = AppColors.warningDim;
  static const success    = AppColors.success;
  static const successDim = AppColors.successDim;
  static const noisePurple = AppColors.noisePurple;
  static const noiseDim   = AppColors.noiseDim;

  // ── Text ─────────────────────────────────────────────────────────────────────
  static const textPrimary   = AppColors.textPrimary;
  static const textSecondary = AppColors.textSecondary;
  static const textDim       = AppColors.textMuted;

  // ── Typography ───────────────────────────────────────────────────────────────
  /// IBM Plex Mono — forwards to AppTextStyles.mono().
  static TextStyle mono({
    double fontSize = 13,
    Color? color,
    FontWeight? weight,
    double? letterSpacing,
    double? height,
  }) =>
      AppTextStyles.mono(
        fontSize,
        weight ?? FontWeight.w400,
        color ?? AppColors.textPrimary,
        letterSpacing: letterSpacing,
      );
}
