// Главный экран BPM-радара — Phase 7 premium design.
//
// Layout (top to bottom):
//   • 35 % — WaveformView: Traktor DJ–style bar waveform (band-split energy columns).
//   • 22 % — LiveSpectrumView: current FFT frame as smooth curve + gradient fill
//             + peak-hold ticks.
//   • 43 % — GlassmorphismCard: DspResult info (BPM, badge, confidence, etc.)
//             with BackdropFilter blur + semi-transparent surface.
//
// VizController computes a single FFT per audio hop (~50 ms) and publishes:
//   • waveColumns (band-split energy ring) → WaveformColumnPainter
//   • latestNorms / peakHoldValues → LiveSpectrumPainter
// Anti-fake: no BPM maths here.
//
// Design tokens in design_tokens.dart.
// BpmDisplay (Phase 6 EMA) is preserved and not modified.
// Debug button (AppBar trailing) is not moved.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide LockState;

import '../capture/bpm_display.dart';
import '../capture/capture_error.dart';
import '../dsp/dsp_result.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../viz/live_spectrum_painter.dart';
import '../viz/viz_controller.dart';
import '../viz/waveform_painter.dart' show WaveformColumnPainter;
import '../widgets/break_button.dart';
import '../widgets/confidence_bar.dart';
import '../widgets/listening_indicator.dart';
import 'design_tokens.dart';

