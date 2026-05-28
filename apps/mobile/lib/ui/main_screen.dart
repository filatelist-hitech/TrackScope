// Живой экран BPM. Через StreamBuilder подписывается на
// CaptureBridge.results и напрямую рисует каждое поле из последнего
// DspResult — никакого производного состояния, никаких запасных
// значений, никакого фейкового BPM.
//
// Структура:
//   • ~45 % высоты — SpectrogramView: скроллящаяся FFT-карта аудио.
//   • ~15 % высоты — WaveformView: амплитуда PCM, краснеет при клиппинге.
//   • ~40 % высоты — InfoTable: поля из DspResult, badge lock_state.
//
// Обе визуализации питаются реальным PCM из CaptureBridge.rawPcm.
// Если rawPcm == null — плейсхолдер «Ожидание микрофона…».
// VizController живёт в State и освобождается в dispose().

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide LockState;

import '../capture/bpm_display.dart';
import '../capture/capture_bridge.dart';
import '../dsp/dsp_result.dart';
import '../viz/spectrogram_painter.dart';
import '../viz/viz_controller.dart';
import '../viz/waveform_painter.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────

const _kBg = Color(0xFF0A0A0F);
const _kSurface = Color(0xFF12121A);
const _kMono = TextStyle(fontFamily: 'monospace');

