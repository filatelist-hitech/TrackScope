// Integration tests for SessionHistoryController throttling and session lifecycle.

import 'dart:async';

import 'package:flutter/widgets.dart' hide LockState;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:TrackScope/dsp/dsp_result.dart';
import 'package:TrackScope/history/session_history_controller.dart';
import 'package:TrackScope/monetization/feature_flags.dart';

// Builds a minimal DspResult with primaryBpm set.
DspResult makeResult(double bpm) {
  return DspResult(
    primaryBpm: bpm,
    confidence: 0.85,
    lockState: LockState.stable,
    signalQuality: const SignalQuality(
      inputLevelDbfs: -12.0,
      peakDbfs: -10.0,
      clipping: false,
      clippedFrameRatio: 0.0,
      noiseLevel: 'low',
      snrEstimateDb: 15.0,
      silence: false,
      breakdownLikely: false,
    ),
    candidates: const [],
    timing: const DspTiming(
      analysisTimeSec: 0.0,
      windowTimeSec: 12.0,
      hopTimeSec: 0.0025,
      firstLockTimeSec: null,
    ),
    debug: const DspDebug(
      onsetRateHz: 3.3,
      onsetStrength: 0.5,
      tempoPeakProminence: 0.8,
      harmonicAmbiguity: 0.1,
      stabilityScore: 0.9,
      warnings: [],
    ),
  );
}

void main() {
  setUpAll(() {
    WidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final flags = const FeatureFlags(isPro: true);

  test('new session created on init', () {
    final ctrl = SessionHistoryController(
      flags: flags,
      resultsStream: const Stream.empty(),
    );
    addTearDown(ctrl.dispose);

    expect(ctrl.currentSession, isNotNull);
    expect(ctrl.currentSession.snapshots, isEmpty);
  });

  test('first result within 30s window is logged', () async {
    final controller = StreamController<DspResult>();
    final ctrl = SessionHistoryController(
      flags: flags,
      resultsStream: controller.stream,
    );
    addTearDown(ctrl.dispose);
    addTearDown(controller.close);

    controller.add(makeResult(200.0));
    await Future.microtask(() {});

    expect(ctrl.currentSession.snapshots.length, 1);
    expect(ctrl.currentSession.snapshots.first.bpm, 200.0);
  });

  test('second result within 30s throttle window is ignored', () async {
    final controller = StreamController<DspResult>();
    final ctrl = SessionHistoryController(
      flags: flags,
      resultsStream: controller.stream,
    );
    addTearDown(ctrl.dispose);
    addTearDown(controller.close);

    controller.add(makeResult(200.0));
    await Future.microtask(() {});
    controller.add(makeResult(195.0));
    await Future.microtask(() {});

    // Only first snapshot passes through
    expect(ctrl.currentSession.snapshots.length, 1);
  });

  test('null primaryBpm is not logged', () async {
    final controller = StreamController<DspResult>();
    final ctrl = SessionHistoryController(
      flags: flags,
      resultsStream: controller.stream,
    );
    addTearDown(ctrl.dispose);
    addTearDown(controller.close);

    controller.add(DspResult(
      primaryBpm: null,
      confidence: 0.1,
      lockState: LockState.searching,
      signalQuality: const SignalQuality(
        inputLevelDbfs: null,
        peakDbfs: null,
        clipping: false,
        clippedFrameRatio: 0.0,
        noiseLevel: 'unknown',
        snrEstimateDb: null,
        silence: true,
        breakdownLikely: false,
      ),
      candidates: const [],
      timing: const DspTiming(
        analysisTimeSec: 0.0,
        windowTimeSec: 12.0,
        hopTimeSec: 0.0025,
        firstLockTimeSec: null,
      ),
      debug: const DspDebug(
        onsetRateHz: 0.0,
        onsetStrength: 0.0,
        tempoPeakProminence: 0.0,
        harmonicAmbiguity: 0.0,
        stabilityScore: 0.0,
        warnings: [],
      ),
    ));
    await Future.microtask(() {});

    expect(ctrl.currentSession.snapshots, isEmpty);
  });

  test('allSessions includes current session if it has data', () async {
    final controller = StreamController<DspResult>();
    final ctrl = SessionHistoryController(
      flags: flags,
      resultsStream: controller.stream,
    );
    addTearDown(ctrl.dispose);
    addTearDown(controller.close);

    controller.add(makeResult(200.0));
    await Future.microtask(() {});

    expect(ctrl.allSessions.length, greaterThanOrEqualTo(1));
    expect(ctrl.allSessions.first.snapshots.first.bpm, 200.0);
  });

  test('isEmpty returns true when no data', () {
    final ctrl = SessionHistoryController(
      flags: flags,
      resultsStream: const Stream.empty(),
    );
    addTearDown(ctrl.dispose);

    expect(ctrl.isEmpty, isTrue);
  });

  test('clear resets current session and past sessions', () async {
    final controller = StreamController<DspResult>();
    final ctrl = SessionHistoryController(
      flags: flags,
      resultsStream: controller.stream,
    );
    addTearDown(ctrl.dispose);
    addTearDown(controller.close);

    controller.add(makeResult(200.0));
    await Future.microtask(() {});
    ctrl.clear();

    expect(ctrl.currentSession.snapshots, isEmpty);
    expect(ctrl.allSessions, isEmpty);
  });

  test('flatSamples returns BpmSample list from all snapshots', () async {
    final controller = StreamController<DspResult>();
    final ctrl = SessionHistoryController(
      flags: flags,
      resultsStream: controller.stream,
    );
    addTearDown(ctrl.dispose);
    addTearDown(controller.close);

    controller.add(makeResult(195.0));
    await Future.microtask(() {});

    final flat = ctrl.flatSamples;
    expect(flat.length, 1);
    expect(flat.first.bpm, 195.0);
  });
}
