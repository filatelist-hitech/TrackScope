// Session data models.
//
// SessionSnapshot — один снимок состояния (BPM, confidence, lock_state).
// Session — одна сессия захвата (открытие приложения).
//
// Хранятся как JSON в SharedPreferences через SessionStore.

import 'dart:math' show min, max;

import '../dsp/dsp_result.dart' show LockState;

class SessionSnapshot {
  const SessionSnapshot({
    required this.timestamp,
    required this.bpm,
    required this.confidence,
    required this.lockState,
  });

  final DateTime timestamp;
  final double bpm;
  final double confidence;
  final LockState lockState;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'bpm': bpm,
        'confidence': confidence,
        'lock_state': lockState.name,
      };

  factory SessionSnapshot.fromJson(Map<String, dynamic> json) =>
      SessionSnapshot(
        timestamp: DateTime.parse(json['timestamp'] as String),
        bpm: (json['bpm'] as num).toDouble(),
        confidence: (json['confidence'] as num).toDouble(),
        lockState: _parseLockState(json['lock_state'] as String),
      );

  static LockState _parseLockState(String name) {
    return LockState.values.firstWhere(
      (e) => e.name == name,
      orElse: () => LockState.searching,
    );
  }
}

class Session {
  Session({
    required this.id,
    required this.startTime,
    this.endTime,
    List<SessionSnapshot>? snapshots,
  }) : snapshots = snapshots ?? [];

  final String id;
  final DateTime startTime;
  DateTime? endTime;
  final List<SessionSnapshot> snapshots;

  double get minBpm {
    if (snapshots.isEmpty) return 0;
    return snapshots.map((s) => s.bpm).reduce(min);
  }

  double get maxBpm {
    if (snapshots.isEmpty) return 0;
    return snapshots.map((s) => s.bpm).reduce(max);
  }

  double get peakConfidence {
    if (snapshots.isEmpty) return 0;
    return snapshots.map((s) => s.confidence).reduce(max);
  }

  Duration get duration =>
      (endTime ?? DateTime.now()).difference(startTime);

  bool get hasData => snapshots.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'start_time': startTime.toIso8601String(),
        if (endTime != null) 'end_time': endTime!.toIso8601String(),
        'snapshots': snapshots.map((s) => s.toJson()).toList(),
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        id: json['id'] as String,
        startTime: DateTime.parse(json['start_time'] as String),
        endTime: json['end_time'] != null
            ? DateTime.parse(json['end_time'] as String)
            : null,
        snapshots: (json['snapshots'] as List<dynamic>)
            .map((e) => SessionSnapshot.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