// ── MainScreen ────────────────────────────────────────────────────────────────

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    required this.results,
    required this.errors,
    required this.debugBuilder,
    this.rawPcm,
    this.isPro = true,
    this.onHistoryTap,
    this.onPaywallTap,
  });

  final Stream<DspResult> results;
  final Stream<CaptureError> errors;

  /// How to build the debug screen when the bug icon is tapped.
  final WidgetBuilder debugBuilder;

  /// Raw PCM-16 LE mono bytes from CaptureBridge.rawPcm. Null in unit tests
  /// and before mic permission is granted — visualisers show a placeholder.
  final Stream<Uint8List>? rawPcm;

  /// Whether the user is on Pro tier. Affects debug gate and AppBar.
  final bool isPro;

  /// Callback when History icon is tapped. Null = no history button shown.
  final VoidCallback? onHistoryTap;

  /// Callback when Upgrade/PRO badge or paywall trigger is tapped.
  final void Function(String feature)? onPaywallTap;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final VizController _viz;
  StreamSubscription<CaptureError>? _errSub;
  CaptureError? _lastError;
  DspResult? _lastResult;
  final BpmDisplay _bpmDisplay = BpmDisplay();

  @override
  void initState() {
    super.initState();
    _viz = VizController();
    final pcm = widget.rawPcm;
    if (pcm != null) _viz.attachRawPcm(pcm);

    _errSub = widget.errors.listen((err) {
      if (!mounted) return;
      setState(() => _lastError = err);
    });
  }

  @override
  void dispose() {
    _errSub?.cancel();
    _viz.dispose();
    _bpmDisplay.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: _TraktorStyleAppBar(
          isPro: widget.isPro,
          onDebugTap: () {
            // Gate: Free → paywall, Pro → debug screen.
            if (!widget.isPro) {
              widget.onPaywallTap?.call('debug_screen');
              return;
            }
            Navigator.of(context).push(MaterialPageRoute(
              builder: widget.debugBuilder,
            ));
          },
          onHistoryTap: widget.onHistoryTap,
          onUpgradeTap: widget.isPro
              ? null
              : () => widget.onPaywallTap?.call('upgrade'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          // Uniform horizontal inset so nothing touches the screen edges.
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: StreamBuilder<DspResult>(
          stream: widget.results,
          builder: (context, snap) {
            if (snap.data != null) _lastResult = snap.data;
            final result = _lastResult;
            final displayBpm = result != null ? _bpmDisplay.update(result) : null;
            final isLockingDisplay = _bpmDisplay.isLockingDisplay;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_lastError != null) _ErrorBanner(error: _lastError!),

                // ── Waveform / oscilloscope — fixed 120 px (Design v2) ───
                SizedBox(
                  height: 120,
                  child: RepaintBoundary(
                    child: _WaveformView(viz: _viz),
                  ),
                ),

                // ── Live spectrum ────────────────────────────────────────
                Expanded(
                  flex: 22,
                  child: RepaintBoundary(
                    child: _LiveSpectrumView(viz: _viz),
                  ),
                ),

                // ── Glassmorphism info card (43 %) ─────────────────────────
                // RepaintBoundary isolates BackdropFilter compositing from
                // the ~20 Hz VizController and DspResult StreamBuilder above.
                Expanded(
                  flex: 43,
                  child: RepaintBoundary(
                    child: _GlassmorphismCard(
                      result: result,
                      viz: _viz,
                      displayBpm: displayBpm,
                      isLockingDisplay: isLockingDisplay,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        ),
      ),
    );
  }
}

// ── Waveform / oscilloscope view ──────────────────────────────────────────────

class _WaveformView extends StatelessWidget {
  const _WaveformView({required this.viz});
  final VizController viz;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viz,
      builder: (_, __) {
        if (viz.waveColumns.isEmpty) {
          return const _Placeholder(label: 'Ожидание микрофона…');
        }
        return CustomPaint(
          painter: WaveformColumnPainter(columns: viz.waveColumns),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

// ── Live spectrum view ────────────────────────────────────────────────────────

class _LiveSpectrumView extends StatelessWidget {
  const _LiveSpectrumView({required this.viz});
  final VizController viz;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: ListenableBuilder(
        listenable: viz,
        builder: (_, __) {
          if (viz.latestNorms.isEmpty) {
            return const _Placeholder(label: 'Ожидание микрофона…');
          }
          return CustomPaint(
            painter: LiveSpectrumPainter(
              norms: viz.latestNorms,
              peakHold: viz.peakHoldValues,
              accentColor: AppTheme.accent,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

// ── Shared placeholder ────────────────────────────────────────────────────────
// Shown by both panels when VizController has no audio data.
// Rendered as a Flutter Text widget (not Canvas) so widget tests can find it.

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.textDim,
          fontFamily: 'monospace',
          fontSize: 13,
        ),
      ),
    );
  }
}

// ── Glassmorphism info card ───────────────────────────────────────────────────

class _GlassmorphismCard extends StatelessWidget {
  const _GlassmorphismCard({
    required this.result,
    required this.viz,
    this.displayBpm,
    this.isLockingDisplay = false,
  });

  final DspResult? result;
  final VizController viz;
  final double? displayBpm;
  final bool isLockingDisplay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withAlpha(18),
            width: 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            // Reduced from 12→8: meaningful perf improvement on real devices
            // since the background repaints every ~50 ms with live waveform.
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              color: Colors.white.withAlpha(8),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: _InfoTableContent(
                  result: result,
                  viz: viz,
                  displayBpm: displayBpm,
                  isLockingDisplay: isLockingDisplay,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Info table content ────────────────────────────────────────────────────────

class _InfoTableContent extends StatelessWidget {
  const _InfoTableContent({
    required this.result,
    required this.viz,
    this.displayBpm,
    this.isLockingDisplay = false,
  });

  final DspResult? result;
  final VizController viz;
  final double? displayBpm;
  final bool isLockingDisplay;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final bpm = displayBpm ?? r?.primaryBpm;
    final conf = r?.confidence ?? 0.0;
    final lock = r?.lockState ?? LockState.searching;
    final sq = r?.signalQuality;

    // Best main candidate (relation == 'main'), fallback to first.
    TempoCandidate? best;
    if (r != null && r.candidates.isNotEmpty) {
      try {
        best = r.candidates.firstWhere((c) => c.relation == 'main');
      } catch (_) {
        best = r.candidates.first;
      }
    }

    final halfCand = r?.candidates.where((c) =>
        c.relation == 'half_time' || c.relation == 'normalized_from_half');
    final doubleCand = r?.candidates.where((c) =>
        c.relation == 'double_time' || c.relation == 'normalized_from_double');

    final halfBpm = (halfCand?.isNotEmpty ?? false)
        ? halfCand!.first.bpm.toStringAsFixed(1)
        : '—';
    final doubleBpm = (doubleCand?.isNotEmpty ?? false)
        ? doubleCand!.first.bpm.toStringAsFixed(1)
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Row 1: BPM hero + lock badge ─────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AnimatedBpmDisplay(
              bpm: bpm,
              confidence: conf,
              viz: viz,
              isLockingDisplay: isLockingDisplay,
              isUnstable: lock == LockState.unstable,
            ),
            const Spacer(),
            _LockBadge(state: lock),
          ],
        ),
        const SizedBox(height: 8),

        // ── Row 2: confidence + input level ──────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _Cell(
                label: 'УВЕРЕННОСТЬ',
                value: '${(conf * 100).round()}%',
              ),
            ),
            Expanded(
              child: _Cell(
                label: 'УРОВЕНЬ ВХОДА',
                value: sq?.inputLevelDbfs != null
                    ? '${sq!.inputLevelDbfs!.toStringAsFixed(1)} dBFS'
                    : '—',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // ── Row 3: best candidate + half / double ─────────────────────────────
        Row(
          children: [
            Expanded(
              child: _Cell(
                label: 'ЛУЧШИЙ КАНДИДАТ',
                value: best != null
                    ? '${best.bpm.toStringAsFixed(1)} BPM'
                    : '—',
              ),
            ),
            Expanded(
              child: _Cell(
                label: '×½ / ×2',
                value: '$halfBpm / $doubleBpm',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // ── Row 4: clipping + noise ────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _Cell(
                label: 'КЛИППИНГ',
                value: sq?.clipping == true ? '⚠ ПЕРЕГРУЗ' : 'нет',
                valueColor: sq?.clipping == true ? AppTheme.danger : null,
              ),
            ),
            Expanded(
              child: _Cell(
                label: 'ШУМ',
                value: _noiseLabel(sq?.noiseLevel),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Row 5: listening indicator + break button ─────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const ListeningIndicator(),
            BreakButton(onTap: () {}),
          ],
        ),
      ],
    );
  }

  static String _noiseLabel(String? level) {
    switch (level) {
      case 'low':
        return 'низкий';
      case 'medium':
        return 'средний';
      case 'high':
        return 'высокий';
      case 'noise_only':
        return 'только шум';
      default:
        return '—';
    }
  }
}

// ── Animated BPM display ──────────────────────────────────────────────────────
//
// Hero BPM text (72 px, Design v2) with beat-reactive glow from VizController.
// Fast attack (immediate), ~200 ms decay — driven by real audio transients.
// No timer, no fake pulse.
//
// Empty state: "— — —" in dim #1E3530.
// UNSTABLE: amber text.  STABLE/LOCKING: accent teal.
//
// Confidence bar uses the new 7 px ConfidenceBar widget with colour thresholds.

class _AnimatedBpmDisplay extends StatelessWidget {
  const _AnimatedBpmDisplay({
    required this.bpm,
    required this.confidence,
    required this.viz,
    this.isLockingDisplay = false,
    this.isUnstable = false,
  });

  final double? bpm;
  final double confidence;
  final VizController viz;
  final bool isLockingDisplay;
  final bool isUnstable;

  @override
  Widget build(BuildContext context) {
    final hasValue = bpm != null;
    final bpmText = hasValue ? bpm!.toStringAsFixed(1) : '— — —';

    // Colour: null→dim, unstable→amber, otherwise accent teal.
    final textColor = AppColors.bpmText(
      hasValue: hasValue,
      isUnstable: isUnstable,
    );
    // Dim slightly during LOCKING to signal not-yet-stable.
    final effectiveColor =
        isLockingDisplay ? textColor.withAlpha(180) : textColor;

    // Font size: 72 when value present, 58 for "— — —" placeholder.
    final fontSize = hasValue ? 72.0 : 58.0;
    final letterSpacing = hasValue ? -2.5 : -1.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hero BPM number with beat-reactive accent glow.
        RepaintBoundary(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeIn,
            switchOutCurve: Curves.easeOut,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: ListenableBuilder(
              key: ValueKey(bpmText),
              listenable: viz,
              builder: (_, __) {
                final g = viz.beatDecay;
                final style = AppTextStyles.mono(
                  fontSize,
                  FontWeight.w600,
                  effectiveColor,
                  letterSpacing: letterSpacing,
                );
                return Text(
                  bpmText,
                  style: (g > 0.04 && hasValue)
                      ? style.copyWith(
                          shadows: [
                            Shadow(
                              color: AppColors.accent.withAlpha(
                                (g * 0.9 * 255).round().clamp(0, 255),
                              ),
                              blurRadius: 6.0 + g * 26.0,
                            ),
                          ],
                        )
                      : style,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        // 7 px confidence bar with red/yellow/teal thresholds (Design v2).
        SizedBox(
          width: 160,
          child: ConfidenceBar(confidence: confidence),
        ),
      ],
    );
  }
}

// ── Metric cell ───────────────────────────────────────────────────────────────

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: AppTheme.textDim,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTheme.mono(
            fontSize: 13,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Lock state badge ──────────────────────────────────────────────────────────
//
// Pill-shaped badge that fades between states via AnimatedSwitcher.
// The child carries ValueKey<LockState>(state) so the switcher detects changes.

class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.state});
  final LockState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: _BadgePill(state: state, key: ValueKey(state)),
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.state, super.key});
  final LockState state;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _scheme(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  static (String, Color, Color) _scheme(LockState s) {
    switch (s) {
      case LockState.stable:
        return ('стабильно', AppTheme.successDim, AppTheme.success);
      case LockState.locking:
        return ('захват', AppTheme.warningDim, AppTheme.warning);
      case LockState.unstable:
        return ('нестабильно', AppTheme.warningDim, AppTheme.warning);
      case LockState.breakdown:
        return ('брейк', AppTheme.accentDim, AppTheme.accent);
      case LockState.clippedMic:
        return ('перегруз', AppTheme.dangerDim, AppTheme.danger);
      case LockState.noiseOnly:
        return ('только шум', AppTheme.noiseDim, AppTheme.noisePurple);
      case LockState.searching:
      case LockState.unknown:
        return ('поиск', AppTheme.surfaceHigh, AppTheme.textDim);
    }
  }
}

// ── Traktor-style AppBar ──────────────────────────────────────────────────────
//
// Minimal dark bar with thin bottom border, compact layout.
// Left: app title in small caps. Right: debug icon button.

class _TraktorStyleAppBar extends StatelessWidget {
  const _TraktorStyleAppBar({
    required this.onDebugTap,
    this.onHistoryTap,
    this.onUpgradeTap,
    this.isPro = true,
  });
  final VoidCallback onDebugTap;
  final VoidCallback? onHistoryTap;
  final VoidCallback? onUpgradeTap;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(
          bottom: BorderSide(
            color: Color(0x18FFFFFF),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // App title — small, uppercase, dim.
              Text(
                'HITECH BPM RADAR',
                style: AppTheme.mono(
                  fontSize: 11,
                  color: AppTheme.textDim,
                  letterSpacing: 1.8,
                  weight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // History button.
              if (onHistoryTap != null)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    splashRadius: 18,
                    icon: const Icon(
                      Icons.history,
                      color: AppTheme.textDim,
                    ),
                    onPressed: onHistoryTap,
                  ),
                ),
              // Upgrade / PRO badge.
              if (!isPro && onUpgradeTap != null)
                GestureDetector(
                  onTap: onUpgradeTap,
                  child: Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentDim,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'PRO',
                      style: AppTheme.mono(
                        fontSize: 9,
                        color: AppTheme.accent,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              // Debug button — compact, no splash, icon only.
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  splashRadius: 18,
                  icon: const Icon(
                    Icons.bug_report_outlined,
                    color: AppTheme.textDim,
                  ),
                  onPressed: onDebugTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});
  final CaptureError error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      color: AppTheme.danger.withAlpha(60),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ошибка захвата: ${error.message}',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
