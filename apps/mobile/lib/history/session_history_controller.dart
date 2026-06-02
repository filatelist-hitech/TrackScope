// Session history controller — подписывается на CaptureBridge.results,
// даунсэмплирует до ~1 Hz и сохраняет в BpmHistory.
//
// ChangeNotifier для реактивности UI. Пересоздаётся при изменении
// FeatureFlags (смена tier → новые лимиты истории).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../dsp/dsp_result.dart';
import '../monetization/feature_flags.dart';
import 'bpm_history.dart';

class SessionHistoryController extends ChangeNotifier {
  SessionHistoryController({
    required FeatureFlags flags,
    required Stream<DspResult> resultsStream,
  })  : _history = BpmHistory(flags) {
    _subscription = resultsStream.listen(_onResult);
  }

  final BpmHistory _history;
  StreamSubscription<DspResult>? _subscription;
  DateTime? _lastSampleTime;

  BpmHistory get history => _history;
  bool get isAtLimit => _history.isAtLimit;

  void _onResult(DspResult result) {
    // Даунсэмплинг: сохраняем только когда primaryBpm != null и прошло ≥1 сек
    if (result.primaryBpm == null) return;

    final now = DateTime.now();
    if (_lastSampleTime != null &&
        now.difference(_lastSampleTime!).inSeconds < 1) {
      return;
    }

    _lastSampleTime = now;
    _history.add(BpmSample(
      bpm: result.primaryBpm!,
      lockState: result.lockState,
      timestamp: now,
      confidence: result.confidence,
    ));
    notifyListeners();
  }

  void clear() {
    _history.clear();
    _lastSampleTime = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
