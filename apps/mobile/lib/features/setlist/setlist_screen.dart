// SetlistScreen — Pro-only экран записи сетлиста.
//
// REC/STOP button → SetlistService.startRecording / stopRecording.
// Записи: таблица строк (время + BPM + confidence + состояние).
// Export: CSV и JSON через share_plus.
// Free tier: автоматически показывает PaywallScreen.

import 'dart:io';

import 'package:flutter/material.dart' hide LockState;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../dsp/dsp_result.dart';
import '../../monetization/feature_flags.dart';
import '../../monetization/paywall_screen.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'setlist_entry.dart';
import 'setlist_service.dart';

class SetlistScreen extends StatelessWidget {
  const SetlistScreen({
    super.key,
    required this.service,
    required this.flags,
  });

  final SetlistService service;
  final FeatureFlags flags;

  @override
  Widget build(BuildContext context) {
    if (!flags.canAccessSetlist) {
      return const PaywallScreen(feature: 'setlist');
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => _SetlistView(service: service),
    );
  }
}

class _SetlistView extends StatelessWidget {
  const _SetlistView({required this.service});
  final SetlistService service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
        title: Text(
          'СЕТЛИСТ',
          style: AppTextStyles.mono(
            11, FontWeight.w600, const Color(0xFF7AB8AA),
            letterSpacing: 0.18 * 11,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.border),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              'PRO',
              style: AppTextStyles.mono(9, FontWeight.w700, AppColors.accent),
            ),
          ),
          if (service.entries.isNotEmpty) ...[
            _ExportButton(
              icon: Icons.file_download_outlined,
              tooltip: 'Экспорт CSV',
              onTap: () => _exportCsv(context, service.entries),
            ),
            _ExportButton(
              icon: Icons.data_object,
              tooltip: 'Экспорт JSON',
              onTap: () => _exportJson(context, service.entries),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _RecBar(service: service),
          if (service.entries.isEmpty)
            Expanded(child: _EmptyState(isRecording: service.isRecording))
          else
            Expanded(child: _EntriesTable(entries: service.entries)),
        ],
      ),
    );
  }

  Future<void> _exportCsv(
      BuildContext context, List<SetlistEntry> entries) async {
    final csv = '$setlistCsvHeader\n'
        '${entries.map((e) => e.toCsvRow()).join('\n')}';
    await _shareText(csv, 'setlist.csv');
  }

  Future<void> _exportJson(
      BuildContext context, List<SetlistEntry> entries) async {
    final entriesList = entries.map((e) => e.toJson()).toList();
    final jsonParts = entriesList
        .map((m) => '{${m.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}')
        .join(',');
    final json = '{"app":"hitech_bpm_radar",'
        '"exported_at":"${DateTime.now().toIso8601String()}",'
        '"entries":[$jsonParts]}';
    await _shareText(json, 'setlist.json');
  }

  Future<void> _shareText(String text, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(text);
    await Share.shareXFiles([XFile(file.path)]);
  }
}

// ── REC / STOP bar ────────────────────────────────────────────────────────────

class _RecBar extends StatelessWidget {
  const _RecBar({required this.service});
  final SetlistService service;

  @override
  Widget build(BuildContext context) {
    final isRec = service.isRecording;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Status indicator
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRec ? AppColors.danger : AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRec ? 'ЗАПИСЬ' : 'ОСТАНОВЛЕНО',
                  style: AppTextStyles.mono(
                    9, FontWeight.w600,
                    isRec ? AppColors.danger : AppColors.textMuted,
                    letterSpacing: 0.12 * 9,
                  ),
                ),
                if (service.entries.isNotEmpty)
                  Text(
                    '${service.entryCount} записей  •  '
                    '${_formatDuration(service.duration)}  •  '
                    '${service.averageBpm?.toStringAsFixed(1) ?? '—'} BPM avg',
                    style: AppTextStyles.mono(
                        9, FontWeight.w400, AppColors.textMuted),
                  ),
              ],
            ),
          ),
          // REC / STOP button
          GestureDetector(
            onTap: isRec ? service.stopRecording : service.startRecording,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isRec ? AppColors.danger : AppColors.accentDim,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isRec ? AppColors.danger : AppColors.accent,
                  width: 0.5,
                ),
              ),
              child: Text(
                isRec ? 'СТОП' : 'REC',
                style: AppTextStyles.mono(
                  10, FontWeight.w700,
                  isRec ? Colors.white : AppColors.accent,
                  letterSpacing: 0.12 * 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ── Entries table ─────────────────────────────────────────────────────────────

class _EntriesTable extends StatelessWidget {
  const _EntriesTable({required this.entries});
  final List<SetlistEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[entries.length - 1 - i]; // newest first
        return _EntryRow(entry: e);
      },
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final SetlistEntry entry;

  @override
  Widget build(BuildContext context) {
    final isStable = entry.lockState == LockState.stable;
    final bpmColor = isStable ? AppColors.accent : AppColors.warning;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Time
          SizedBox(
            width: 52,
            child: Text(
              _formatTime(entry.timestamp),
              style: AppTextStyles.mono(
                  11, FontWeight.w400, AppColors.textMuted),
            ),
          ),
          // BPM
          SizedBox(
            width: 60,
            child: Text(
              entry.bpm.toStringAsFixed(1),
              style: AppTextStyles.mono(15, FontWeight.w700, bpmColor),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'BPM',
            style: AppTextStyles.mono(9, FontWeight.w400, AppColors.textMuted),
          ),
          const SizedBox(width: 12),
          // Confidence bar
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: entry.confidence.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: const Color(0xFF111916),
                valueColor: AlwaysStoppedAnimation<Color>(
                  entry.confidence > 0.7
                      ? AppColors.accent
                      : entry.confidence > 0.3
                          ? AppColors.warning
                          : AppColors.danger,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Confidence value
          Text(
            '${(entry.confidence * 100).toStringAsFixed(0)}%',
            style:
                AppTextStyles.mono(9, FontWeight.w400, AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isRecording});
  final bool isRecording;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRecording ? Icons.fiber_manual_record : Icons.queue_music,
            size: 36,
            color: isRecording ? AppColors.danger : AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            isRecording
                ? 'Ожидание STABLE сигнала...'
                : 'Нажми REC чтобы начать запись сета',
            style:
                AppTextStyles.mono(12, FontWeight.w400, AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Export icon button ────────────────────────────────────────────────────────

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20, color: AppColors.textSecondary),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}
