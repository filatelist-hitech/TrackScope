// 7 px confidence bar with colour thresholds — Design System v2.
//
// Color rules: <30 % → red (danger), 30–70 % → yellow, >70 % → accent teal.
// Animated fill (400 ms) on confidence changes.

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class ConfidenceBar extends StatelessWidget {
  const ConfidenceBar({super.key, required this.confidence});

  /// Normalised 0.0–1.0 confidence from DspResult.
  final double confidence;

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).clamp(0.0, 100.0);
    final color = AppColors.confidence(pct);

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 7,
              child: Stack(
                children: [
                  Container(color: const Color(0xFF111916)),
                  FractionallySizedBox(
                    widthFactor: confidence.clamp(0.0, 1.0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        SizedBox(
          width: 36,
          child: Text(
            '${pct.toInt()}%',
            textAlign: TextAlign.right,
            style: AppTextStyles.mono(10, FontWeight.w500, color),
          ),
        ),
      ],
    );
  }
}
