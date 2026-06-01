// Custom Tab Bar — Design System v2.
//
// Three tabs: Радар / История / Настройки.
// Active tab: AppColors.accent. Inactive: AppColors.textMuted.
// Thin top border separates bar from content.

import 'package:flutter/material.dart';

import '../navigation/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.current,
    required this.onChanged,
  });

  final AppTab current;
  final ValueChanged<AppTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.borderFaint),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 16),
      child: Row(
        children: AppTab.values.map((tab) {
          return _TabItem(
            tab: tab,
            isActive: tab == current,
            onTap: () => onChanged(tab),
          );
        }).toList(),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.isActive,
    required this.onTap,
  });

  final AppTab tab;
  final bool isActive;
  final VoidCallback onTap;

  IconData get _icon {
    switch (tab) {
      case AppTab.radar:
        return Icons.gps_fixed;
      case AppTab.history:
        return Icons.history;
      case AppTab.settings:
        return Icons.settings_outlined;
    }
  }

  String get _label {
    switch (tab) {
      case AppTab.radar:
        return 'РАДАР';
      case AppTab.history:
        return 'ИСТОРИЯ';
      case AppTab.settings:
        return 'НАСТРОЙКИ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.accent : AppColors.textMuted;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _icon,
              size: 20,
              color: color,
            ),
            const SizedBox(height: 4),
            Text(
              _label,
              style: AppTextStyles.mono(
                8, FontWeight.w400, color,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
