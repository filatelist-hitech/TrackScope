// SessionDetailScreen — детальный просмотр одной сессии.
//
// Показывает BPM-линию по времени и список снимков.
// Все данные из Session — нет BPM-вычислений в UI.

import 'package:flutter/material.dart' hide LockState;

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'session.dart';

class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final snaps = session.snapshots;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _formatDateTime(session.startTime),
          style: AppTextStyles.mono(12, FontWeight.w500, AppColors.textSecondary),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Stats bar ─────────────────────────────────────────────────
            _StatsBar(session: session),
            const Divider(height: 1, thickness: 1, color: AppColors.border),

            // ── BPM chart ─────────────────────────────────────────────────
            if (snaps.length >= 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: SizedBox(
                  height: 80,
                  child: CustomPaint(
                    painter: _BpmLinePainter(snaps),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),

            const Divider(height: 1, thickness: 1, color: AppColors.border),

            // ── Snapshot list ──────────────────────────────────────────────
            Expanded(
              child: snaps.isEmpty
                  ? Center(
                      child: Text('Нет данных',
                          style: AppTextStyles.mono(11, FontWeight.w400, AppColors.textMuted)),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: 24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: snaps.length,
                      itemBuilder: (_, i) => _SnapshotRow(
                        snap: snaps[snaps.length - 1 - i],
                        showDivider: i < snaps.length - 1,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final mon = dt.month.toString().padLeft(2, '0');
    return '$day.$mon  $h:$m';
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.session});
  final Session session;

  String _durStr() {
    final d = session.duration;
    if (d.inMinutes < 1) return '< 1 мин';
    if (d.inHours < 1) return '${d.inMinutes} мин';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m > 0 ? '${h}ч ${m}м' : '${h}ч';
  }

  @override
  Widget build(BuildContext context) {
    final hasData = session.hasData;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          _StatCell(value: _durStr(), label: 'ДЛИТ'),
          const SizedBox(width: 20),
          _StatCell(
            value: hasData
                ? '${session.minBpm.toStringAsFixed(0)}–${session.maxBpm.toStringAsFixed(0)}'
                : '—',
            label: 'BPM',
          ),
          const SizedBox(width: 20),
          _StatCell(
            value: hasData
                ? '${(session.peakConfidence * 100).toStringAsFixed(0)}%'
                : '—',
            label: 'ПИКОВАЯ',
          ),
          const SizedBox(width: 20),
          _StatCell(
            value: '${session.snapshots.length}',
            label: 'СНИМКОВ',
          ),
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
            style: AppTextStyles.mono(16, FontWeight.w600, AppColors.accent,
                letterSpacing: -0.5)),
        const SizedBox(height: 1),
        Text(label,
            style: AppTextStyles.mono(6.5, FontWeight.w400, AppColors.textMuted,
                letterSpacing: 0.8)),
      ],
    );
  }
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({required this.snap, this.showDivider = false});
  final SessionSnapshot snap;
  final bool showDivider;

  Color get _bpmColor {
    if (snap.confidence > 0.65) return AppColors.accent;
    if (snap.confidence > 0.4) return AppColors.amberText;
    return AppColors.textSecondary;
  }

  String _fmt(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  snap.bpm.toStringAsFixed(1),
                  style: AppTextStyles.mono(18, FontWeight.w600, _bpmColor,
                      letterSpacing: -0.5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fmt(snap.timestamp),
                        style: AppTextStyles.mono(
                            8.5, FontWeight.w400, AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          value: snap.confidence.clamp(0.0, 1.0),
                          backgroundColor: const Color(0xFF111916),
                          valueColor: AlwaysStoppedAnimation<Color>(_bpmColor),
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

/// Рисует BPM-линию за сессию.
class _BpmLinePainter extends CustomPainter {
  _BpmLinePainter(this.snaps);
  final List<SessionSnapshot> snaps;

  @override
  void paint(Canvas canvas, Size size) {
    if (snaps.length < 2) return;

    final bpms = snaps.map((s) => s.bpm).toList();
    final minB = bpms.reduce((a, b) => a < b ? a : b);
    final maxB = bpms.reduce((a, b) => a > b ? a : b);
    final range = (maxB - minB).clamp(1.0, double.infinity);

    final paint = Paint()
      ..color = AppColors.accent.withAlpha(200)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (int i = 0; i < snaps.length; i++) {
      final x = i / (snaps.length - 1) * size.width;
      final y = (1 - (snaps[i].bpm - minB) / range) * size.height * 0.9 +
          size.height * 0.05;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BpmLinePainter old) => old.snaps != snaps;
}
