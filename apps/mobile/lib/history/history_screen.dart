// History screen — Design System v2, matching BPM Radar Prototype.html.
//
// Layout:
//   • Summary header: кол-во сэмплов / avg BPM / период — stat числа в 18px teal
//   • Export button в шапке (↑ Экспорт), только Pro
//   • Список сгруппирован по дням: СЕГОДНЯ / ВЧЕРА / РАНЕЕ
//   • Каждая группа — карточка sa-grp (#0d1712, r=13)
//   • Каждая строка: BPM 20px (teal/amber) + время + 3px conf bar
//   • Free tier: баннер лимита с переходом на paywall
//
// Все токены — AppColors + AppTextStyles (не AppTheme).
// Anti-fake: данные только из BpmHistory.

import 'package:flutter/material.dart' hide LockState;

import '../dsp/dsp_result.dart' show LockState;
import '../monetization/feature_flags.dart';
import '../monetization/paywall_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'bpm_history.dart';
import 'session_history_controller.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    super.key,
    required this.controller,
    required this.flags,
    required this.onExportCsv,
    required this.onExportJson,
  });

  final SessionHistoryController controller;
  final FeatureFlags flags;
  final VoidCallback onExportCsv;
  final VoidCallback onExportJson;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final samples = controller.history.samples;
            final grouped = _groupByDay(samples);

            return Column(
              children: [
                // ── Summary header ────────────────────────────────────────
                _SummaryHeader(
                  samples: samples,
                  canExport: flags.canExport,
                  onExportCsv: onExportCsv,
                  onExportJson: onExportJson,
                ),

                // ── Free tier limit banner ────────────────────────────────
                if (!flags.canExport && controller.isAtLimit)
                  _CapBanner(onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PaywallScreen(feature: 'history'),
                    ));
                  }),

                const Divider(height: 1, thickness: 1, color: AppColors.border),

                // ── Grouped history list ──────────────────────────────────
                Expanded(
                  child: samples.isEmpty
                      ? _EmptyState()
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            for (final group in grouped) ...[
                              _DayLabel(label: group.label),
                              _HistoryGroup(samples: group.samples),
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Groups samples newest-first into TODAY / YESTERDAY / EARLIER.
  List<_DayGroup> _groupByDay(List<BpmSample> samples) {
    if (samples.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final todayItems = <BpmSample>[];
    final yestItems = <BpmSample>[];
    final olderItems = <BpmSample>[];

    // Newest first
    for (final s in samples.reversed) {
      final d = DateTime(s.timestamp.year, s.timestamp.month, s.timestamp.day);
      if (!d.isBefore(today)) {
        todayItems.add(s);
      } else if (!d.isBefore(yesterday)) {
        yestItems.add(s);
      } else {
        olderItems.add(s);
      }
    }

    return [
      if (todayItems.isNotEmpty) _DayGroup('СЕГОДНЯ', todayItems),
      if (yestItems.isNotEmpty) _DayGroup('ВЧЕРА', yestItems),
      if (olderItems.isNotEmpty) _DayGroup('РАНЕЕ', olderItems),
    ];
  }
}

// ── Data helpers ──────────────────────────────────────────────────────────────

class _DayGroup {
  const _DayGroup(this.label, this.samples);
  final String label;
  final List<BpmSample> samples;
}

// ── Summary header ────────────────────────────────────────────────────────────
// hist-top: stat numbers 18px teal + labels 6.5px dim + export button

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.samples,
    required this.canExport,
    required this.onExportCsv,
    required this.onExportJson,
  });

  final List<BpmSample> samples;
  final bool canExport;
  final VoidCallback onExportCsv;
  final VoidCallback onExportJson;

  String get _avgBpm {
    if (samples.isEmpty) return '—';
    final avg = samples.map((s) => s.bpm).reduce((a, b) => a + b) /
        samples.length;
    return avg.toStringAsFixed(1);
  }

  String get _period {
    if (samples.isEmpty) return '—';
    final oldest = samples.first.timestamp;
    final newest = samples.last.timestamp;
    final diff = newest.difference(oldest);
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return m > 0 ? '${h}ч ${m}м' : '${h}ч';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Expanded(
            child: Row(
              children: [
                _StatCell(value: '${samples.length}', label: 'СЭМПЛОВ'),
                const SizedBox(width: 22),
                _StatCell(value: _avgBpm, label: 'AVG BPM'),
                const SizedBox(width: 22),
                _StatCell(value: _period, label: 'ПЕРИОД'),
              ],
            ),
          ),
          // Export button — only Pro
          if (canExport)
            _ExportButton(onCsv: onExportCsv, onJson: onExportJson),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTextStyles.mono(
              18, FontWeight.w600, AppColors.accent,
              letterSpacing: -0.5),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: AppTextStyles.mono(
              6.5, FontWeight.w400, AppColors.textMuted,
              letterSpacing: 0.12 * 6.5),
        ),
      ],
    );
  }
}

