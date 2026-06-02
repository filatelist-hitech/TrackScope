// Settings Screen — Design System v2, matching BPM Radar Prototype.html.
//
// Layout: section headers (s-hdr: 7px uppercase dim) + group cards
// (s-grp: #0d1712, r=13) + rows with dividers (s-row: 9px labels).
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
            10, FontWeight.w400, AppColors.textSecondary,
            letterSpacing: 0.18 * 10,
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.border),
        ),
      ),
      body: ListenableBuilder(
        listenable: AppSettings.instance,
        builder: (context, _) {
          final s = AppSettings.instance;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              // ── 1. АУДИО ──────────────────────────────────────────────
              const _SectionHeader('АУДИО'),
              _SettingsGroup(
                children: [
                  _InfoRow(
                    label: 'BPM Range',
                    value: flags.isPro ? '155–230' : '170–230',
                    badge: flags.isPro ? null : 'PRO',
                    showDivider: true,
                  ),
                  _SliderRow(
                    label: 'Чувствительность',
                    displayText: '${s.inputSensitivity >= 0 ? '+' : ''}'
                        '${s.inputSensitivity.toStringAsFixed(0)} dB',
                    value: s.inputSensitivity,
                    min: -6,
                    max: 6,
                    onChanged: (v) => s.setInputSensitivity(v),
                    showDivider: true,
                  ),
                  _SmoothingRow(
                    value: s.bpmSmoothing,
                    onChanged: (v) => s.setBpmSmoothing(v),
                    showDivider: false,
                  ),
                ],
              ),

              // ── 2. ВИЗУАЛИЗАЦИЯ ───────────────────────────────────────
              const _SectionHeader('ВИЗУАЛИЗАЦИЯ'),
              _SettingsGroup(
                children: [
                  _ToggleRow(
                    label: 'Волноформа',
                    value: s.showWaveform,
                    onChanged: (v) => s.setShowWaveform(v),
                    showDivider: true,
                  ),
                  _ToggleRow(
                    label: 'Спектр',
                    value: s.showSpectrum,
                    onChanged: (v) => s.setShowSpectrum(v),
                    showDivider: true,
                  ),
                  _ToggleRow(
                    label: 'Не гасить экран',
                    value: s.keepScreenOn,
                    onChanged: (v) async {
                      await s.setKeepScreenOn(v);
                      await WakelockPlus.toggle(enable: v);
                    },
                    showDivider: false,
                  ),
                ],
              ),

              // ── 3. PRO FEATURES ───────────────────────────────────────
              const _SectionHeader('PRO-ФУНКЦИИ'),
              _SettingsGroup(
                children: [
                  _NavRow(
                    label: 'Анализатор сигнала',
                    isPro: !flags.canAccessDebugScreen,
                    onTap: onSignalAnalyzerTap,
                    showDivider: true,
                  ),
                  _NavRow(
                    label: 'История сессий',
                    isPro: !flags.isPro,
                    onTap: onHistoryTap,
                    showDivider: false,
                  ),
                ],
              ),

              // ── 4. АККАУНТ ────────────────────────────────────────────
              const _SectionHeader('АККАУНТ'),
              _SettingsGroup(
                children: [
                  if (!flags.isPro)
                    _NavRow(
                      label: 'Upgrade to Pro',
                      labelColor: AppColors.accent,
                      onTap: onUpgradeTap,
                      showDivider: true,
                    ),
                  _NavRow(
                    label: 'Восстановить покупки',
                    labelColor: AppColors.textMuted,
                    onTap: () {},
                    showDivider: false,
                  ),
                ],
              ),

              // ── 5. ПРОЧЕЕ ─────────────────────────────────────────────
              const _SectionHeader('ПРОЧЕЕ'),
              _SettingsGroup(
                children: [
                  _NavRow(
                    label: 'Сбросить данные',
                    labelColor: AppColors.danger,
                    onTap: () => _confirmReset(context),
                    showDivider: false,
                  ),
                ],
              ),
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
          style: AppTextStyles.mono(
              12, FontWeight.w400, AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена',
                style: AppTextStyles.mono(
                    12, FontWeight.w400, AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              AppSettings.instance.resetAll();
            },
            child: Text('Сбросить',
                style: AppTextStyles.mono(
                    12, FontWeight.w500, AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

// ── Section header (s-hdr) ────────────────────────────────────────────────────
// 7px uppercase dim, 10px top / 20px side / 4px bottom — outside cards.

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Text(
        title,
        style: AppTextStyles.sectionLabel,
      ),
    );
  }
}

// ── Settings group card (s-grp) ───────────────────────────────────────────────
// bg #0d1712, r=13, margin 0 14px 4px, no outer border.

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1712),
        borderRadius: BorderRadius.circular(13),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

// ── Toggle row ────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.showDivider = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => onChanged(!value),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.mono(
                        12, FontWeight.w400, AppColors.textSecondary),
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeColor: AppColors.accent,
                  activeTrackColor: AppColors.accentDim,
                  inactiveTrackColor: const Color(0xFF1E3530),
                  inactiveThumbColor: AppColors.textMuted,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFF080C09)),
      ],
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
    this.showDivider = false,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String displayText;
  final ValueChanged<double> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: AppTextStyles.mono(
                      12, FontWeight.w400, AppColors.textSecondary)),
              Text(displayText,
                  style: AppTextStyles.mono(
                      11, FontWeight.w400, AppColors.accent)),
            ],
          ),
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.accent,
            inactiveTrackColor: const Color(0xFF111916),
            thumbColor: AppColors.accent,
            overlayColor: AppColors.accentDim,
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: SizedBox(
            height: 36,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: ((max - min) * 2).toInt(),
              onChanged: onChanged,
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFF080C09)),
      ],
    );
  }
}

