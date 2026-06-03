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
import '../viz/live_spectrum_painter.dart';
import '../viz/viz_controller.dart';
import '../viz/waveform_painter.dart' show WaveformColumnPainter;
import '../widgets/confidence_bar.dart';
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
    this.onBreak,
  });

  final Stream<DspResult> results;
  final Stream<CaptureError> errors;

  /// How to build the Signal Analyzer when the debug icon or best-candidate row is tapped.
  final WidgetBuilder debugBuilder;

  /// Raw PCM-16 LE mono bytes from CaptureBridge.rawPcm.
  final Stream<Uint8List>? rawPcm;

  /// Whether the user is on Pro tier.
  final bool isPro;

  /// Callback when History icon is tapped (legacy — now History is a Tab).
  final VoidCallback? onHistoryTap;

  /// Callback when Upgrade/PRO badge or paywall trigger is tapped.
  final void Function(String feature)? onPaywallTap;

  /// Called when the user taps Break — resets DSP engine state mid-session.
  final VoidCallback? onBreak;

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
    void pushSignalAnalyzer() {
      if (!widget.isPro) {
        widget.onPaywallTap?.call('debug_screen');
        return;
      }
      Navigator.of(context)
          .push(MaterialPageRoute(builder: widget.debugBuilder));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: _TraktorStyleAppBar(
          isPro: widget.isPro,
          isCapturing: _lastResult != null,
          onDebugTap: pushSignalAnalyzer,
          onUpgradeTap: widget.isPro
              ? null
              : () => widget.onPaywallTap?.call('upgrade'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: LayoutBuilder(
          builder: (context, constraints) {
            // Adaptive waveform height: 90dp on compact screens (Pixel 4,
            // iPhone SE etc.), 120dp on larger phones (Pixel 7, iPhone 14+).
            // Threshold on body height: <680dp → compact.
            final waveformHeight = constraints.maxHeight < 680 ? 90.0 : 120.0;
            return StreamBuilder<DspResult>(
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

                // ── Zone label: WAVEFORM ──────────────────────────────────
                const _ZoneLabelRow(label: 'WAVEFORM'),

                // ── Waveform — adaptive height ────────────────────────────
                SizedBox(
                  height: waveformHeight,
                  child: RepaintBoundary(
                    child: _WaveformView(viz: _viz),
                  ),
                ),

                // ── Zone label: LIVE SPECTRUM ─────────────────────────────
                const _ZoneLabelRow(label: 'LIVE SPECTRUM'),

                // ── Live spectrum ─────────────────────────────────────────
                Expanded(
                  flex: 22,
                  child: RepaintBoundary(
                    child: _LiveSpectrumView(viz: _viz),
                  ),
                ),

                // ── Info card ─────────────────────────────────────────────
                Expanded(
                  flex: 43,
                  child: RepaintBoundary(
                    child: _GlassmorphismCard(
                      result: result,
                      viz: _viz,
                      displayBpm: displayBpm,
                      isLockingDisplay: isLockingDisplay,
                      onBestCandidateTap: pushSignalAnalyzer,
                      onBreak: widget.onBreak,
                    ),
                  ),
                ),
              ],
            );
          },
        );
          },
        ),
        ),
      ),
    );
  }
}

// ── Zone label row (WAVEFORM / LIVE SPECTRUM) ─────────────────────────────────
// Matches prototype .zlbl — dim label left, optional trailing widget right.
// Bright contrast (#3a6858) to meet CR ≥ 3:1 target from the redesign audit.

class _ZoneLabelRow extends StatelessWidget {
  const _ZoneLabelRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
      child: Text(
        label,
        style: AppTextStyles.sectionLabel,
      ),
    );
  }
}

// ── Waveform / oscilloscope view ──────────────────────────────────────────────
// Uses a StatefulWidget so the widget tree is rebuilt only ONCE (on first data),
// then repaints via `repaint: viz` without touching the widget tree on every
// PCM chunk — reduces jank on real device.

