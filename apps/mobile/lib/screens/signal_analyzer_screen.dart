// Signal Analyzer Screen — Pro-only, Design System v2.
//
// Layout matches HTML prototype (BPM Radar Prototype.html):
//   1. AppBar: "SIGNAL ANALYZER" uppercase + PRO badge
//   2. FFT SPECTRUM — live spectrum from rawPcm (when available)
//   3. BPM КАНДИДАТЫ — top-4 candidates, 17px BPM, 4px colored bar
//   4. МЕТРИКИ АЛГОРИТМА — onset/autocorr/flux as % bars; SNR/level as text
//
// Section headers are standalone (sa-hdr style, outside cards).
// Group cards use bg #0d1712, r=13, no border (sa-grp style).
//
// Anti-fake: all values come from DspResult stream; no hardcoded numbers.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../dsp/dsp_result.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../viz/live_spectrum_painter.dart';
import '../viz/viz_controller.dart';

class SignalAnalyzerScreen extends StatefulWidget {
  const SignalAnalyzerScreen({super.key, required this.results, this.rawPcm});

  final Stream<DspResult> results;
  final Stream<Uint8List>? rawPcm;

  @override
  State<SignalAnalyzerScreen> createState() => _SignalAnalyzerScreenState();
}

class _SignalAnalyzerScreenState extends State<SignalAnalyzerScreen> {
  late final VizController _viz;

  @override
  void initState() {
    super.initState();
    _viz = VizController();
    final pcm = widget.rawPcm;
    if (pcm != null) _viz.attachRawPcm(pcm);
  }

  @override
  void dispose() {
    _viz.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        // Back icon
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
        title: Text(
          'АНАЛИЗАТОР СИГНАЛА',
          style: AppTextStyles.mono(
            11, FontWeight.w600, const Color(0xFF7AB8AA),
            letterSpacing: 0.18 * 11,
          ),
        ),
        // PRO badge on right
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              'PRO',
              style: AppTextStyles.mono(
                  9, FontWeight.w700, AppColors.accent),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.border),
        ),
      ),
      body: Column(
        children: [
          // ── FFT Spectrum (live, from rawPcm) ─────────────────────────────
          if (widget.rawPcm != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('СПЕКТР FFT',
                      style: AppTextStyles.sectionLabel),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 90,
                    child: RepaintBoundary(
                      child: _SpectrumView(viz: _viz),
                    ),
                  ),
                ],
              ),
            ),

          // ── DSP results ───────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<DspResult>(
              stream: widget.results,
              builder: (context, snap) {
                final r = snap.data;
                if (r == null) {
                  return Center(
                    child: Text(
                      'Ожидание первого снапшота DspResult…',
                      style: AppTextStyles.mono(
                          12, FontWeight.w400, AppColors.textMuted),
                    ),
                  );
                }
                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // ── BPM Кандидаты ─────────────────────────────────
                    const _SectionHeader('КАНДИДАТЫ BPM'),
                    _CandidatesGroup(candidates: r.candidates),

                    // ── Метрики алгоритма ─────────────────────────────
                    const _SectionHeader('МЕТРИКИ АЛГОРИТМА'),
                    _MetricsGroup(debug: r.debug, quality: r.signalQuality),

                    // ── Качество сигнала ──────────────────────────────
                    const _SectionHeader('КАЧЕСТВО СИГНАЛА'),
                    _QualityGroup(quality: r.signalQuality),

                    const SizedBox(height: 32),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Spectrum view — forwards VizController to LiveSpectrumPainter ─────────────

class _SpectrumView extends StatefulWidget {
  const _SpectrumView({required this.viz});
  final VizController viz;

  @override
  State<_SpectrumView> createState() => _SpectrumViewState();
}

class _SpectrumViewState extends State<_SpectrumView> {
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
    if (!_hasData && widget.viz.latestNorms.isNotEmpty) {
      setState(() => _hasData = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return Container(
        color: const Color(0xFF07070F),
        alignment: Alignment.center,
        child: Text('Ожидание аудио…',
            style: AppTextStyles.caption),
      );
    }
    return CustomPaint(
      painter: _VizSpectrumPainter(widget.viz),
      child: const SizedBox.expand(),
    );
  }
}

class _VizSpectrumPainter extends CustomPainter {
  _VizSpectrumPainter(this.viz) : super(repaint: viz);
  final VizController viz;

  @override
  void paint(Canvas canvas, Size size) {
    LiveSpectrumPainter(
      norms: viz.latestNorms,
      peakHold: viz.peakHoldValues,
      accentColor: AppColors.accent,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_VizSpectrumPainter old) =>
      !identical(viz.latestNorms, old.viz.latestNorms);
}

// ── Section header (sa-hdr) ───────────────────────────────────────────────────
// Outside cards: 9px uppercase dim label with standard padding.

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Text(
        label,
        style: AppTextStyles.mono(
          9, FontWeight.w500, const Color(0xFF7AB8AA),
          letterSpacing: 0.14 * 9,
        ),
      ),
    );
  }
}

