// UI smoke tests. The mic / FFI path is exercised by
// `dsp_engine_test.dart`; these tests pump synthetic `DspResult`
// snapshots into the screens to assert wiring (StreamBuilder, lock
// badge, candidate visibility) without needing a real mic or device.

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

void main() {
  testWidgets('MainScreen renders primary_bpm and STABLE badge from stream',
      (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(MaterialApp(
      home: MainScreen(
        results: ctrl.stream,
        errors: errs.stream,
        debugBuilder: (_) => const Scaffold(body: Text('stub-debug')),
      ),
    ));
    await tester.pump();

    expect(find.text('— —'), findsOneWidget);

    ctrl.add(_stableSnapshot());
    await tester.pump();
    await tester.pump();

    expect(find.text('200.0'), findsOneWidget);
    expect(find.text('STABLE'), findsOneWidget);
    expect(find.text('Уверенность 87%'), findsOneWidget);
  });

  testWidgets('MainScreen surfaces capture errors from the error stream',
      (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(MaterialApp(
      home: MainScreen(
        results: ctrl.stream,
        errors: errs.stream,
        debugBuilder: (_) => const Scaffold(body: Text('stub-debug')),
      ),
    ));
    await tester.pump();

    errs.add(const CaptureError('не удалось открыть нативный DSP'));
    await tester.pump();
    await tester.pump();

    expect(
        find.textContaining('Ошибка захвата: не удалось открыть нативный DSP'),
        findsOneWidget);
  });

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

  testWidgets('SEARCHING snapshot keeps BPM placeholder (no fake value)',
      (tester) async {
    final ctrl = StreamController<DspResult>.broadcast();
    final errs = StreamController<CaptureError>.broadcast();
    addTearDown(() async {
      await ctrl.close();
      await errs.close();
    });

    await tester.pumpWidget(MaterialApp(
      home: MainScreen(
        results: ctrl.stream,
        errors: errs.stream,
        debugBuilder: (_) => const Scaffold(body: Text('stub-debug')),
      ),
    ));
    await tester.pump();

    ctrl.add(_searchingSnapshot());
    await tester.pump();
    await tester.pump();

    expect(find.text('— —'), findsOneWidget,
        reason: 'SEARCHING must render placeholder, never an invented BPM');
    expect(find.text('SEARCHING'), findsOneWidget);
  });

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
}
