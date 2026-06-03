import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/dsp/dsp_result.dart';
import 'package:TrackScope/features/setlist/setlist_service.dart';

DspResult _makeResult({
  LockState lockState = LockState.stable,
  double? primaryBpm = 200.0,
  double confidence = 0.9,
  KeyResult? keyResult,
  EnergyResult? energyResult,
}) {
  return DspResult(
    primaryBpm: primaryBpm,
    confidence: confidence,
    lockState: lockState,
    signalQuality: const SignalQuality(
      inputLevelDbfs: null,
      peakDbfs: null,
      clipping: false,
      clippedFrameRatio: 0.0,
      noiseLevel: 'low',
      snrEstimateDb: null,
      silence: false,
      breakdownLikely: false,
    ),
    candidates: const [],
    timing: const DspTiming(
      analysisTimeSec: 5.0,
      windowTimeSec: 12.0,
      hopTimeSec: 0.0025,
      firstLockTimeSec: 4.2,
    ),
    debug: const DspDebug(
      onsetRateHz: 0.0,
      onsetStrength: 0.0,
      tempoPeakProminence: 0.0,
      harmonicAmbiguity: 0.0,
      stabilityScore: 0.0,
      warnings: [],
    ),
    keyResult: keyResult,
    energyResult: energyResult,
  );
}

const _keyResult8A = KeyResult(
  key: 'A',
  mode: 'Minor',
  camelot: '8A',
  confidence: 0.72,
);

const _energyResult7 = EnergyResult(
  level: 7,
  rmsDbfs: -8.0,
  spectralFlux: 0.05,
  onsetDensityHz: 3.5,
);

void main() {
  group('SetlistService', () {
    late SetlistService service;

    setUp(() {
      service = SetlistService();
    });

    tearDown(() {
      service.dispose();
    });

    test('onDspResult ignored when not recording', () {
      service.onDspResult(_makeResult());
      expect(service.entryCount, 0);
    });

    test('startRecording → onDspResult STABLE adds entry', () {
      service.startRecording();
      service.onDspResult(_makeResult());
      expect(service.entryCount, 1);
      expect(service.entries.first.bpm, closeTo(200.0, 0.1));
    });

    test('non-STABLE result not recorded', () {
      service.startRecording();
      service.onDspResult(_makeResult(lockState: LockState.locking));
      service.onDspResult(_makeResult(lockState: LockState.searching));
      service.onDspResult(_makeResult(lockState: LockState.breakdown));
      expect(service.entryCount, 0);
    });

    test('null primaryBpm not recorded', () {
      service.startRecording();
      service.onDspResult(_makeResult(primaryBpm: null));
      expect(service.entryCount, 0);
    });

    test('deduplication: same BPM within 5s → single entry', () {
      service.startRecording();
      service.onDspResult(_makeResult(primaryBpm: 200.0));
      service.onDspResult(_makeResult(primaryBpm: 200.1));
      expect(service.entryCount, 1);
    });

    test('different BPM (delta > 0.5) creates new entry', () {
      service.startRecording();
      service.onDspResult(_makeResult(primaryBpm: 200.0));
      service.onDspResult(_makeResult(primaryBpm: 201.0));
      expect(service.entryCount, 2);
    });

    test('stopRecording prevents new entries', () {
      service.startRecording();
      service.onDspResult(_makeResult());
      service.stopRecording();
      service.onDspResult(_makeResult(primaryBpm: 205.0));
      expect(service.entryCount, 1);
    });

    test('exportJson contains required fields', () {
      service.startRecording();
      service.onDspResult(_makeResult(primaryBpm: 195.0));
      final json = service.exportJson();
      expect(json, contains('"bpm"'));
      expect(json, contains('"timestamp"'));
      expect(json, contains('"lock_state"'));
      expect(json, contains('"STABLE"'));
      expect(json, contains('"entry_count"'));
    });

    test('exportCsv contains header and rows', () {
      service.startRecording();
      service.onDspResult(_makeResult(primaryBpm: 192.0));
      final csv = service.exportCsv();
      expect(csv, contains('timestamp,bpm,lock_state'));
      expect(csv, contains('STABLE'));
      expect(csv, contains('192.0'));
    });

    test('clear resets entries and recording state', () {
      service.startRecording();
      service.onDspResult(_makeResult());
      service.clear();
      expect(service.entryCount, 0);
      expect(service.isRecording, isFalse);
    });

    test('averageBpm computed correctly', () {
      service.startRecording();
      service.onDspResult(_makeResult(primaryBpm: 190.0));
      service.onDspResult(_makeResult(primaryBpm: 210.0));
      expect(service.averageBpm, closeTo(200.0, 0.1));
    });

    // Phase 2.4: camelot key + energy level

    test('onDspResult with key_result stores camelotKey in entry', () {
      service.startRecording();
      service.onDspResult(_makeResult(keyResult: _keyResult8A));
      expect(service.entries.first.camelotKey, equals('8A'));
    });

    test('onDspResult without key_result stores null camelotKey', () {
      service.startRecording();
      service.onDspResult(_makeResult());
      expect(service.entries.first.camelotKey, isNull);
    });

    test('onDspResult with energy_result stores energyLevel in entry', () {
      service.startRecording();
      service.onDspResult(_makeResult(energyResult: _energyResult7));
      expect(service.entries.first.energyLevel, equals(7));
    });

    test('exportJson contains camelot_key when present', () {
      service.startRecording();
      service.onDspResult(_makeResult(keyResult: _keyResult8A));
      final json = service.exportJson();
      expect(json, contains('"camelot_key"'));
      expect(json, contains('"8A"'));
    });

    test('exportJson contains has_key_data field', () {
      service.startRecording();
      service.onDspResult(_makeResult(keyResult: _keyResult8A));
      final json = service.exportJson();
      expect(json, contains('"has_key_data": true'));
      expect(json, contains('"has_energy_data": false'));
    });

    test('exportCsv header contains camelot_key and energy_level columns', () {
      service.startRecording();
      service.onDspResult(_makeResult());
      final csv = service.exportCsv();
      expect(csv, contains('camelot_key'));
      expect(csv, contains('energy_level'));
    });

    test('exportCsv row contains empty strings when camelot/energy null', () {
      service.startRecording();
      service.onDspResult(_makeResult(primaryBpm: 200.0));
      final csv = service.exportCsv();
      // The row ends with two empty columns: ,, at end
      final rows = csv.trim().split('\n');
      expect(rows.length, equals(2)); // header + 1 row
      // last two CSV columns are empty
      final row = rows[1];
      expect(row, endsWith(',,'));
    });
  });
}
