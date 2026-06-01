// AppNavigator — Tab Bar structure (Design System v2).
//
// Three tabs: Radar / History / Settings.
// IndexedStack preserves each tab's widget tree and scroll position.
// CaptureBridge streams are passed in from _CapturePipeline (main.dart) and
// forwarded to RadarTab — the bridge is NOT recreated on tab switch.
//
// Architecture:
//   _CapturePipeline (owns CaptureBridge + MicrophoneSource)
//     └── AppNavigator
//           ├── [0] RadarTab  ← receives DSP streams
//           ├── [1] HistoryTab
//           └── [2] SettingsTab

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../capture/capture_error.dart';
import '../dsp/dsp_result.dart';
import '../export/bpm_exporter.dart';
import '../history/history_screen.dart';
import '../history/session_history_controller.dart';
import '../monetization/feature_flags.dart';
import '../monetization/paywall_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/signal_analyzer_screen.dart';
import '../ui/main_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/app_tab_bar.dart';

export 'app_navigator.dart' show AppTab;

enum AppTab { radar, history, settings }

class AppNavigator extends StatefulWidget {
  const AppNavigator({
    super.key,
    required this.results,
    required this.errors,
    required this.flags,
    required this.historyController,
    this.rawPcm,
  });

  final Stream<DspResult> results;
  final Stream<CaptureError> errors;
  final FeatureFlags flags;
  final SessionHistoryController historyController;
  final Stream<Uint8List>? rawPcm;

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator> {
  AppTab _current = AppTab.radar;

  void _onTabChanged(AppTab tab) {
    // History / Settings are Pro-gated at the tab level.
    if (tab == AppTab.history && !widget.flags.isPro) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const PaywallScreen(feature: 'history'),
      ));
      return;
    }
    setState(() => _current = tab);
  }

  void _pushPaywall(String feature) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PaywallScreen(feature: feature),
    ));
  }

  void _pushSignalAnalyzer() {
    if (!widget.flags.canAccessDebugScreen) {
      _pushPaywall('signal_analyzer');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SignalAnalyzerScreen(results: widget.results),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _current.index,
        children: [
          // ── Tab 0: Radar ──────────────────────────────────────────────────
          MainScreen(
            results: widget.results,
            errors: widget.errors,
            rawPcm: widget.rawPcm,
            isPro: widget.flags.isPro,
            onHistoryTap: null, // History is now a tab, not a push
            onPaywallTap: _pushPaywall,
            debugBuilder: (_) =>
                SignalAnalyzerScreen(results: widget.results),
          ),

          // ── Tab 1: History ────────────────────────────────────────────────
          HistoryScreen(
            controller: widget.historyController,
            flags: widget.flags,
            onExportCsv: () =>
                exportCsv(widget.historyController.history.samples),
            onExportJson: () =>
                exportJson(widget.historyController.history.samples),
          ),

          // ── Tab 2: Settings ───────────────────────────────────────────────
          SettingsScreen(
            flags: widget.flags,
            onSignalAnalyzerTap: _pushSignalAnalyzer,
            onHistoryTap: () => setState(() => _current = AppTab.history),
            onUpgradeTap: () => _pushPaywall('upgrade'),
          ),
        ],
      ),
      bottomNavigationBar: AppTabBar(
        current: _current,
        onChanged: _onTabChanged,
      ),
    );
  }
}
