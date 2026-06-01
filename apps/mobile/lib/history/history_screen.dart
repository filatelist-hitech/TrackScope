// History screen — показывает список BPM-сэмплов с timestamp/lock-state.
//
// Free tier: показывает cap-баннер "30 сек · Upgrade →" при достижении лимита.
// Pro tier: показывает кнопку экспорта (CSV/JSON) в app bar.

import 'package:flutter/material.dart';

import '../monetization/feature_flags.dart';
import '../monetization/paywall_screen.dart';
import 'session_history_controller.dart';
import '../ui/design_tokens.dart';

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
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('BPM History', style: AppTheme.mono(fontSize: 16)),
        centerTitle: true,
        actions: [
          if (flags.canExport)
            PopupMenuButton<String>(
              icon: const Icon(Icons.download, color: AppTheme.accent),
              onSelected: (value) {
                if (value == 'csv') {
                  onExportCsv();
                } else if (value == 'json') {
                  onExportJson();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'csv',
                  child: Text('Export CSV', style: AppTheme.mono(fontSize: 13)),
                ),
                PopupMenuItem(
                  value: 'json',
                  child: Text('Export JSON', style: AppTheme.mono(fontSize: 13)),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final samples = controller.history.samples;

            if (samples.isEmpty) {
              return Center(
                child: Text(
                  'No history yet',
                  style: AppTheme.mono(fontSize: 14, color: AppTheme.textSecondary),
                ),
              );
            }

            return Column(
              children: [
                // Cap banner for Free tier
                if (!flags.canExport && controller.isAtLimit)
                  _buildCapBanner(context),

                // History list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: samples.length,
                    itemBuilder: (context, index) {
                      final sample = samples[samples.length - 1 - index]; // Reverse order
                      return _buildHistoryRow(sample);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCapBanner(BuildContext context) {
    return Material(
      color: AppTheme.warningDim,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const PaywallScreen(feature: 'history'),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, color: AppTheme.warning, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '30 сек · Upgrade для unlimited',
                  style: AppTheme.mono(fontSize: 13, color: AppTheme.warning),
                ),
              ),
              const Icon(Icons.arrow_forward, color: AppTheme.warning, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryRow(sample) {
    final timeStr = _formatTime(sample.timestamp);
    final bpmStr = sample.bpm.toStringAsFixed(1);
    final stateStr = _formatLockState(sample.lockState);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              timeStr,
              style: AppTheme.mono(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              '$bpmStr BPM',
              textAlign: TextAlign.center,
              style: AppTheme.mono(fontSize: 13, color: AppTheme.accent),
            ),
          ),
          Expanded(
            child: Text(
              stateStr,
              textAlign: TextAlign.right,
              style: AppTheme.mono(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatLockState(lockState) {
    switch (lockState.name) {
      case 'STABLE':
        return 'STABLE';
      case 'LOCKING':
        return 'LOCKING';
      case 'UNSTABLE':
        return 'UNSTABLE';
      default:
        return lockState.name;
    }
  }
}
