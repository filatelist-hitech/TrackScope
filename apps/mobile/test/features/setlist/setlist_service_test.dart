import 'package:flutter_test/flutter_test.dart';
import 'package:hitech_bpm_radar/dsp/dsp_result.dart';
import 'package:hitech_bpm_radar/features/setlist/setlist_service.dart';

DspResult _makeResult({
  LockState lockState = LockState.stable,
  double? primaryBpm = 200.0,
  double confidence = 0.9,
  double inputLevelDbfs = -14.0,
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
  );
}

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
      // Второй вызов сразу после — дедуплицируется (delta < 0.5, secs < 5)
      service.onDspResult(_makeResult(primaryBpm: 200.1));
      expect(service.entryCount, 1);
    });

    test('different BPM (delta > 0.5) creates new entry', () {
      service.startRecording();
      service.onDspResult(_makeResult(primaryBpm: 200.0));
      service.onDspResult(_makeResult(primaryBpm: 201.0)); // delta = 1.0 > 0.5
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
      service.onDspResult(_makeResult(primaryBpm: 210.0)); // delta > 0.5
      expect(service.averageBpm, closeTo(200.0, 0.1));
    });
  });
}
