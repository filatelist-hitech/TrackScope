// Break button — Design System v2.
//
// Icon (pause) + label "Зафиксировать брейк". Styled with surface bg and
// dim border; no accent fill — this is a secondary action.

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class BreakButton extends StatelessWidget {
  const BreakButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.bpmEmpty),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.pause_circle_outline,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              'Зафиксировать брейк',
              style: AppTextStyles.mono(
                8.5, FontWeight.w400, AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
