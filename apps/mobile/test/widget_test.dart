// UI smoke tests (Phase 11 updated). The mic / FFI path is exercised by
// `dsp_engine_test.dart`; these tests pump synthetic `DspResult`
// snapshots into the screens to assert wiring (StreamBuilder, lock
// chip, candidate visibility) without needing a real mic or device.
//
// Phase 11 design changes reflected here:
//   • Russian badge labels replaced by IDLE / ACTIVE / UNSTABLE mode chips.
//     Only UNSTABLE still shows "нестабильно" pill inside _AnimatedBpmDisplay.
//   • InfoCard dropped УВЕРЕННОСТЬ and ×½/×2 cells (now 2×2 grid).
//   • Debug/signal-analyzer button icon changed to Icons.settings_outlined.
//   • Zone labels 'WAVEFORM' and 'LIVE SPECTRUM' added above viz panels.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitech_bpm_radar/capture/capture_bridge.dart';
import 'package:hitech_bpm_radar/dsp/dsp_result.dart';
import 'package:hitech_bpm_radar/ui/debug_screen.dart';
import 'package:hitech_bpm_radar/ui/main_screen.dart';
import 'package:hitech_bpm_radar/ui/permission_denied_screen.dart';

DspResult _stableSnapshot({double bpm = 200.0, double confidence = 0.87}) {
  return DspResult.fromJson({
    'primary_bpm': bpm,
    'confidence': confidence,
    'lock_state': 'STABLE',
    'signal_quality': {
      'input_level_dbfs': -14.2,
      'peak_dbfs': -2.1,
      'clipping': false,
      'clipped_frame_ratio': 0.0,
      'noise_level': 'low',
      'snr_estimate_db': null,
      'silence': false,
      'breakdown_likely': false,
    },
    'candidates': [
      {
        'bpm': bpm,
        'relation': 'main',
        'score': confidence,
        'raw_score': confidence,
        'stability_score': 0.9,
        'range_score': 1.0,
      },
      {
        'bpm': bpm / 2,
        'relation': 'half_time',
        'score': 0.45,
        'raw_score': 0.45,
        'stability_score': 0.5,
        'range_score': 0.3,
        'source_bpm': bpm / 2,
      },
    ],
    'timing': {
      'analysis_time_sec': 12.0,
      'window_time_sec': 6.0,
      'hop_time_sec': 0.0025,
      'first_lock_time_sec': 5.4,
    },
  });
}

DspResult _searchingSnapshot() => DspResult.fromJson({
      'primary_bpm': null,
      'confidence': 0.0,
      'lock_state': 'SEARCHING',
      'signal_quality': {
        'input_level_dbfs': null,
        'peak_dbfs': null,
        'clipping': false,
        'clipped_frame_ratio': 0.0,
        'noise_level': 'unknown',
        'snr_estimate_db': null,
        'silence': true,
        'breakdown_likely': false,
      },
      'candidates': <Map<String, dynamic>>[],
      'timing': {
        'analysis_time_sec': 0.0,
        'window_time_sec': 6.0,
        'hop_time_sec': 0.0025,
        'first_lock_time_sec': null,
      },
    });

DspResult _clippingSnapshot() => DspResult.fromJson({
      'primary_bpm': null,
      'confidence': 0.2,
      'lock_state': 'CLIPPED_MIC',
      'signal_quality': {
        'input_level_dbfs': -2.0,
        'peak_dbfs': 0.0,
        'clipping': true,
        'clipped_frame_ratio': 0.12,
        'noise_level': 'high',
        'snr_estimate_db': null,
        'silence': false,
        'breakdown_likely': false,
      },
      'candidates': <Map<String, dynamic>>[],
      'timing': {
        'analysis_time_sec': 3.0,
        'window_time_sec': 6.0,
        'hop_time_sec': 0.0025,
        'first_lock_time_sec': null,
      },
    });

/// Generic lock-state snapshot helper for badge smoke tests.
DspResult _lockSnapshot(String lockState) => DspResult.fromJson({
      'primary_bpm': null,
      'confidence': 0.0,
      'lock_state': lockState,
      'signal_quality': {
        'input_level_dbfs': null,
        'peak_dbfs': null,
        'clipping': false,
        'clipped_frame_ratio': 0.0,
        'noise_level': 'unknown',
        'snr_estimate_db': null,
        'silence': false,
        'breakdown_likely': false,
      },
      'candidates': <Map<String, dynamic>>[],
      'timing': {
        'analysis_time_sec': 0.0,
        'window_time_sec': 6.0,
        'hop_time_sec': 0.0025,
        'first_lock_time_sec': null,
      },
    });

/// Helper: wraps [MainScreen] without a rawPcm stream (simulates pre-mic state).
Widget _buildMainScreen(
  Stream<DspResult> results,
  Stream<CaptureError> errors, {
  bool isPro = true,
  VoidCallback? onHistoryTap,
  void Function(String)? onPaywallTap,
}) =>
    MaterialApp(
      home: MainScreen(
        results: results,
        errors: errors,
        rawPcm: null, // no mic in tests → spectrogram shows placeholder
        isPro: isPro,
        onHistoryTap: onHistoryTap,
        onPaywallTap: onPaywallTap,
        debugBuilder: (_) => const Scaffold(body: Text('stub-debug')),
      ),
    );

