// BPM history data model.
//
// Хранит временны́е сэмплы BPM с lock-state и timestamp. Ограничивается
// по времени (maxHistoryDuration) и по количеству (maxHistorySamples).

import '../dsp/dsp_result.dart';
import '../monetization/feature_flags.dart';

class BpmSample {
  const BpmSample({
    required this.bpm,
    required this.lockState,
    required this.timestamp,
    this.confidence = 0.0,
  });

  final double bpm;
  final LockState lockState;
  final DateTime timestamp;
  final double confidence; // 0.0–1.0

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'bpm': bpm,
        'lock_state': lockState.name,
        'confidence': confidence,
      };
}

class BpmHistory {
  BpmHistory(this.flags);

  final FeatureFlags flags;
  final List<BpmSample> _samples = [];

  List<BpmSample> get samples => List.unmodifiable(_samples);

  bool get isAtLimit {
    if (_samples.isEmpty) return false;
    final now = DateTime.now();
    final oldestAllowed = now.subtract(flags.maxHistoryDuration);
    return _samples.length >= flags.maxHistorySamples ||
        (_samples.first.timestamp.isBefore(oldestAllowed));
  }

  void add(BpmSample sample) {
    _samples.add(sample);
    _trimToLimits();
  }

  void clear() {
    _samples.clear();
  }

  void _trimToLimits() {
    final now = DateTime.now();
    final oldestAllowed = now.subtract(flags.maxHistoryDuration);

    // Удаляем сэмплы старше maxHistoryDuration
    _samples.removeWhere((s) => s.timestamp.isBefore(oldestAllowed));

    // Если всё ещё превышаем maxHistorySamples, удаляем самые старые
    while (_samples.length > flags.maxHistorySamples) {
      _samples.removeAt(0);
    }
  }
}