// Export button matching .exp-btn style
class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.onCsv, required this.onJson});
  final VoidCallback onCsv;
  final VoidCallback onJson;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) => v == 'csv' ? onCsv() : onJson(),
      color: const Color(0xFF0D1712),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1712),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1E3530)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.upload_outlined,
                size: 12, color: AppColors.textSecondary),
            const SizedBox(width: 5),
            Text('Экспорт',
                style: AppTextStyles.mono(
                    8, FontWeight.w400, AppColors.textSecondary)),
          ],
        ),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'csv',
          child: Text('CSV',
              style: AppTextStyles.mono(
                  12, FontWeight.w400, AppColors.textSecondary)),
        ),
        PopupMenuItem(
          value: 'json',
          child: Text('JSON',
              style: AppTextStyles.mono(
                  12, FontWeight.w400, AppColors.textSecondary)),
        ),
      ],
    );
  }
}

// ── Day label (datelbl) ───────────────────────────────────────────────────────

class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 3),
      child: Text(
        label,
        style: AppTextStyles.mono(
            7, FontWeight.w400, AppColors.textMuted,
            letterSpacing: 0.14 * 7),
      ),
    );
  }
}

// ── History group card (hist-grp) ─────────────────────────────────────────────

class _HistoryGroup extends StatelessWidget {
  const _HistoryGroup({required this.samples});
  final List<BpmSample> samples;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1712),
        borderRadius: BorderRadius.circular(13),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < samples.length; i++) ...[
            _HistoryRow(
              sample: samples[i],
              showDivider: i < samples.length - 1,
            ),
          ],
        ],
      ),
    );
  }
}

// ── History row (hist-item) ───────────────────────────────────────────────────
// BPM 20px (teal if stable/locking, amber if unstable) + time + 3px conf bar

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.sample, this.showDivider = false});
  final BpmSample sample;
  final bool showDivider;

  Color get _bpmColor {
    final ls = sample.lockState;
    if (ls == LockState.stable || ls == LockState.locking) {
      return AppColors.accent;
    }
    if (ls == LockState.unstable) return AppColors.amberText;
    return AppColors.textSecondary;
  }

  Color get _confBarColor {
    final c = sample.confidence;
    if (c < 0.3) return AppColors.danger;
    if (c < 0.7) return AppColors.yellow;
    return AppColors.accent;
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // BPM number — 20px semibold, 58px wide
              SizedBox(
                width: 58,
                child: Text(
                  sample.bpm.toStringAsFixed(1),
                  style: AppTextStyles.mono(
                      20, FontWeight.w600, _bpmColor,
                      letterSpacing: -0.5),
                ),
              ),
              const SizedBox(width: 12),
              // Meta: time + confidence bar
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatTime(sample.timestamp),
                      style: AppTextStyles.mono(
                          8.5, FontWeight.w400, AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    // 3px confidence bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          value: sample.confidence.clamp(0.0, 1.0),
                          backgroundColor: const Color(0xFF111916),
                          valueColor: AlwaysStoppedAnimation<Color>(
                              _confBarColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
              height: 1, thickness: 1, color: Color(0xFF080C09),
              indent: 0, endIndent: 0),
      ],
    );
  }
}

// ── Cap banner (Free tier limit) ──────────────────────────────────────────────

class _CapBanner extends StatelessWidget {
  const _CapBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.amberBg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          child: Row(
            children: [
              const Icon(Icons.lock_outline,
                  color: AppColors.amberText, size: 14),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '30 сек · Upgrade для unlimited истории',
                  style: AppTextStyles.mono(
                      8.5, FontWeight.w400, AppColors.amberText),
                ),
              ),
              Text('›',
                  style: AppTextStyles.mono(
                      14, FontWeight.w400, AppColors.amberText)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '—',
            style: AppTextStyles.mono(
                32, FontWeight.w300, AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            'История пуста',
            style: AppTextStyles.mono(
                11, FontWeight.w400, AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            'Начни захват, чтобы появились записи',
            style: AppTextStyles.mono(
                9, FontWeight.w400, AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