void main() {
  // ── MainScreen ─────────────────────────────────────────────────────────────

  testWidgets('MainScreen shows BPM placeholder before first snapshot',
      (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(_buildMainScreen(ctrl.stream, errs.stream));
    await tester.pump();

    // No result yet → BPM field shows em-dash placeholder.
    expect(find.text('—'), findsWidgets);
    // Both Spectrogram and LiveSpectrum panels show placeholder (no rawPcm).
    // Phase 7: two panels → findsWidgets (one or more) rather than findsOneWidget.
    expect(find.textContaining('Ожидание микрофона'), findsWidgets);
  });

  testWidgets(
      'MainScreen renders primary_bpm and ACTIVE chip from STABLE snapshot',
      (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(_buildMainScreen(ctrl.stream, errs.stream));
    await tester.pump();

    ctrl.add(_stableSnapshot());
    await tester.pump();
    await tester.pump();

    // BPM displayed.
    expect(find.text('200.0'), findsOneWidget);
    // Design v2: STABLE shows ACTIVE chip (not "стабильно" badge).
    expect(find.text('ACTIVE'), findsOneWidget);
    // Confidence bar shows percentage.
    expect(find.textContaining('87%'), findsAtLeast(1));
  });

  testWidgets(
      'MainScreen InfoCard renders all metric fields from STABLE snapshot',
      (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(_buildMainScreen(ctrl.stream, errs.stream));
    await tester.pump();

    ctrl.add(_stableSnapshot()); // bpm 200, conf 0.87, level -14.2, half_time 100
    await tester.pump();
    await tester.pump();

    // Zone labels (Phase 11 addition).
    expect(find.text('WAVEFORM'), findsOneWidget);
    expect(find.text('LIVE SPECTRUM'), findsOneWidget);

    // InfoCard stat grid labels (mixed-case, no toUpperCase() in _StatCell).
    expect(find.text('Уровень входа'), findsOneWidget);
    expect(find.text('Лучший кандидат'), findsOneWidget);
    expect(find.text('Клиппинг'), findsOneWidget);
    // ×½ / ×2 cell restored — shows half/double candidates (never hidden).
    expect(find.text('×½ / ×2'), findsOneWidget);
    // Уверенность cell still absent.
    expect(find.text('Уверенность'), findsNothing);

    // Values.
    expect(find.text('-14.2 dBFS'), findsOneWidget); // input level
    expect(find.text('200.0 BPM'), findsOneWidget); // best (main) candidate
    expect(find.text('100.0 / —'), findsOneWidget); // half=100, double=null
    expect(find.text('нет'), findsOneWidget); // clipping == false
  });

  testWidgets('MainScreen shows поиск badge for SEARCHING snapshot',
      (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(_buildMainScreen(ctrl.stream, errs.stream));
    await tester.pump();

    ctrl.add(_searchingSnapshot());
    await tester.pump();
    await tester.pump();

    // primary_bpm null → em-dash placeholder, never an invented number.
    expect(find.text('—'), findsWidgets,
        reason: 'SEARCHING must render placeholder, never an invented BPM');
    // Phase 11: mode chips. SEARCHING → IDLE chip active.
    expect(find.text('IDLE'), findsOneWidget);
  });

  testWidgets('MainScreen shows перегруз badge for CLIPPED_MIC',
      (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(_buildMainScreen(ctrl.stream, errs.stream));
    await tester.pump();

    ctrl.add(_clippingSnapshot());
    await tester.pump();
    await tester.pump();

    // Phase 11: no Russian badge; mode chip CLIPPED_MIC → IDLE active.
    expect(find.text('IDLE'), findsOneWidget);
    // Clipping value in InfoCard cell (lowercase with warning emoji).
    expect(find.text('⚠ перегруз'), findsOneWidget);
    // BPM must be null, not a fake number.
    expect(find.text('—'), findsWidgets,
        reason: 'CLIPPED_MIC with null primary_bpm must show placeholder');
  });

  // ── Phase 7: all 7 badge states smoke tests ────────────────────────────────
  // Each badge state gets its own test. Verifies correct label text is rendered
  // with the correct lock_state snapshot. (STABLE and SEARCHING already covered
  // above; CLIPPED_MIC covered above.)

  testWidgets('MainScreen shows нестабильно badge for UNSTABLE', (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async { await ctrl.close(); await errs.close(); });

    await tester.pumpWidget(_buildMainScreen(ctrl.stream, errs.stream));
    await tester.pump();
    ctrl.add(_lockSnapshot('UNSTABLE'));
    await tester.pump();
    await tester.pump();

    expect(find.text('нестабильно'), findsOneWidget);
  });

  testWidgets('MainScreen shows брейк badge for BREAKDOWN', (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async { await ctrl.close(); await errs.close(); });

    await tester.pumpWidget(_buildMainScreen(ctrl.stream, errs.stream));
    await tester.pump();
    ctrl.add(_lockSnapshot('BREAKDOWN'));
    await tester.pump();
    await tester.pump();

    // Phase 11: BREAKDOWN → IDLE chip active (no Russian badge).
    expect(find.text('IDLE'), findsOneWidget);
  });

  testWidgets('MainScreen shows только шум badge for NOISE_ONLY', (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async { await ctrl.close(); await errs.close(); });

    await tester.pumpWidget(_buildMainScreen(ctrl.stream, errs.stream));
    await tester.pump();
    ctrl.add(_lockSnapshot('NOISE_ONLY'));
    await tester.pump();
    await tester.pump();

    // Phase 11: NOISE_ONLY → IDLE chip active (no Russian badge).
    expect(find.text('IDLE'), findsOneWidget);
  });

  testWidgets('MainScreen shows захват badge for LOCKING', (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async { await ctrl.close(); await errs.close(); });

    await tester.pumpWidget(_buildMainScreen(ctrl.stream, errs.stream));
    await tester.pump();
    ctrl.add(_lockSnapshot('LOCKING'));
    await tester.pump();
    await tester.pump();

    // Phase 11: LOCKING → ACTIVE chip active (no Russian badge).
    expect(find.text('ACTIVE'), findsOneWidget);
  });

  testWidgets('MainScreen surfaces capture errors from the error stream',
      (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(_buildMainScreen(ctrl.stream, errs.stream));
    await tester.pump();

    errs.add(const CaptureError('не удалось открыть нативный DSP'));
    await tester.pump();
    await tester.pump();

    expect(
        find.textContaining('Ошибка захвата: не удалось открыть нативный DSP'),
        findsOneWidget);
  });

  testWidgets('Debug button navigates to debug screen', (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(_buildMainScreen(ctrl.stream, errs.stream));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('stub-debug'), findsOneWidget);
  });

  // ── DebugScreen ────────────────────────────────────────────────────────────

  testWidgets('DebugScreen keeps half-time candidates visible',
      (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    addTearDown(ctrl.close);

    await tester.pumpWidget(MaterialApp(
      home: DebugScreen(results: ctrl.stream),
    ));
    await tester.pump();

    ctrl.add(_stableSnapshot());
    await tester.pump();
    await tester.pump();

    expect(find.text('main'), findsOneWidget);
    expect(find.text('half_time'), findsOneWidget);
    expect(find.text('200.00'), findsOneWidget);
    expect(find.text('100.00'), findsOneWidget);
  });

  testWidgets('DebugScreen shows waiting state before first snapshot',
      (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    addTearDown(ctrl.close);

    await tester.pumpWidget(MaterialApp(
      home: DebugScreen(results: ctrl.stream),
    ));
    await tester.pump();

    expect(find.textContaining('Ожидание первого снапшота DspResult'),
        findsOneWidget);
  });

  // ── PermissionDeniedScreen ─────────────────────────────────────────────────

  testWidgets('PermissionDeniedScreen shows settings deep-link copy',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PermissionDeniedScreen(
        permanentlyDenied: true,
        onRetry: () async {},
      ),
    ));
    await tester.pump();

    expect(find.text('Открыть системные настройки'), findsOneWidget);
    expect(
        find.textContaining(
            'Ранее вы отказали в доступе к микрофону навсегда'),
        findsOneWidget);
  });

  testWidgets('PermissionDeniedScreen offers grant button on soft denial',
      (tester) async {
    var retryCalled = false;
    await tester.pumpWidget(MaterialApp(
      home: PermissionDeniedScreen(
        permanentlyDenied: false,
        onRetry: () async {
          retryCalled = true;
        },
      ),
    ));
    await tester.pump();

    expect(find.text('Выдать доступ к микрофону'), findsOneWidget);
    await tester.tap(find.text('Выдать доступ к микрофону'));
    await tester.pump();
    expect(retryCalled, isTrue);
  });

  // ── Freemium gating ─────────────────────────────────────────────────────────

  testWidgets('Free tier: debug button triggers onPaywallTap instead of debug',
      (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    String? paywallFeature;
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(_buildMainScreen(
      ctrl.stream,
      errs.stream,
      isPro: false,
      onPaywallTap: (f) => paywallFeature = f,
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();

    expect(paywallFeature, 'debug_screen');
  });

  testWidgets('Free tier: PRO badge visible in app bar', (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(_buildMainScreen(
      ctrl.stream,
      errs.stream,
      isPro: false,
    ));
    await tester.pump();

    expect(find.text('PRO'), findsOneWidget);
  });

  testWidgets('Pro tier: no PRO badge in app bar', (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(_buildMainScreen(
      ctrl.stream,
      errs.stream,
      isPro: true,
    ));
    await tester.pump();

    expect(find.text('PRO'), findsNothing);
  });
}
