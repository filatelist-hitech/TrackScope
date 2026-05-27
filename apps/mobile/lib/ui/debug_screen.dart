// Debug-экран. Подписывается на тот же поток `CaptureBridge.results`,
// что и главный экран; рисует полный список BPM-кандидатов (raw +
// half / double / normalized) и каждое поле `signal_quality`.
// Кандидаты половинного и удвоенного темпа показываются всегда — UI
// их никогда не прячет.

import 'package:flutter/material.dart';

import '../dsp/dsp_result.dart';

class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key, required this.results});

  final Stream<DspResult> results;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Отладка')),
      body: StreamBuilder<DspResult>(
        stream: results,
        builder: (context, snap) {
          final r = snap.data;
          if (r == null) {
            return const Center(
                child: Text('Ожидание первого снапшота DspResult…'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Section(
                title: 'BPM-кандидаты (${r.candidates.length})',
                child: Column(
                  children: [
                    for (final c in r.candidates) _CandidateRow(candidate: c),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Качество сигнала',
                child: _SignalQualityTable(quality: r.signalQuality),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Тайминги',
                child: _TimingTable(timing: r.timing),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700, letterSpacing: 1.0)),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(padding: const EdgeInsets.all(12), child: child),
        ),
      ],
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.candidate});
  final TempoCandidate candidate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(candidate.bpm.toStringAsFixed(2),
                style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            width: 170,
            child: Text(candidate.relation,
                style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Text(
              'оценка ${candidate.score.toStringAsFixed(3)}'
              '${candidate.sourceBpm != null ? '  ← ${candidate.sourceBpm!.toStringAsFixed(1)}' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalQualityTable extends StatelessWidget {
  const _SignalQualityTable({required this.quality});
  final SignalQuality quality;

  @override
  Widget build(BuildContext context) {
    String fmt(double? v) => v == null ? '—' : v.toStringAsFixed(2);
    return Column(
      children: [
        _kv('input_level_dbfs', fmt(quality.inputLevelDbfs)),
        _kv('peak_dbfs', fmt(quality.peakDbfs)),
        _kv('clipping', quality.clipping.toString()),
        _kv('clipped_frame_ratio', quality.clippedFrameRatio.toStringAsFixed(3)),
        _kv('noise_level', quality.noiseLevel),
        _kv('snr_estimate_db', fmt(quality.snrEstimateDb)),
        _kv('silence', quality.silence.toString()),
        _kv('breakdown_likely', quality.breakdownLikely.toString()),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 170, child: Text(k, style: const TextStyle(fontSize: 12))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(
                        fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]))),
          ],
        ),
      );
}

class _TimingTable extends StatelessWidget {
  const _TimingTable({required this.timing});
  final DspTiming timing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _kv('analysis_time_sec', timing.analysisTimeSec.toStringAsFixed(2)),
        _kv('window_time_sec', timing.windowTimeSec.toStringAsFixed(3)),
        _kv('hop_time_sec', timing.hopTimeSec.toStringAsFixed(4)),
        _kv('first_lock_time_sec',
            timing.firstLockTimeSec?.toStringAsFixed(2) ?? '—'),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 170, child: Text(k, style: const TextStyle(fontSize: 12))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(
                        fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]))),
          ],
        ),
      );
}
