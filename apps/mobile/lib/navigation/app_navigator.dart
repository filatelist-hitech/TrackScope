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
    this.onBreak,
  });

  final Stream<DspResult> results;
  final Stream<CaptureError> errors;
  final FeatureFlags flags;
  final SessionHistoryController historyController;
  final Stream<Uint8List>? rawPcm;

  /// Called when the user taps the Break button — resets DSP engine state.
  final VoidCallback? onBreak;

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator>
    with SingleTickerProviderStateMixin {
  AppTab _current = AppTab.radar;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1.0,
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged(AppTab tab) {
    // History / Settings are Pro-gated at the tab level.
    if (tab == AppTab.history && !widget.flags.isPro) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const PaywallScreen(feature: 'history'),
      ));
      return;
    }
    if (tab == _current) return;
    _fadeCtrl.reset();
    setState(() => _current = tab);
    _fadeCtrl.forward();
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
      builder: (_) => SignalAnalyzerScreen(
        results: widget.results,
        rawPcm: widget.rawPcm,
      ),
    ));
  }

  void _onSwipe(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    const double threshold = 300.0;
    const tabs = AppTab.values;
    final idx = _current.index;
    if (v < -threshold && idx < tabs.length - 1) {
      // Swipe left → next tab
      _onTabChanged(tabs[idx + 1]);
    } else if (v > threshold && idx > 0) {
      // Swipe right → prev tab
      _onTabChanged(tabs[idx - 1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onHorizontalDragEnd: _onSwipe,
        behavior: HitTestBehavior.translucent,
        child: FadeTransition(
        opacity: _fadeAnim,
        child: IndexedStack(
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
            onBreak: widget.onBreak,
            debugBuilder: (_) => SignalAnalyzerScreen(
              results: widget.results,
              rawPcm: widget.rawPcm,
            ),
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
        ),
      ),
      bottomNavigationBar: AppTabBar(
        current: _current,
        onChanged: _onTabChanged,
      ),
    );
  }
}