class _WaveformView extends StatefulWidget {
  const _WaveformView({required this.viz});
  final VizController viz;

  @override
  State<_WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<_WaveformView> {
  bool _hasData = false;

  @override
  void initState() {
    super.initState();
    widget.viz.addListener(_onViz);
  }

  @override
  void dispose() {
    widget.viz.removeListener(_onViz);
    super.dispose();
  }

  void _onViz() {
    // Only trigger a widget rebuild when transitioning from empty to non-empty.
    // All subsequent repaints are handled by the `repaint: viz` mechanism.
    if (!_hasData && widget.viz.waveColumns.isNotEmpty) {
      setState(() => _hasData = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return const _Placeholder(label: 'Ожидание микрофона…');
    }
    return CustomPaint(
      painter: _VizWaveformPainter(widget.viz),
      child: const SizedBox.expand(),
    );
  }
}

/// Reads waveColumns + beatDecay from VizController at paint-time.
/// Registers `repaint: viz` so canvas repaints without Flutter widget rebuild.
/// Forwards beatDecay as glowIntensity for the same beat-reactive glow as
/// the BPM-hero text.
class _VizWaveformPainter extends CustomPainter {
  _VizWaveformPainter(this.viz) : super(repaint: viz);
  final VizController viz;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = viz.waveColumns;
    if (cols.isEmpty) return;
    WaveformColumnPainter(
      columns: cols,
      glowIntensity: viz.beatDecay,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_VizWaveformPainter old) =>
      !identical(viz.waveColumns, old.viz.waveColumns) ||
      (viz.beatDecay - old.viz.beatDecay).abs() > 0.01;
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
    this.onBestCandidateTap,
    this.onBreak,
  });

