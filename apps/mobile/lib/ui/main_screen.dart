// Live BPM screen. Subscribes to `CaptureBridge.results` via a
// StreamBuilder and renders every field from the latest `DspResult`
// directly — no derived state, no fallback values, no fake BPM.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart' hide LockState;

import '../capture/capture_bridge.dart';
import '../dsp/dsp_result.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    required this.results,
    required this.errors,
    required this.debugBuilder,
  });

  final Stream<DspResult> results;
  final Stream<CaptureError> errors;

  /// How the debug screen is constructed when the user taps the bug
  /// icon. Injected so widget tests can substitute a stub builder.
  final WidgetBuilder debugBuilder;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const int _historyLength = 60;
  final Queue<double?> _bpmHistory = Queue<double?>();
  StreamSubscription<CaptureError>? _errSub;
  CaptureError? _lastError;

  @override
  void initState() {
    super.initState();
    _errSub = widget.errors.listen((err) {
      if (!mounted) return;
      setState(() => _lastError = err);
    });
  }

  @override
  void dispose() {
    _errSub?.cancel();
    super.dispose();
  }

  void _recordHistory(double? bpm) {
    _bpmHistory.addLast(bpm);
    while (_bpmHistory.length > _historyLength) {
      _bpmHistory.removeFirst();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hitech BPM Radar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Debug',
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
            final result = snap.data;
            if (result != null) {
              _recordHistory(result.primaryBpm);
            }
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_lastError != null)
                    _ErrorBanner(error: _lastError!),
                  _BpmReadout(result: result),
                  const SizedBox(height: 16),
                  _ConfidenceAndLock(result: result),
                  const SizedBox(height: 16),
                  _SignalQualityMeter(result: result),
                  const SizedBox(height: 16),
                  Expanded(child: _HistorySparkline(history: _bpmHistory)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BpmReadout extends StatelessWidget {
  const _BpmReadout({required this.result});
  final DspResult? result;

  @override
  Widget build(BuildContext context) {
    final bpm = result?.primaryBpm;
    final text = bpm == null ? '— —' : bpm.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PRIMARY BPM',
            style: TextStyle(letterSpacing: 1.5, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _ConfidenceAndLock extends StatelessWidget {
  const _ConfidenceAndLock({required this.result});
  final DspResult? result;

  @override
  Widget build(BuildContext context) {
    final lock = result?.lockState ?? LockState.searching;
    final conf = result?.confidence ?? 0.0;
    final pct = (conf * 100).round();
    return Row(
      children: [
        _LockBadge(state: lock),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Confidence $pct%'),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: conf.clamp(0.0, 1.0)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.state});
  final LockState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color bg;
    switch (state) {
      case LockState.stable:
        bg = Colors.green.shade700;
        break;
      case LockState.locking:
        bg = Colors.amber.shade700;
        break;
      case LockState.unstable:
      case LockState.breakdown:
        bg = Colors.deepOrange;
        break;
      case LockState.clippedMic:
        bg = scheme.error;
        break;
      case LockState.noiseOnly:
        bg = Colors.blueGrey;
        break;
      case LockState.searching:
      case LockState.unknown:
        bg = scheme.surfaceContainerHighest;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(state.wireName,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0)),
    );
  }
}

class _SignalQualityMeter extends StatelessWidget {
  const _SignalQualityMeter({required this.result});
  final DspResult? result;

  @override
  Widget build(BuildContext context) {
    final sq = result?.signalQuality;
    final dbfs = sq?.inputLevelDbfs;
    // -60 dBFS → 0.0, 0 dBFS → 1.0 (clamped).
    final norm =
        dbfs == null ? 0.0 : ((dbfs + 60.0) / 60.0).clamp(0.0, 1.0);
    final clipping = sq?.clipping ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Input level: ${dbfs?.toStringAsFixed(1) ?? '—'} dBFS',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (clipping)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('CLIPPING',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: norm,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            color: clipping ? Theme.of(context).colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}

class _HistorySparkline extends StatelessWidget {
  const _HistorySparkline({required this.history});
  final Queue<double?> history;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent BPM',
            style: TextStyle(letterSpacing: 1.5, fontSize: 12)),
        const SizedBox(height: 8),
        Expanded(
          child: CustomPaint(
            painter: _SparkPainter(
              history.toList(growable: false),
              Theme.of(context).colorScheme,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.scheme);
  final List<double?> points;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final valid = points.whereType<double>().toList();
    if (valid.isEmpty) return;
    final minV = valid.reduce((a, b) => a < b ? a : b) - 1.0;
    final maxV = valid.reduce((a, b) => a > b ? a : b) + 1.0;
    final range = (maxV - minV).clamp(1.0, double.infinity);
    final stepX = size.width / (points.length - 1).clamp(1, 999);
    final paint = Paint()
      ..color = scheme.primary
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final path = Path();
    var started = false;
    for (var i = 0; i < points.length; i++) {
      final v = points[i];
      if (v == null) {
        started = false;
        continue;
      }
      final x = i * stepX;
      final y = size.height - ((v - minV) / range) * size.height;
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      !identical(old.points, points);
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});
  final CaptureError error;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Capture error: ${error.message}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
