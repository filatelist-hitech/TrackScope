// Unit tests for Session and SessionSnapshot models.

import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/dsp/dsp_result.dart';
import 'package:TrackScope/history/session.dart';

SessionSnapshot snap(double bpm, double confidence) => SessionSnapshot(
      timestamp: DateTime(2026, 6, 4, 12, 0, 0),
      bpm: bpm,
      confidence: confidence,
      lockState: LockState.stable,
    );

void main() {
  group('SessionSnapshot', () {
    test('toJson / fromJson round-trip', () {
      final s = snap(200.0, 0.88);
      final json = s.toJson();
      final restored = SessionSnapshot.fromJson(json);

      expect(restored.bpm, s.bpm);
      expect(restored.confidence, s.confidence);
      expect(restored.lockState, s.lockState);
      expect(restored.timestamp, s.timestamp);
    });

    test('unknown lock_state falls back to searching', () {
      final json = {
        'timestamp': '2026-06-04T12:00:00.000',
        'bpm': 190.0,
        'confidence': 0.7,
        'lock_state': 'totally_unknown_state',
      };
      final s = SessionSnapshot.fromJson(json);
      expect(s.lockState, LockState.searching);
    });
  });

  group('Session', () {
    test('minBpm / maxBpm / peakConfidence computed correctly', () {
      final session = Session(
        id: '1',
        startTime: DateTime(2026, 6, 4, 12, 0),
        snapshots: [snap(170.0, 0.7), snap(200.0, 0.9), snap(185.0, 0.8)],
      );

      expect(session.minBpm, 170.0);
      expect(session.maxBpm, 200.0);
      expect(session.peakConfidence, 0.9);
    });

    test('empty session returns zeros for stats', () {
      final session = Session(id: '1', startTime: DateTime.now());
      expect(session.minBpm, 0.0);
      expect(session.maxBpm, 0.0);
      expect(session.peakConfidence, 0.0);
    });

    test('hasData returns false when no snapshots', () {
      final session = Session(id: '1', startTime: DateTime.now());
      expect(session.hasData, isFalse);
    });

    test('hasData returns true when snapshots present', () {
      final session = Session(
        id: '1',
        startTime: DateTime.now(),
        snapshots: [snap(200.0, 0.9)],
      );
      expect(session.hasData, isTrue);
    });

    test('duration uses endTime when set', () {
      final start = DateTime(2026, 6, 4, 12, 0, 0);
      final end = DateTime(2026, 6, 4, 12, 13, 0);
      final session = Session(id: '1', startTime: start, endTime: end);
      expect(session.duration.inMinutes, 13);
    });

    test('toJson / fromJson round-trip', () {
      final session = Session(
        id: 'abc123',
        startTime: DateTime(2026, 6, 4, 12, 0, 0),
        endTime: DateTime(2026, 6, 4, 12, 10, 0),
        snapshots: [snap(200.0, 0.85)],
      );
      final json = session.toJson();
      final restored = Session.fromJson(json);

      expect(restored.id, session.id);
      expect(restored.startTime, session.startTime);
      expect(restored.endTime, session.endTime);
      expect(restored.snapshots.length, 1);
      expect(restored.snapshots.first.bpm, 200.0);
    });

    test('fromJson handles missing endTime', () {
      final json = {
        'id': '1',
        'start_time': '2026-06-04T12:00:00.000',
        'snapshots': [],
      };
      final session = Session.fromJson(json);
      expect(session.endTime, isNull);
    });
  });
}