  final DspResult? result;
  final VizController viz;
  final double? displayBpm;
  final bool isLockingDisplay;
  final VoidCallback? onBestCandidateTap;
  final VoidCallback? onBreak;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 6),
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
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
              ),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              clipBehavior: Clip.hardEdge,
              child: LayoutBuilder(
                builder: (context, cc) {
                  // Adaptive compact mode based on empirically measured card heights:
                  //   Pixel 4 (real): cc.maxHeight ≈ 312.7 dp → compact + no chips
                  //   Pixel 7 (real): cc.maxHeight ≈ 350.8 dp → compact + chips shown
                  //
                  // compact (<420 dp): BPM font 52→52dp, spacings 3→1dp, break-padding 8→5dp.
                  // showLockChips (≥335 dp): mode chips visible when enough vertical room.
                  //   Pixel 4 (312.7 < 335) → chips hidden  → content ~257dp, inner ~302dp ✓
                  //   Pixel 7 (350.8 ≥ 335) → chips shown   → content ~286dp, inner ~340dp ✓
                  final bool compact = cc.maxHeight < 420;
                  return OverflowBox(
                    alignment: Alignment.topCenter,
                    maxHeight: double.infinity,
                    child: _InfoTableContent(
                      result: result,
                      viz: viz,
                      displayBpm: displayBpm,
                      isLockingDisplay: isLockingDisplay,
                      onBestCandidateTap: onBestCandidateTap,
                      onBreak: onBreak,
                      compact: compact,
                      showLockChips: cc.maxHeight >= 335,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Info card content — Design System v2 (matches BPM Radar Prototype) ──────

class _InfoTableContent extends StatelessWidget {
  const _InfoTableContent({
    required this.result,
    required this.viz,
    this.displayBpm,
    this.isLockingDisplay = false,
    this.onBestCandidateTap,
    this.onBreak,
    this.showLockChips = true,
    this.compact = false,
  });

  final DspResult? result;
  final VizController viz;
  final double? displayBpm;
  final bool isLockingDisplay;
  final VoidCallback? onBestCandidateTap;
  final VoidCallback? onBreak;
  /// На очень компактных экранах (Pixel 4, iPhone SE) скрываем чипы
  /// состояния захвата, чтобы строки ЭНЕРГИЯ/ТОНАЛЬНОСТЬ оставались видимыми.
  final bool showLockChips;
  /// Compact mode: BPM font 52 dp, spacings 1 dp, break-button padding reduced.
  /// Activated by _GlassmorphismCard when cc.maxHeight < 420 dp.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Adaptive spacing and BPM font size driven by compact mode.
    final double spacing = compact ? 1.0 : 3.0;
    final double bpmFontSize = compact ? 52.0 : 72.0;

    final r = result;
    final energyResult = r?.energyResult;
    final keyResult = r?.keyResult;
    final hasEnergy = energyResult != null;
    final kResult = keyResult;
    final hasKey = kResult != null && kResult.confidence >= 0.25;
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

    final inputLevel = sq?.inputLevelDbfs != null
        ? '${sq!.inputLevelDbfs!.toStringAsFixed(1)} dBFS'
        : '—';
    final bestCandText = best != null
        ? '${best.bpm.toStringAsFixed(1)} BPM'
        : bpm != null
            ? '${bpm.toStringAsFixed(1)} BPM'
            : '—';

    // ×½ / ×2 candidates — half-time and double-time, never hidden.
    final halfCand = r?.candidates
        .where((c) => c.relation == 'half_time')
        .firstOrNull;
    final doubleCand = r?.candidates
        .where((c) => c.relation == 'double_time')
        .firstOrNull;
    final halfText = halfCand != null
        ? halfCand.bpm.toStringAsFixed(1)
        : '—';
    final doubleText = doubleCand != null
        ? doubleCand.bpm.toStringAsFixed(1)
        : '—';
    final halfDoubleText = '$halfText / $doubleText';

    final clippingText = sq?.clipping == true ? '⚠ перегруз' : 'нет';
    final clippingColor = sq?.clipping == true ? AppTheme.danger : null;
    final noiseText = _noiseLabel(sq?.noiseLevel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Centered BPM hero ────────────────────────────────────────────────
        Center(
          child: _AnimatedBpmDisplay(
            bpm: bpm,
            viz: viz,
            isLockingDisplay: isLockingDisplay,
            isUnstable: lock == LockState.unstable,
            fontSize: bpmFontSize,
            subtitleHeight: compact ? 18.0 : 22.0,
          ),
        ),

        // ── Full-width confidence bar ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: ConfidenceBar(confidence: conf),
        ),

        // ── Break button — centered ──────────────────────────────────────────
        Center(
          child: _BreakButtonInline(
              onTap: onBreak ?? () {}, compactPadding: compact),
        ),
        SizedBox(height: spacing),

        // ── Stats grid ───────────────────────────────────────────────────────
        // Row 1: Уровень входа (left-aligned) | Лучший кандидат (centered)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _StatCell(label: 'Уровень входа', value: inputLevel)),
            const SizedBox(width: 18),
            Expanded(
              child: _StatCell(
                label: 'Лучший кандидат',
                value: bestCandText,
                isLink: onBestCandidateTap != null,
                onTap: onBestCandidateTap,
                centered: true,
              ),
            ),
          ],
        ),
        SizedBox(height: spacing),
        // Row 2: Клиппинг (left-aligned) | Шум (centered)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StatCell(
                label: 'Клиппинг',
                value: clippingText,
                valueColor: clippingColor,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _StatCell(
                label: 'Шум',
                value: noiseText,
                centered: true,
              ),
            ),
          ],
        ),
        SizedBox(height: spacing),
        // Row 3: ×½ / ×2 — full width centered (both half and double visible)
        Center(
          child: _StatCell(
            label: '×½ / ×2',
            value: halfDoubleText,
            centered: true,
          ),
        ),
        // ── Energy + Key row — always shown; '—' when data unavailable ────────
        SizedBox(height: spacing),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: hasEnergy
                  ? _EnergyCell(energyResult: energyResult)
                  : const _StatCell(label: 'ЭНЕРГИЯ', value: '—'),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: hasKey
                  ? _StatCell(
                      label: 'ТОНАЛЬНОСТЬ',
                      value: kResult.camelot ?? '—',
                      centered: true,
                    )
                  : const _StatCell(
                      label: 'ТОНАЛЬНОСТЬ',
                      value: '—',
                      centered: true,
                    ),
            ),
          ],
        ),

        if (showLockChips) ...[
          SizedBox(height: spacing),
          // ── Lock state chips ───────────────────────────────────────────────
          _ModeChips(lockState: lock),
        ],
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