// ── BPM Smoothing row ─────────────────────────────────────────────────────────

class _SmoothingRow extends StatelessWidget {
  const _SmoothingRow({
    required this.value,
    required this.onChanged,
    this.showDivider = false,
  });

  final BpmSmoothing value;
  final ValueChanged<BpmSmoothing> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Сглаживание BPM',
                  style: AppTextStyles.mono(
                      12, FontWeight.w400, AppColors.textSecondary),
                ),
              ),
              // Compact segment selector
              Row(
                children: BpmSmoothing.values.map((opt) {
                  final isOn = opt == value;
                  return GestureDetector(
                    onTap: () => onChanged(opt),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOn
                            ? AppColors.accentDim
                            : Colors.transparent,
                        border: Border.all(
                          color: isOn
                              ? AppColors.accent
                              : const Color(0xFF1E3530),
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        opt.label,
                        style: AppTextStyles.mono(
                          10, FontWeight.w400,
                          isOn ? AppColors.accent : AppColors.textMuted,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFF080C09)),
      ],
    );
  }
}

// ── Info row (read-only) ──────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.badge,
    this.showDivider = false,
  });

  final String label;
  final String value;
  final String? badge;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: AppTextStyles.mono(
                        12, FontWeight.w400, AppColors.textSecondary)),
              ),
              Text(value,
                  style: AppTextStyles.mono(
                      11, FontWeight.w400, AppColors.textMuted)),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accentDim,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(badge!,
                      style: AppTextStyles.mono(
                          8, FontWeight.w600, AppColors.accent)),
                ),
              ],
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFF080C09)),
      ],
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
    this.showDivider = false,
  });

  final String label;
  final VoidCallback onTap;
  final Color? labelColor;
  final bool isPro;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.mono(
                      9, FontWeight.w400,
                      labelColor ?? AppColors.textSecondary,
                    ),
                  ),
                ),
                if (isPro) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accentDim,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('PRO',
                        style: AppTextStyles.mono(
                            8, FontWeight.w600, AppColors.accent)),
                  ),
                ],
                Icon(
                  Icons.chevron_right,
                  color: AppColors.textMuted,
                  size: 13,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFF080C09)),
      ],
    );
  }
}
