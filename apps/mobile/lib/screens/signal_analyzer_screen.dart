// Signal Analyzer Screen — Pro-only, Design System v2.
//
// Renamed from DebugScreen. Shows:
//   1. BPM Candidates list (top candidate in accent, others muted)
//   2. Signal Quality table
//   3. Algorithm Metrics placeholder (DspDebug not yet in Dart contract)
//   4. Timing table
//
// Anti-fake: all data comes from DspResult stream; no hardcoded values.
// DspDebug is not yet exposed through the Dart FFI contract — the
// "Algorithm Metrics" section shows an explicit placeholder, not random numbers.

import 'package:flutter/material.dart';

import '../dsp/dsp_result.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/confidence_bar.dart';

class SignalAnalyzerScreen extends StatelessWidget {
  const SignalAnalyzerScreen({super.key, required this.results});

  final Stream<DspResult> results;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          'Signal Analyzer',
          style: AppTextStyles.mono(14, FontWeight.w500, AppColors.textPrimary),
        ),
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),
      body: StreamBuilder<DspResult>(
        stream: results,
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
            padding: const EdgeInsets.all(14),
            children: [
              _CandidatesSection(candidates: r.candidates),
              const SizedBox(height: 14),
              _AlgorithmMetricsSection(debug: r.debug, quality: r.signalQuality),
              const SizedBox(height: 14),
              _SignalQualitySection(quality: r.signalQuality),
              const SizedBox(height: 14),
              _TimingSection(timing: r.timing),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// ── BPM Candidates ────────────────────────────────────────────────────────────

class _CandidatesSection extends StatelessWidget {
  const _CandidatesSection({required this.candidates});
  final List<TempoCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'BPM-кандидаты (${candidates.length})',
      child: Column(
        children: [
          for (int i = 0; i < candidates.length; i++)
            _CandidateRow(
              candidate: candidates[i],
              isTop: candidates[i].relation == 'main' ||
                  (i == 0 && candidates.every((c) => c.relation != 'main')),
            ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.candidate, this.isTop = false});
  final TempoCandidate candidate;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    final color = isTop ? AppColors.accent : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              '${candidate.bpm.toStringAsFixed(1)} BPM',
              style: AppTextStyles.mono(
                isTop ? 13 : 11,
                isTop ? FontWeight.w600 : FontWeight.w400,
                color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(
              candidate.relation,
              style: AppTextStyles.mono(
                  9, FontWeight.w400, AppColors.textMuted,
                  letterSpacing: 0.5),
            ),
          ),
          Expanded(
            child: ConfidenceBar(confidence: candidate.score),
          ),
        ],
      ),
    );
  }
}

// ── Signal Quality ────────────────────────────────────────────────────────────

class _SignalQualitySection extends StatelessWidget {
  const _SignalQualitySection({required this.quality});
  final SignalQuality quality;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Качество сигнала',
      child: Column(
        children: [
          if (quality.inputLevelDbfs != null)
            _MetricRow('Input Level',
                '${quality.inputLevelDbfs!.toStringAsFixed(1)} dBFS'),
          _MetricRow('Clipping',
              quality.clipping ? '⚠ ПЕРЕГРУЗ' : 'нет',
              valueColor: quality.clipping ? AppColors.danger : null),
          _MetricRow('Clipped frames',
              '${(quality.clippedFrameRatio * 100).toStringAsFixed(1)}%'),
          _MetricRow('Noise Level', quality.noiseLevel),
          if (quality.snrEstimateDb != null)
            _MetricRow('SNR',
                '${quality.snrEstimateDb!.toStringAsFixed(1)} dB'),
          _MetricRow('Тишина', quality.silence ? 'да' : 'нет'),
          _MetricRow('Вероятен брейк',
              quality.breakdownLikely ? 'да' : 'нет'),
        ],
      ),
    );
  }
}

// ── Algorithm Metrics — реальные данные из DspDebug ──────────────────────────

class _AlgorithmMetricsSection extends StatelessWidget {
  const _AlgorithmMetricsSection({
    required this.debug,
    required this.quality,
  });

  final DspDebug debug;
  final SignalQuality quality;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Метрики алгоритма',
      child: Column(
        children: [
          _MetricRow(
            'Onset rate',
            '${debug.onsetRateHz.toStringAsFixed(2)} Hz',
          ),
          _MetricRow(
            'Onset strength',
            debug.onsetStrength.toStringAsFixed(4),
          ),
          _MetricRow(
            'Peak prominence',
            debug.tempoPeakProminence.toStringAsFixed(4),
          ),
          _MetricRow(
            'Harmonic ambiguity',
            debug.harmonicAmbiguity.toStringAsFixed(4),
          ),
          _MetricRow(
            'Stability score',
            debug.stabilityScore.toStringAsFixed(4),
          ),
          if (quality.snrEstimateDb != null)
            _MetricRow(
              'SNR',
              '${quality.snrEstimateDb!.toStringAsFixed(1)} dB',
            ),
          if (debug.warnings.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final w in debug.warnings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_outlined,
                        color: AppColors.yellow, size: 12),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        w,
                        style: AppTextStyles.mono(
                            10, FontWeight.w400, AppColors.amberText),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Timing ────────────────────────────────────────────────────────────────────

class _TimingSection extends StatelessWidget {
  const _TimingSection({required this.timing});
  final DspTiming timing;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Тайминги',
      child: Column(
        children: [
          _MetricRow('Analysis time',
              '${timing.analysisTimeSec.toStringAsFixed(3)} s'),
          _MetricRow('Window',
              '${timing.windowTimeSec.toStringAsFixed(2)} s'),
          _MetricRow('Hop', '${timing.hopTimeSec.toStringAsFixed(4)} s'),
          if (timing.firstLockTimeSec != null)
            _MetricRow('First lock',
                '${timing.firstLockTimeSec!.toStringAsFixed(2)} s'),
        ],
      ),
    );
  }
}

// ── Reusable card ─────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.sectionLabel),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ── Metric row ────────────────────────────────────────────────────────────────

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value, {this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.mono(
                  10, FontWeight.w400, AppColors.textMuted),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.mono(
              10, FontWeight.w400,
              valueColor ?? AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