// ── Stat cell (label + value, prototype .sc/.sl/.sv style) ──────────────────

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    this.valueColor,
    this.isLink = false,
    this.centered = false,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool isLink;
  final bool centered;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = valueColor ?? (isLink ? AppColors.accent : AppColors.textSecondary);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.statsLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: AppTextStyles.statsValue.copyWith(color: color),
              ),
              if (isLink) ...[
                const SizedBox(width: 3),
                Text(
                  '›',
                  style: AppTextStyles.mono(12, FontWeight.w400, color),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Break button inline (prototype .brk) ────────────────────────────────────

class _BreakButtonInline extends StatelessWidget {
  const _BreakButtonInline({required this.onTap, this.compactPadding = false});
  final VoidCallback onTap;
  /// When true, reduces vertical padding from 8 → 5 dp to save vertical space.
  final bool compactPadding;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: 18, vertical: compactPadding ? 5 : 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.bpmEmpty),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Simple pause-like icon matching prototype SVG
            const Icon(Icons.pause_circle_outline,
                size: 11, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Зафиксировать брейк',
                style: AppTextStyles.mono(
                    11, FontWeight.w400, AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mode chips (prototype .modes/.mode-opt) ──────────────────────────────────
// Read-only state indicator. Shows current lock mode as one of 3 chips.

class _ModeChips extends StatelessWidget {
  const _ModeChips({required this.lockState});
  final LockState lockState;

  // Map lock state to one of three chip positions.
  _ChipMode get _activeChip {
    switch (lockState) {
      case LockState.stable:
      case LockState.locking:
        return _ChipMode.active;
      case LockState.unstable:
        return _ChipMode.unstable;
      default:
        return _ChipMode.idle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeChip;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Chip(label: 'ПОИСК', isOn: active == _ChipMode.idle),
        const SizedBox(width: 6),
        _Chip(label: 'ЗАХВАТ', isOn: active == _ChipMode.active),
        const SizedBox(width: 6),
        _Chip(label: 'НЕСТАБ.', isOn: active == _ChipMode.unstable),
      ],
    );
  }
}

enum _ChipMode { idle, active, unstable }

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.isOn});
  final String label;
  final bool isOn;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOn ? AppColors.accentDim : Colors.transparent,
        border: Border.all(
          color: isOn ? AppColors.accent : const Color(0xFF1A2D24),
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: AppTextStyles.mono(
          10,
          FontWeight.w400,
          isOn ? AppColors.accent : AppColors.textMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
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
    required this.viz,
    this.isLockingDisplay = false,
    this.isUnstable = false,
    this.fontSize = 72.0,
    this.subtitleHeight = 22.0,
  });

  final double? bpm;
  final VizController viz;
  final bool isLockingDisplay;
  final bool isUnstable;
  /// Hero BPM font size: 72 dp (normal) or 52 dp (compact).
  final double fontSize;
  /// Height of the subtitle row beneath the BPM number.
  final double subtitleHeight;

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

    // Letter spacing tighter at large size; slightly looser at compact 52 dp.
    final double letterSpacing = fontSize < 60 ? -1.5 : -2.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hero BPM number with beat-reactive accent glow.
        // AnimatedSwitcher key = hasValue only: animates on null↔value transition,
        // not on every BPM update (which fires every ~50 ms and stacks animations).
        RepaintBoundary(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeIn,
            switchOutCurve: Curves.easeOut,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: ListenableBuilder(
              key: ValueKey(hasValue),
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
                  textAlign: TextAlign.center,
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
        SizedBox(
          height: subtitleHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'BPM',
                style: AppTextStyles.mono(
                    14, FontWeight.w400, AppColors.textSecondary,
                    letterSpacing: 4),
              ),
              if (isUnstable) ...[
                const SizedBox(width: 10),
                _UnstablePill(),
              ],
              const SizedBox(width: 10),
              Text(
                '155–230 · Hitech',
                style: AppTextStyles.mono(
                    10, FontWeight.w400, AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Unstable pill ─────────────────────────────────────────────────────────────

class _UnstablePill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.amberBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.amber.withAlpha(76)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                  color: AppColors.amberText, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('нестабильно',
              style: AppTextStyles.mono(
                  10, FontWeight.w500, AppColors.amberText)),
        ],
      ),
    );
  }
}

