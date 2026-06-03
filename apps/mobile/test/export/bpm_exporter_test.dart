// bpm_exporter unit tests — pure buildCsv and buildJson builders.

import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/dsp/dsp_result.dart';
import 'package:TrackScope/export/bpm_exporter.dart';
import 'package:TrackScope/history/bpm_history.dart';

List<BpmSample> _mockSamples() {
  final base = DateTime(2026, 5, 31, 12, 0, 0);
  return [
    BpmSample(bpm: 200.0, lockState: LockState.stable, timestamp: base),
    BpmSample(bpm: 198.4, lockState: LockState.stable,
        timestamp: base.add(const Duration(seconds: 1))),
    BpmSample(bpm: 197.0, lockState: LockState.locking,
        timestamp: base.add(const Duration(seconds: 2))),
  ];
}

void main() {
  group('buildCsv', () {
    test('has correct header', () {
      final csv = buildCsv(_mockSamples());
      expect(csv.startsWith('timestamp,bpm,lock_state\n'), isTrue);
    });

    test('has one row per sample', () {
      final csv = buildCsv(_mockSamples());
      final lines = csv.trim().split('\n');
      expect(lines.length, 4); // header + 3 rows
    });

    test('rows contain bpm and lock_state', () {
      final csv = buildCsv(_mockSamples());
      expect(csv, contains('200.0'));
      expect(csv, contains('198.4'));
      expect(csv, contains('stable'));
      expect(csv, contains('locking'));
    });

    test('empty list produces header only', () {
      final csv = buildCsv([]);
      expect(csv.trim(), 'timestamp,bpm,lock_state');
    });
  });

  group('buildJson', () {
    test('has app and exported_at keys', () {
      final json = buildJson(_mockSamples());
      expect(json, contains('"app":"hitech_bpm_radar"'));
      expect(json, contains('"exported_at"'));
    });

    test('samples array has correct count', () {
      final json = buildJson(_mockSamples());
      expect(json, contains('"samples"'));
      // Count occurrences of "bpm" as a key inside samples.
      expect(json.split('"bpm":').length - 1, 3);
    });

    test('each sample has timestamp, bpm, lock_state', () {
      final json = buildJson(_mockSamples());
      expect(json, contains('"timestamp"'));
      expect(json, contains('"lock_state"'));
    });

    test('empty list produces empty samples array', () {
      final json = buildJson([]);
      expect(json, contains('"samples":[]'));
    });
  });
}