// ── MainScreen ────────────────────────────────────────────────────────────────

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    required this.results,
    required this.errors,
    required this.debugBuilder,
    this.rawPcm,
  });

  final Stream<DspResult> results;
  final Stream<CaptureError> errors;

  /// Как строится debug-экран, когда пользователь нажимает иконку жука.
  final WidgetBuilder debugBuilder;

  /// Raw PCM-16 LE mono bytes from CaptureBridge.rawPcm. Null in unit tests
  /// and before mic permission is granted — visualisers show a placeholder.
  final Stream<Uint8List>? rawPcm;

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
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        title: const Text(
          'Hitech BPM Radar',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 15,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined, color: Colors.white54),
            tooltip: 'Отладка',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: widget.debugBuilder,
              ));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<DspResult>(
          stream: widget.results,
          builder: (context, snap) {
            if (snap.data != null) _lastResult = snap.data;
            final result = _lastResult;
            final displayBpm = result != null ? _bpmDisplay.update(result) : null;
            final isClipping = result?.signalQuality.clipping ?? false;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_lastError != null) _ErrorBanner(error: _lastError!),

                // ── Spectrogram (45 %) ──────────────────────────────────────
                Expanded(
                  flex: 45,
                  child: RepaintBoundary(
                    child: ListenableBuilder(
                      listenable: _viz,
                      builder: (_, __) {
                        if (!_viz.hasData) {
                          return Container(
                            color: _kBg,
                            alignment: Alignment.center,
                            child: const Text(
                              'Ожидание микрофона…',
                              style: TextStyle(
                                color: Color(0xFF444466),
                                fontFamily: 'monospace',
                                fontSize: 14,
                              ),
                            ),
                          );
                        }
                        return CustomPaint(
                          painter: SpectrogramPainter(
                            cols: _viz.specCols,
                            lutPaints: _viz.lutPaints,
                          ),
                          child: const SizedBox.expand(),
                        );
                      },
                    ),
                  ),
                ),

                // ── Waveform (15 %) ─────────────────────────────────────────
                Expanded(
                  flex: 15,
                  child: RepaintBoundary(
                    child: ListenableBuilder(
                      listenable: _viz,
                      builder: (_, __) => CustomPaint(
                        painter: WaveformPainter(
                          samples: _viz.waveCache,
                          isClipping: isClipping,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),

                // ── Info table (40 %) ───────────────────────────────────────
                Expanded(
                  flex: 40,
                  child: _InfoTable(result: result, displayBpm: displayBpm),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Info table ────────────────────────────────────────────────────────────────

class _InfoTable extends StatelessWidget {
  const _InfoTable({required this.result, this.displayBpm});
  final DspResult? result;
  /// EMA-сглаженное значение BPM для большого числа на экране.
  /// null когда lock_state != STABLE или primary_bpm ещё не доступен.
  final double? displayBpm;

  @override
  Widget build(BuildContext context) {
    final r = result;
    // displayBpm приоритетен для большого числа (EMA-сглаженный).
    // Если BpmDisplay ещё не вошёл в STABLE — используем raw primary_bpm.
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

    // Half-time and double-time for display.
    final halfCand = r?.candidates
        .where((c) => c.relation == 'half_time' || c.relation == 'normalized_from_half')
        .toList();
    final doubleCand = r?.candidates
        .where((c) => c.relation == 'double_time' || c.relation == 'normalized_from_double')
        .toList();

    final halfBpm = (halfCand?.isNotEmpty ?? false)
        ? halfCand!.first.bpm.toStringAsFixed(1)
        : '—';
    final doubleBpm = (doubleCand?.isNotEmpty ?? false)
        ? doubleCand!.first.bpm.toStringAsFixed(1)
        : '—';

    return Container(
      color: _kSurface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Row 1: BPM + lock badge ────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                bpm == null ? '—' : bpm.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontFamily: 'monospace',
                  height: 1.0,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 6, bottom: 6),
                child: Text(
                  'BPM',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white38,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const Spacer(),
              _LockBadge(state: lock),
            ],
          ),
          const SizedBox(height: 10),

          // ── Row 2: confidence + input level ───────────────────────────
          Row(
            children: [
              Expanded(
                child: _Cell(
                  label: 'Уверенность',
                  value: '${(conf * 100).round()}%',
                ),
              ),
              Expanded(
                child: _Cell(
                  label: 'Уровень входа',
                  value: sq?.inputLevelDbfs != null
                      ? '${sq!.inputLevelDbfs!.toStringAsFixed(1)} dBFS'
                      : '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Row 3: best candidate + half / double ──────────────────────
          Row(
            children: [
              Expanded(
                child: _Cell(
                  label: 'Лучший кандидат',
                  value: best != null ? '${best.bpm.toStringAsFixed(1)} BPM' : '—',
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

          // ── Row 4: clipping + noise level ─────────────────────────────
          Row(
            children: [
              Expanded(
                child: _Cell(
                  label: 'Клиппинг',
                  value: sq?.clipping == true ? '⚠ ПЕРЕГРУЗ' : 'нет',
                  valueColor:
                      sq?.clipping == true ? Colors.red.shade300 : null,
                ),
              ),
              Expanded(
                child: _Cell(
                  label: 'Шум',
                  value: _noiseLabel(sq?.noiseLevel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _noiseLabel(String? level) {
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
            fontSize: 10,
            color: Colors.white38,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: _kMono.copyWith(
            fontSize: 13,
            color: valueColor ?? Colors.white70,
          ),
        ),
      ],
    );
  }
}

// ── Lock badge ────────────────────────────────────────────────────────────────

class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.state});
  final LockState state;

  @override
  Widget build(BuildContext context) {
    final (label, bg) = _scheme(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  (String, Color) _scheme(LockState s) {
    switch (s) {
      case LockState.stable:
        return ('стабильно', const Color(0xFF2E7D32));
      case LockState.locking:
        return ('захват', const Color(0xFFF57F17));
      case LockState.unstable:
        return ('нестабильно', const Color(0xFFE65100));
      case LockState.breakdown:
        return ('брейк', const Color(0xFF1565C0));
      case LockState.clippedMic:
        return ('перегруз микрофона', const Color(0xFFC62828));
      case LockState.noiseOnly:
        return ('только шум', const Color(0xFF4A148C));
      case LockState.searching:
      case LockState.unknown:
        return ('поиск', const Color(0xFF37474F));
    }
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
      color: const Color(0xFF7F0000),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ошибка захвата: ${error.message}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
