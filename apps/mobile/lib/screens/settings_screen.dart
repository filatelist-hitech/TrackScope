// Settings Screen — Design System v2.
//
// 5 sections: АУДИО / ВИЗУАЛИЗАЦИЯ / PRO FEATURES / АККАУНТ / ПРОЧЕЕ.
// Backed by AppSettings (SharedPreferences). Keep Screen On via WakelockPlus.

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../monetization/feature_flags.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.flags,
    required this.onSignalAnalyzerTap,
    required this.onHistoryTap,
    required this.onUpgradeTap,
  });

  final FeatureFlags flags;
  final VoidCallback onSignalAnalyzerTap;
  final VoidCallback onHistoryTap;
  final VoidCallback onUpgradeTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          'НАСТРОЙКИ',
          style: AppTextStyles.mono(
            11, FontWeight.w400, AppColors.textSecondary,
            letterSpacing: 3,
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderFaint),
        ),
      ),
      body: ListenableBuilder(
        listenable: AppSettings.instance,
        builder: (context, _) {
          final s = AppSettings.instance;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // ── 1. АУДИО ─────────────────────────────────────────────────
              const _SectionHeader('АУДИО'),
              _InfoRow(
                label: 'BPM Range',
                value: flags.isPro ? '155–230' : '170–230',
                badge: flags.isPro ? null : 'PRO',
              ),
              _SliderRow(
                label: 'Input Sensitivity',
                value: s.inputSensitivity,
                min: -6,
                max: 6,
                displayText: '${s.inputSensitivity >= 0 ? '+' : ''}'
                    '${s.inputSensitivity.toStringAsFixed(0)} dB',
                onChanged: (v) => s.setInputSensitivity(v),
              ),

              // ── 2. ВИЗУАЛИЗАЦИЯ ───────────────────────────────────────────
              const _SectionHeader('ВИЗУАЛИЗАЦИЯ'),
              _ToggleRow(
                label: 'Волноформа',
                value: s.showWaveform,
                onChanged: (v) => s.setShowWaveform(v),
              ),
              _ToggleRow(
                label: 'Спектр',
                value: s.showSpectrum,
                onChanged: (v) => s.setShowSpectrum(v),
              ),
              _ToggleRow(
                label: 'Не гасить экран',
                value: s.keepScreenOn,
                onChanged: (v) async {
                  await s.setKeepScreenOn(v);
                  await WakelockPlus.toggle(enable: v);
                },
              ),

              // ── 3. PRO FEATURES ───────────────────────────────────────────
              const _SectionHeader('PRO FEATURES'),
              _NavRow(
                label: 'Signal Analyzer',
                isPro: !flags.canAccessDebugScreen,
                onTap: onSignalAnalyzerTap,
              ),
              _NavRow(
                label: 'История сессий',
                isPro: !flags.isPro,
                onTap: onHistoryTap,
              ),

              // ── 4. АККАУНТ ────────────────────────────────────────────────
              const _SectionHeader('АККАУНТ'),
              if (!flags.isPro)
                _NavRow(
                  label: 'Upgrade to Pro',
                  labelColor: AppColors.accent,
                  onTap: onUpgradeTap,
                ),
              _NavRow(
                label: 'Restore purchases',
                labelColor: AppColors.textMuted,
                onTap: () {},
              ),

              // ── 5. ПРОЧЕЕ ─────────────────────────────────────────────────
              const _SectionHeader('ПРОЧЕЕ'),
              _NavRow(
                label: 'Сбросить данные',
                labelColor: AppColors.danger,
                onTap: () => _confirmReset(context),
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Сбросить данные?',
          style: AppTextStyles.mono(14, FontWeight.w500, AppColors.textPrimary),
        ),
        content: Text(
          'Все настройки и история будут удалены.',
          style: AppTextStyles.mono(12, FontWeight.w400, AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Отмена',
              style: AppTextStyles.mono(12, FontWeight.w400, AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              AppSettings.instance.resetAll();
            },
            child: Text(
              'Сбросить',
              style: AppTextStyles.mono(12, FontWeight.w500, AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(title, style: AppTextStyles.sectionLabel),
    );
  }
}

// ── Toggle row ────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.mono(12, FontWeight.w400, AppColors.textPrimary),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.accent,
            inactiveTrackColor: AppColors.surface2,
          ),
        ],
      ),
    );
  }
}

// ── Slider row ────────────────────────────────────────────────────────────────

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.displayText,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String displayText;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: AppTextStyles.mono(
                      12, FontWeight.w400, AppColors.textPrimary)),
              Text(displayText,
                  style: AppTextStyles.mono(
                      11, FontWeight.w400, AppColors.textSecondary)),
            ],
          ),
          SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.surface2,
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accentDim,
              trackHeight: 2,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: ((max - min) * 2).toInt(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info row (read-only) ──────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.badge});

  final String label;
  final String value;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.mono(12, FontWeight.w400, AppColors.textPrimary),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.mono(11, FontWeight.w400, AppColors.textSecondary),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge!,
                style: AppTextStyles.mono(8, FontWeight.w600, AppColors.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Nav row (tappable) ────────────────────────────────────────────────────────

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.label,
    required this.onTap,
    this.labelColor,
    this.isPro = false,
  });

  final String label;
  final VoidCallback onTap;
  final Color? labelColor;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.mono(
                  12, FontWeight.w400,
                  labelColor ?? AppColors.textPrimary,
                ),
              ),
            ),
            if (isPro)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accentDim,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'PRO',
                  style: AppTextStyles.mono(8, FontWeight.w600, AppColors.accent),
                ),
              ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 16),
          ],
        ),
      ),
    );
  }
}
