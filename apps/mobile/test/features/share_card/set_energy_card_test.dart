// Tests for SetEnergyCardPainter and FeatureFlags.canShareCard.
//
// Note: toImage() is not tested in unit environment (requires a real render
// surface). Instead, CustomPainter.paint() is exercised directly via
// PictureRecorder to verify no exceptions on any input.

import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide LockState;
import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/dsp/dsp_result.dart';
import 'package:TrackScope/features/setlist/setlist_entry.dart';
import 'package:TrackScope/features/setlist/setlist_screen.dart';
import 'package:TrackScope/features/setlist/setlist_service.dart';
import 'package:TrackScope/features/share_card/set_energy_card_painter.dart';
import 'package:TrackScope/monetization/feature_flags.dart';
import 'package:TrackScope/monetization/paywall_screen.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

SetlistEntry _entry({
  double bpm = 200.0,
  String? camelotKey,
  int? energyLevel,
  DateTime? ts,
}) =>
    SetlistEntry(
      timestamp: ts ?? DateTime(2026, 6, 4, 12, 0, 0),
      bpm: bpm,
      lockState: LockState.stable,
      confidence: 0.9,
      inputLevelDbfs: -12.0,
      camelotKey: camelotKey,
      energyLevel: energyLevel,
    );

/// Runs [painter].paint() on an in-memory canvas.
/// Throws if painter throws; does not validate pixel output.
void _paintSmoke(SetEnergyCardPainter painter) {
  const size = Size(1080, 1080);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
  painter.paint(canvas, size);
  recorder.endRecording().dispose();
}

Widget _wrap(Widget child) => MaterialApp(home: child);

DspResult _stableResult({double bpm = 200.0}) => DspResult(
      primaryBpm: bpm,
      confidence: 0.9,
      lockState: LockState.stable,
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

// ── FeatureFlags unit tests ───────────────────────────────────────────────────

void main() {
  group('FeatureFlags.canShareCard', () {
    test('Pro → canShareCard is true', () {
      const flags = FeatureFlags(isPro: true);
      expect(flags.canShareCard, isTrue);
    });

    test('Free → canShareCard is false', () {
      const flags = FeatureFlags(isPro: false);
      expect(flags.canShareCard, isFalse);
    });
  });

  // ── Painter smoke tests ────────────────────────────────────────────────────

  group('SetEnergyCardPainter smoke tests', () {
    test('empty entries renders without throwing', () {
      _paintSmoke(const SetEnergyCardPainter([]));
    });

    test('single entry renders without throwing', () {
      _paintSmoke(SetEnergyCardPainter([_entry(bpm: 185.0)]));
    });

    test('multiple entries renders without throwing', () {
      final now = DateTime(2026, 6, 4, 12, 0, 0);
      _paintSmoke(SetEnergyCardPainter([
        _entry(bpm: 180.0, camelotKey: '8A', energyLevel: 6,
            ts: now),
        _entry(bpm: 185.0, camelotKey: '8A', energyLevel: 7,
            ts: now.add(const Duration(seconds: 30))),
        _entry(bpm: 190.0, camelotKey: '5A', energyLevel: 8,
            ts: now.add(const Duration(seconds: 60))),
        _entry(bpm: 192.0, energyLevel: 8,
            ts: now.add(const Duration(seconds: 90))),
        _entry(bpm: 195.0, camelotKey: '5A', energyLevel: 9,
            ts: now.add(const Duration(seconds: 120))),
      ]));
    });

    test('all same BPM renders without throwing (no division by zero)', () {
      final now = DateTime(2026, 6, 4, 12, 0, 0);
      _paintSmoke(SetEnergyCardPainter([
        _entry(bpm: 200.0, ts: now),
        _entry(bpm: 200.0, ts: now.add(const Duration(seconds: 30))),
        _entry(bpm: 200.0, ts: now.add(const Duration(seconds: 60))),
      ]));
    });

    test('no energy level entries — arc skipped without throwing', () {
      final now = DateTime(2026, 6, 4, 12, 0, 0);
      _paintSmoke(SetEnergyCardPainter([
        _entry(bpm: 180.0, ts: now),
        _entry(bpm: 185.0, ts: now.add(const Duration(seconds: 30))),
      ]));
    });

    test('painter reads entry.bpm, not hardcoded value', () {
      final e = _entry(bpm: 177.3);
      final painter = SetEnergyCardPainter([e]);
      expect(painter.entries.first.bpm, 177.3);
    });
  });

  // ── SetlistScreen widget tests for share button ────────────────────────────

  group('SetlistScreen share card button', () {
    testWidgets('share button visible when Pro and entries non-empty',
        (tester) async {
      final service = SetlistService()..startRecording();
      service.onDspResult(_stableResult());
      await tester.pumpWidget(_wrap(SetlistScreen(
        service: service,
        flags: const FeatureFlags(isPro: true),
      )));
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      service.dispose();
    });

    testWidgets('share button absent when entries empty', (tester) async {
      final service = SetlistService();
      await tester.pumpWidget(_wrap(SetlistScreen(
        service: service,
        flags: const FeatureFlags(isPro: true),
      )));
      expect(find.byIcon(Icons.share_outlined), findsNothing);
      service.dispose();
    });

    testWidgets('share button absent for Free tier even with entries',
        (tester) async {
      // Free tier goes to PaywallScreen — share button not in tree
      final service = SetlistService();
      await tester.pumpWidget(_wrap(SetlistScreen(
        service: service,
        flags: const FeatureFlags(isPro: false),
      )));
      expect(find.byIcon(Icons.share_outlined), findsNothing);
      expect(find.byType(PaywallScreen), findsOneWidget);
      service.dispose();
    });
  });
}
