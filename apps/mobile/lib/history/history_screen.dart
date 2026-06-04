// History screen — Design System v2, session-based view.
//
// Layout:
//   • Summary header: кол-во сессий / avg BPM / period — stat числа 18px teal
//   • Export button в шапке (↑ Экспорт), только Pro
//   • Список SessionCard, свежие сверху
//   • Tap на карточку → SessionDetailScreen
//
// Все токены — AppColors + AppTextStyles.
// Anti-fake: данные только из SessionHistoryController.allSessions.

import 'package:flutter/material.dart' hide LockState;

import '../monetization/feature_flags.dart';
import '../monetization/paywall_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'session.dart';
import 'session_detail_screen.dart';
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
            final sessions = controller.allSessions;

            return Column(
              children: [
                _SummaryHeader(
                  sessions: sessions,
                  canExport: flags.canExport,
                  onExportCsv: onExportCsv,
                  onExportJson: onExportJson,
                ),

                if (!flags.canExport && controller.isAtLimit)
                  _CapBanner(onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PaywallScreen(feature: 'history'),
                    ));
                  }),

                const Divider(height: 1, thickness: 1, color: AppColors.border),

                Expanded(
                  child: sessions.isEmpty
                      ? _EmptyState()
                      : ListView.builder(
                          padding: EdgeInsets.only(
                            top: 8,
                            bottom: 24 + MediaQuery.paddingOf(context).bottom,
                          ),
                          itemCount: sessions.length,
                          itemBuilder: (_, i) => _SessionCard(
                            session: sessions[i],
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    SessionDetailScreen(session: sessions[i]),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Summary header ────────────────────────────────────────────────────────────

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.sessions,
    required this.canExport,
    required this.onExportCsv,
    required this.onExportJson,
  });

  final List<Session> sessions;
  final bool canExport;
  final VoidCallback onExportCsv;
  final VoidCallback onExportJson;

  String get _avgBpm {
    final allSnaps = sessions.expand((s) => s.snapshots).toList();
    if (allSnaps.isEmpty) return '—';
    final avg =
        allSnaps.map((s) => s.bpm).reduce((a, b) => a + b) / allSnaps.length;
    return avg.toStringAsFixed(1);
  }

  String get _period {
    if (sessions.isEmpty) return '—';
    final times = sessions.map((s) => s.startTime).toList();
    final oldest = times.reduce((a, b) => a.isBefore(b) ? a : b);
    final diff = DateTime.now().difference(oldest);
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
          Expanded(
            child: Row(
              children: [
                _StatCell(value: '${sessions.length}', label: 'СЕССИЙ'),
                const SizedBox(width: 22),
                _StatCell(value: _avgBpm, label: 'AVG BPM'),
                const SizedBox(width: 22),
                _StatCell(value: _period, label: 'ПЕРИОД'),
              ],
            ),
          ),
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
        Text(value,
            style: AppTextStyles.mono(18, FontWeight.w600, AppColors.accent,
                letterSpacing: -0.5)),
        const SizedBox(height: 1),
        Text(label,
            style: AppTextStyles.mono(6.5, FontWeight.w400, AppColors.textMuted,
                letterSpacing: 0.12 * 6.5)),
      ],
    );
  }
}

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

// ── Session card ──────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onTap});
  final Session session;
  final VoidCallback onTap;

  String _durStr() {
    final d = session.duration;
    if (d.inSeconds < 60) return '< 1 мин';
    if (d.inHours < 1) return '${d.inMinutes} мин';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m > 0 ? '${h}ч ${m}м' : '${h}ч';
  }

  String _startStr() {
    final dt = session.startTime;
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _bpmRange() {
    if (!session.hasData) return '—';
    final lo = session.minBpm.toStringAsFixed(0);
    final hi = session.maxBpm.toStringAsFixed(0);
    return lo == hi ? lo : '$lo–$hi';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1712),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            // Left: time + duration
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_startStr(),
                    style: AppTextStyles.mono(
                        20, FontWeight.w600, AppColors.accent,
                        letterSpacing: -0.5)),
                const SizedBox(height: 2),
                Text(_durStr(),
                    style: AppTextStyles.mono(
                        8.5, FontWeight.w400, AppColors.textMuted)),
              ],
            ),
            const SizedBox(width: 16),
            // Center: BPM range + confidence
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('BPM ',
                          style: AppTextStyles.mono(
                              8.5, FontWeight.w400, AppColors.textMuted)),
                      Text(_bpmRange(),
                          style: AppTextStyles.mono(
                              13, FontWeight.w600, AppColors.textSecondary,
                              letterSpacing: -0.3)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('ПИК ',
                          style: AppTextStyles.mono(
                              8.5, FontWeight.w400, AppColors.textMuted)),
                      Text(
                        session.hasData
                            ? '${(session.peakConfidence * 100).toStringAsFixed(0)}%'
                            : '—',
                        style: AppTextStyles.mono(
                            11, FontWeight.w500, AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Right: snapshot count + chevron
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${session.snapshots.length}',
                    style: AppTextStyles.mono(
                        16, FontWeight.w600, AppColors.textSecondary)),
                Text('снимков',
                    style: AppTextStyles.mono(
                        7, FontWeight.w400, AppColors.textMuted)),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Cap banner ────────────────────────────────────────────────────────────────

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
          Text('—',
              style: AppTextStyles.mono(32, FontWeight.w300, AppColors.textMuted)),
          const SizedBox(height: 8),
          Text('История пуста',
              style: AppTextStyles.mono(11, FontWeight.w400, AppColors.textMuted)),
          const SizedBox(height: 4),
          Text('Начни захват, чтобы появились записи',
              style: AppTextStyles.mono(9, FontWeight.w400, AppColors.textMuted)),
        ],
      ),
    );
  }
}