// ── Traktor-style AppBar ──────────────────────────────────────────────────────

class _TraktorStyleAppBar extends StatelessWidget {
  const _TraktorStyleAppBar({
    required this.onDebugTap,
    this.onUpgradeTap,
    this.isPro = true,
    this.isCapturing = false,
  });

  final VoidCallback onDebugTap;
  final VoidCallback? onUpgradeTap;
  final bool isPro;

  /// When true shows the blinking REC badge on the left (prototype .rec).
  final bool isCapturing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(
          bottom: BorderSide(color: Color(0x18FFFFFF), width: 0.5),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          // left: 16 pt keeps title centred; right: 10 pt moves gear icon
          // closer to the screen edge, visually level with the REC badge.
          padding: const EdgeInsets.only(left: 16, right: 10),
          child: Row(
            // start: all items pin to the top of the row, so the gear icon
            // sits a few px higher than it did with CrossAxisAlignment.center.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: REC badge when capturing, spacer otherwise
              if (isCapturing)
                _RecBadge()
              else
                const SizedBox(width: 26),

              // Center: title
              Expanded(
                child: Text(
                  'HITECH BPM RADAR',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.mono(
                    10, FontWeight.w600, AppColors.textMuted,
                    letterSpacing: 2.0,
                  ),
                ),
              ),

              // Right: PRO badge + settings/debug icon
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isPro && onUpgradeTap != null)
                    GestureDetector(
                      onTap: onUpgradeTap,
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentDim,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'PRO',
                          style: AppTextStyles.mono(
                            10, FontWeight.w700, AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  // 26×26 matches REC badge height (~22 pt) more closely
                  // than the previous 30×30, so both sit on the same
                  // visual centre line when crossAxisAlignment: center.
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1712),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 13,
                        icon: const Icon(Icons.settings_outlined,
                            color: AppColors.textSecondary),
                        onPressed: onDebugTap,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── REC badge (prototype .rec + .rdot) ───────────────────────────────────────

class _RecBadge extends StatefulWidget {
  @override
  State<_RecBadge> createState() => _RecBadgeState();
}

class _RecBadgeState extends State<_RecBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1.0, end: 0.3)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFD03030),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _opacity,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'REC',
            style: AppTextStyles.mono(10, FontWeight.w600, Colors.white),
          ),
        ],
      ),
    );
  }
}

// ── Energy cell (label + numeric value + compact colour bar) ─────────────────
// Gated: only rendered when energyResult != null.
// Color: levels 1–3 danger / 4–7 warning / 8–10 accent — mirrors ConfidenceBar.

class _EnergyCell extends StatelessWidget {
  const _EnergyCell({required this.energyResult});
  final EnergyResult energyResult;

  static Color _barColor(int level) {
    if (level <= 3) return AppColors.danger;
    if (level <= 7) return AppColors.warning;
    return AppColors.accent;
  }

  @override
  Widget build(BuildContext context) {
    final level = energyResult.level.clamp(1, 10);
    final fraction = level / 10.0;
    final color = _barColor(level);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ЭНЕРГИЯ',
          style: AppTextStyles.statsLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        // Compact layout: value + progress bar in one row (same height as _StatCell)
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('$level/10', style: AppTextStyles.statsValue),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: fraction,
                  backgroundColor: AppColors.surface2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 4,
                ),
              ),
            ),
          ],
        ),
      ],
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
