// Hero BPM number widget — Design System v2.
//
// Three display modes:
//   idle      — no BPM available → shows "— — —" in dim #1E3530
//   detecting — BPM present, lock is stable   → accent teal
//   unstable  — BPM present, lock is unstable → amber + pill
//
// This widget renders DSP contract data only. BPM is always sourced from
// DspResult.primaryBpm — no hardcoded values, no random numbers.

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

enum BpmDisplayMode { idle, detecting, unstable }

class BpmHeroDisplay extends StatelessWidget {
  const BpmHeroDisplay({
    super.key,
    this.bpm,
    this.mode = BpmDisplayMode.idle,
  });

  /// Sourced from DspResult.primaryBpm. Null → shows "— — —".
  final double? bpm;
  final BpmDisplayMode mode;

  String get _text =>
      bpm != null ? bpm!.toStringAsFixed(1) : '— — —';

  Color get _color {
    if (bpm == null) return AppColors.bpmEmpty;
    return mode == BpmDisplayMode.unstable
        ? AppColors.amberText
        : AppColors.accent;
  }

  TextStyle get _style => bpm == null
      ? AppTextStyles.bpmEmptyHero
      : AppTextStyles.bpmHeroWith(_color);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: _style,
          child: Text(_text, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'BPM',
              style: AppTextStyles.mono(
                12, FontWeight.w400, AppColors.textSecondary,
                letterSpacing: 4,
              ),
            ),
            if (mode == BpmDisplayMode.unstable) ...[
              const SizedBox(width: 12),
              const _LockStatePill(
                text: 'нестабильно',
                style: _PillStyle.amber,
              ),
            ],
            const SizedBox(width: 12),
            Text(
              '155–230 · Hitech',
              style: AppTextStyles.mono(8, FontWeight.w400, AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Internal pill ─────────────────────────────────────────────────────────────

enum _PillStyle { amber }

class _LockStatePill extends StatelessWidget {
  const _LockStatePill({required this.text, required this.style});

  final String text;
  final _PillStyle style;

  @override
  Widget build(BuildContext context) {
    final color =
        style == _PillStyle.amber ? AppColors.amberText : AppColors.accent;
    final bg =
        style == _PillStyle.amber ? AppColors.amberBg : AppColors.accentDim;
    final borderColor = style == _PillStyle.amber
        ? AppColors.amber.withAlpha(76)
        : AppColors.accent.withAlpha(76);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(text, style: AppTextStyles.mono(8, FontWeight.w500, color)),
        ],
      ),
    );
  }
}