// ── Group card (sa-grp) ───────────────────────────────────────────────────────
// bg #0d1712, borderRadius 13, no outer border. Rows separated by thin divider.

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1712),
        borderRadius: BorderRadius.circular(13),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children,
      ),
    );
  }
}

// ── Candidates group ──────────────────────────────────────────────────────────
// Top-4 candidates. Large BPM left (17px, 60px wide), full-width 4px bar, pct.
// Colour: main/top → teal; score>0.4 → amber; otherwise dark green.

class _CandidatesGroup extends StatelessWidget {
  const _CandidatesGroup({required this.candidates});
  final List<TempoCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    // Find top candidate (relation == 'main', or first if none).
    final topIdx = candidates.indexWhere((c) => c.relation == 'main');
    final topBpm = topIdx >= 0 ? candidates[topIdx].bpm : null;

    // Show top 4, sorted by score descending.
    final sorted = [...candidates]..sort((a, b) => b.score.compareTo(a.score));
    final top4 = sorted.take(4).toList();

    if (top4.isEmpty) {
      return _GroupCard(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('Нет кандидатов',
                style: AppTextStyles.mono(9, FontWeight.w400, AppColors.textMuted)),
          ),
        ],
      );
    }

    return _GroupCard(
      children: [
        for (int i = 0; i < top4.length; i++) ...[
          _CandidateRow(
            candidate: top4[i],
            isTop: top4[i].relation == 'main' ||
                (topBpm == null && i == 0),
            showDivider: i < top4.length - 1,
          ),
        ],
      ],
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    this.isTop = false,
    this.showDivider = false,
  });
  final TempoCandidate candidate;
  final bool isTop;
  final bool showDivider;

  Color get _barColor {
    if (isTop) return AppColors.accent;
    if (candidate.score > 0.4) return AppColors.yellow;
    return const Color(0xFF2A4A3E);
  }

  Color get _bpmColor {
    if (isTop) return AppColors.accent;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final pct = (candidate.score * 100).round();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              // BPM number — 62px wide, 20px semibold
              SizedBox(
                width: 62,
                child: Text(
                  candidate.bpm.toStringAsFixed(1),
                  style: AppTextStyles.mono(
                    20, FontWeight.w600, _bpmColor,
                  ),
                ),
              ),
              // Thin bar — fills remaining space, 4px height
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      value: candidate.score.clamp(0.0, 1.0),
                      backgroundColor: const Color(0xFF111916),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_barColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Percentage — 28px right-aligned
              SizedBox(
                width: 32,
                child: Text(
                  '$pct%',
                  textAlign: TextAlign.right,
                  style: AppTextStyles.mono(
                      9, FontWeight.w400, _barColor),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1, thickness: 1,
            color: Color(0xFF080C09),
            indent: 0, endIndent: 0,
          ),
      ],
    );
  }
}

// ── Algorithm metrics group ───────────────────────────────────────────────────
// Onset/Autocorr/Flux → bar rows (sa-bw: 80px, 5px).
// SNR / Input Level → text rows.
// Warnings → amber text rows at bottom.

class _MetricsGroup extends StatelessWidget {
  const _MetricsGroup({required this.debug, required this.quality});
  final DspDebug debug;
  final SignalQuality quality;

  @override
  Widget build(BuildContext context) {
    // Map raw DSP values to 0-100 for bar display.
    // onsetStrength is spectral-flux magnitude (0..~1 in practice).
    // tempoPeakProminence is autocorrelation peak height (0..~1).
    // onsetRateHz: typical 0-5 Hz → scale by /5.
    final onsetDetPct =
        (debug.onsetStrength.clamp(0.0, 1.0) * 100).round();
    final autocorrPct =
        (debug.tempoPeakProminence.clamp(0.0, 1.0) * 100).round();
    final fluxPct =
        ((debug.onsetRateHz / 5.0).clamp(0.0, 1.0) * 100).round();

    final rows = <Widget>[
      _MetricBarRow(
        label: 'Обнаружение онсетов',
        value: onsetDetPct / 100.0,
        pct: onsetDetPct,
        color: AppColors.accent,
        showDivider: true,
      ),
      _MetricBarRow(
        label: 'Автокорреляция',
        value: autocorrPct / 100.0,
        pct: autocorrPct,
        color: AppColors.accent,
        showDivider: true,
      ),
      _MetricBarRow(
        label: 'Спектральный поток',
        value: fluxPct / 100.0,
        pct: fluxPct,
        color: AppColors.yellow,
        showDivider: true,
      ),
      // Harmonic ambiguity: 0.0 = clean, 1.0+ = ambiguous → amber when high
      _MetricTextRow(
        label: 'Гарм. неоднозначность',
        value: debug.harmonicAmbiguity.toStringAsFixed(2),
        valueColor: debug.harmonicAmbiguity > 0.5
            ? AppColors.amberText
            : AppColors.textPrimary,
        showDivider: true,
      ),
      // Stability score: 0.0–1.0 → bar with accent colour
      _MetricBarRow(
        label: 'Стабильность',
        value: debug.stabilityScore.clamp(0.0, 1.0),
        pct: (debug.stabilityScore.clamp(0.0, 1.0) * 100).round(),
        color: AppColors.accent,
        showDivider: quality.snrEstimateDb != null ||
            quality.inputLevelDbfs != null ||
            debug.warnings.isNotEmpty,
      ),
      if (quality.snrEstimateDb != null)
        _MetricTextRow(
          label: 'SNR',
          value: '${quality.snrEstimateDb!.toStringAsFixed(1)} dB',
          showDivider: quality.inputLevelDbfs != null ||
              debug.warnings.isNotEmpty,
        ),
      if (quality.inputLevelDbfs != null)
        _MetricTextRow(
          label: 'Уровень входа',
          value: '${quality.inputLevelDbfs!.toStringAsFixed(1)} dBFS',
          showDivider: debug.warnings.isNotEmpty,
        ),
      for (int i = 0; i < debug.warnings.length; i++)
        _WarningRow(
          text: debug.warnings[i],
          showDivider: i < debug.warnings.length - 1,
        ),
    ];

    return _GroupCard(children: rows);
  }
}

class _MetricBarRow extends StatelessWidget {
  const _MetricBarRow({
    required this.label,
    required this.value,
    required this.pct,
    required this.color,
    this.showDivider = false,
  });
  final String label;
  final double value;   // 0.0–1.0
  final int pct;        // 0–100
  final Color color;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              // Label — flex:1
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.mono(
                      9, FontWeight.w400, AppColors.textSecondary),
                ),
              ),
              // Bar — 80px, 5px height
              SizedBox(
                width: 80,
                height: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: value,
                    backgroundColor: const Color(0xFF111916),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              // Percentage — 32px right
              SizedBox(
                width: 32,
                child: Text(
                  '$pct%',
                  textAlign: TextAlign.right,
                  style:
                      AppTextStyles.mono(9, FontWeight.w400, color),
                ),
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

class _MetricTextRow extends StatelessWidget {
  const _MetricTextRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.showDivider = false,
  });
  final String label;
  final String value;
  final Color? valueColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.mono(
                      9, FontWeight.w400, AppColors.textSecondary),
                ),
              ),
              Text(
                value,
                style: AppTextStyles.mono(
                    9, FontWeight.w400,
                    valueColor ?? AppColors.textPrimary),
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

class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.text, this.showDivider = false});
  final String text;
  final bool showDivider;

  // Translate raw DSP warning keys → Russian.
  static String _translate(String raw) {
    if (raw == 'breakdown_likely') return 'вероятен брейкдаун';
    if (raw == 'clipping') return 'клиппинг';
    // harmonic_ambiguity=X.XX
    if (raw.startsWith('harmonic_ambiguity=')) {
      final val = raw.substring('harmonic_ambiguity='.length);
      return 'гарм. неоднозначность: $val';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_outlined,
                  color: AppColors.yellow, size: 12),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _translate(text),
                  style: AppTextStyles.mono(
                      9, FontWeight.w400, AppColors.amberText),
                ),
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

// ── Signal Quality group ──────────────────────────────────────────────────────
// Compact: clipping, noise, silence, breakdown as text rows.

class _QualityGroup extends StatelessWidget {
  const _QualityGroup({required this.quality});
  final SignalQuality quality;

  static String _noiseLevel(String? v) {
    switch (v) {
      case 'low':       return 'низкий';
      case 'medium':    return 'средний';
      case 'high':      return 'высокий';
      case 'noise_only':return 'только шум';
      case 'unknown':   return 'неизвестно';
      default:          return v ?? '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String, Color?)>[
      (
        'Клиппинг',
        quality.clipping ? '⚠ перегруз' : 'нет',
        quality.clipping ? AppColors.danger : null,
      ),
      (
        'Клипп. кадры',
        '${(quality.clippedFrameRatio * 100).toStringAsFixed(1)}%',
        null,
      ),
      ('Уровень шума', _noiseLevel(quality.noiseLevel), null),
      ('Тишина', quality.silence ? 'да' : 'нет', null),
      (
        'Вероятен брейк',
        quality.breakdownLikely ? 'да' : 'нет',
        quality.breakdownLikely ? AppColors.yellow : null,
      ),
    ];

    return _GroupCard(
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          _MetricTextRow(
            label: rows[i].$1,
            value: rows[i].$2,
            showDivider: i < rows.length - 1,
          ),
        ],
      ],
    );
  }
}
