// Точка входа приложения. Связывает gate разрешений, источник микрофона,
// FFI-мост захвата (который владеет изолятом DSP-воркера) и живой UI.
// Никаких вычислений BPM, никаких фейковых значений, никакого отката на
// синтетический звук при сбое захвата — UI показывает ошибку.
//
// Freemium: ProStatusService инициализируется при старте. FeatureFlags
// вычисляются из Pro-статуса. CaptureBridge пересоздаётся при смене tier
// (новый minBpm), без перезапуска приложения.
//
// RevenueCat gateway инжектируется только здесь — единственный файл,
// импортирующий `revenuecat_gateway.dart` (и, через него, `purchases_flutter`).
//
// MyTracker analytics: инициализируется сразу после AppSettings. Ключ
// передаётся через --dart-define=MYTRACKER_ANDROID_KEY / MYTRACKER_IOS_KEY
// (не коммитится). При пустом ключе Analytics остаётся в stub-режиме.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'analytics/analytics.dart';
import 'analytics/mytracker_analytics.dart';
import 'capture/capture_bridge.dart';
import 'dsp/dsp_result.dart' as dsp;
import 'capture/microphone_source.dart';
import 'features/setlist/setlist_service.dart';
import 'history/session_history_controller.dart';
import 'monetization/feature_flags.dart';
import 'monetization/pro_status_service.dart';
import 'monetization/revenuecat_gateway.dart';
import 'navigation/app_navigator.dart';
import 'permissions/permission_gate.dart';
import 'settings/app_settings.dart';
import 'ui/permission_denied_screen.dart';

/// Local / QA-only tier override. Built with `--dart-define=FORCE_PRO=true`,
/// the app behaves as Pro (155–230 BPM, debug screen, 24 h history, export)
/// WITHOUT a real purchase. Defaults to `false`, so a normal App Store build —
/// which never passes this flag — stays Free. This flips only the entitlement
/// tier; it does NOT touch the DSP / BPM math (no fake BPM, no fake lock).
const bool _forceProTier = bool.fromEnvironment('FORCE_PRO', defaultValue: false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted settings (wakelock, etc.) before first frame.
  await AppSettings.instance.load();

  // Inject the real RevenueCat gateway before initializing.
  ProStatusService.instance.configureGateway(RevenueCatGateway());

  // Read RevenueCat keys from --dart-define / --dart-define-from-file.
  // If both are empty, the app stays fully Free / offline / keyless.
  const iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY', defaultValue: '');
  const androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY', defaultValue: '');

  await ProStatusService.instance.initialize(
    iosKey: iosKey,
    androidKey: androidKey,
  );

  // MyTracker analytics — ключ передаётся через --dart-define.
  // При пустом ключе или на вебе Analytics остаётся в stub-режиме (no-op).
  const myTrackerAndroidKey =
      String.fromEnvironment('MYTRACKER_ANDROID_KEY', defaultValue: '');
  const myTrackerIosKey =
      String.fromEnvironment('MYTRACKER_IOS_KEY', defaultValue: '');
  if (!kIsWeb) {
    final myTrackerKey =
        Platform.isIOS ? myTrackerIosKey : myTrackerAndroidKey;
    await Analytics.configure(MyTrackerAnalytics(), myTrackerKey);
  }

  runApp(const HitechBpmRadarApp());
}

class HitechBpmRadarApp extends StatelessWidget {
  const HitechBpmRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrackScope',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00BFA5),
          surface: Color(0xFF12121A),
        ),
        useMaterial3: true,
      ),
      home: PermissionGate(
        onGranted: (_) => const _LiveCaptureScaffold(),
        onDenied: (ctx, permanent, retry) => PermissionDeniedScreen(
          permanentlyDenied: permanent,
          onRetry: retry,
        ),
      ),
    );
  }
}

/// Владеет [CaptureBridge] и [MicrophoneSource] на время жизни живого
/// экрана. Создаёт их в `initState`, освобождает в `dispose` — держим
/// здесь (а не в состоянии приложения), чтобы handle моста не пережил
/// отзыв разрешения на микрофон.
///
/// Rebuilds the capture pipeline when the tier changes (new minBpm) via
/// ListenableBuilder on ProStatusService.instance. Startup/capture errors are
/// owned by [_CapturePipeline], so this wrapper is stateless.
class _LiveCaptureScaffold extends StatelessWidget {
  const _LiveCaptureScaffold();

  @override
  Widget build(BuildContext context) {
    // Rebuild when Pro status OR selected genre changes so that
    // CaptureBridge picks up the new minBpm/maxBpm.
    // _CapturePipeline uses ValueKey(minBpm-maxBpm) so its state is
    // only disposed/recreated when the BPM range actually changes —
    // not on every unrelated AppSettings notification.
    return ListenableBuilder(
      listenable: Listenable.merge([
        ProStatusService.instance,
        AppSettings.instance,
      ]),
      builder: (context, _) {
        final flags = FeatureFlags(
          isPro: _forceProTier || ProStatusService.instance.isPro,
          selectedGenre: AppSettings.instance.selectedGenre,
          customMin: AppSettings.instance.customMin,
          customMax: AppSettings.instance.customMax,
        );
        return _CapturePipeline(
          key: ValueKey('${flags.minBpm}-${flags.maxBpm}'),
          flags: flags,
        );
      },
    );
  }
}

/// The actual capture pipeline that owns CaptureBridge, MicrophoneSource,
/// and SessionHistoryController. Disposed and respawned on tier change.
class _CapturePipeline extends StatefulWidget {
  const _CapturePipeline({super.key, required this.flags});
  final FeatureFlags flags;

  @override
  State<_CapturePipeline> createState() => _CapturePipelineState();
}

class _CapturePipelineState extends State<_CapturePipeline> {
  late final CaptureBridge _bridge;
  late final MicrophoneSource _mic;
  late final SessionHistoryController _history;
  late final SetlistService _setlist;
  Object? _startupError;

  // --- Analytics state ---
  final Stopwatch _captureTimer = Stopwatch();
  // Дебаунс lock_state_change — не чаще 1 раза в 3 секунды.
  DateTime _lastStateEventTime = DateTime.fromMillisecondsSinceEpoch(0);
  dsp.LockState _prevLockState = dsp.LockState.searching;
  bool _firstStableTracked = false;
  bool _clippingReported = false;
  bool _breakdownReported = false;
  bool _reachedStable = false;
  // Последний STABLE-кадр — используется для session_summary.
  dsp.DspResult? _stableResult;

  @override
  void initState() {
    super.initState();
    _bridge = CaptureBridge(
      minBpm: widget.flags.minBpm,
      maxBpm: widget.flags.maxBpm,
    );
    _mic = MicrophoneSource();
    _history = SessionHistoryController(
      flags: widget.flags,
      resultsStream: _bridge.results,
    );
    _setlist = SetlistService();
    _bridge.results.listen(_setlist.onDspResult);
    _bridge.results.listen(_onDspResult);
    _startCapture();
  }

  /// Слушатель DSP-результатов для аналитики.
  /// Не вычисляет BPM — только пробрасывает данные из готового [DspResult].
  void _onDspResult(dsp.DspResult result) {
    final elapsed = _captureTimer.elapsed.inSeconds;
    final analytics = Analytics.instance;
    final flags = widget.flags;

    // lock_state_change (throttled ≥3 сек)
    if (result.lockState != _prevLockState) {
      final now = DateTime.now();
      if (now.difference(_lastStateEventTime).inSeconds >= 3) {
        analytics.trackEvent('lock_state_change', {
          'from': _prevLockState.wireName,
          'to': result.lockState.wireName,
          'confidence': result.confidence.toStringAsFixed(2),
          'elapsed_sec': '$elapsed',
          'genre': flags.selectedGenre.name,
        });
        _lastStateEventTime = now;
      }
      _prevLockState = result.lockState;
    }

    // bpm_first_stable — единожды за сессию
    if (result.lockState == dsp.LockState.stable) {
      _reachedStable = true;
      _stableResult = result;
      if (!_firstStableTracked && result.primaryBpm != null) {
        _firstStableTracked = true;
        analytics.trackEvent('bpm_first_stable', {
          'bpm': result.primaryBpm!.toStringAsFixed(1),
          'confidence': result.confidence.toStringAsFixed(2),
          'first_lock_sec':
              result.timing.firstLockTimeSec?.toStringAsFixed(1) ?? '',
          'analysis_sec': result.timing.analysisTimeSec.toStringAsFixed(1),
          'input_dbfs':
              result.signalQuality.inputLevelDbfs?.toStringAsFixed(1) ?? '',
          'snr_db':
              result.signalQuality.snrEstimateDb?.toStringAsFixed(1) ?? '',
          'noise_level': result.signalQuality.noiseLevel,
          'onset_rate_hz': result.debug.onsetRateHz.toStringAsFixed(2),
          'onset_strength': result.debug.onsetStrength.toStringAsFixed(3),
          'peak_prominence':
              result.debug.tempoPeakProminence.toStringAsFixed(2),
          'harmonic_ambiguity':
              result.debug.harmonicAmbiguity.toStringAsFixed(2),
          'stability_score': result.debug.stabilityScore.toStringAsFixed(2),
          'key_camelot': result.keyResult?.camelot ?? '',
          'key_confidence':
              result.keyResult?.confidence.toStringAsFixed(2) ?? '',
          'energy_level': result.energyResult?.level.toString() ?? '',
          'top_candidate_relation': result.candidates.isNotEmpty
              ? result.candidates.first.relation
              : '',
          'top_candidate_score': result.candidates.isNotEmpty
              ? result.candidates.first.score.toStringAsFixed(2)
              : '',
          'genre': flags.selectedGenre.name,
          'is_pro': flags.isPro ? '1' : '0',
          'platform': kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
        });
      }
    }

    // signal_quality_warning — по одному разу за тип за сессию
    if (result.signalQuality.clipping && !_clippingReported) {
      _clippingReported = true;
      analytics.trackEvent('signal_quality_warning', {
        'type': 'clipping',
        'clipped_frame_ratio':
            result.signalQuality.clippedFrameRatio.toStringAsFixed(2),
        'input_dbfs':
            result.signalQuality.inputLevelDbfs?.toStringAsFixed(1) ?? '',
        'elapsed_sec': '$elapsed',
      });
    }
    if (result.signalQuality.breakdownLikely && !_breakdownReported) {
      _breakdownReported = true;
      analytics.trackEvent('signal_quality_warning', {
        'type': 'breakdown',
        'elapsed_sec': '$elapsed',
        'confidence': result.confidence.toStringAsFixed(2),
      });
    }
  }

  Future<void> _startCapture() async {
    try {
      final pcm = await _mic.start();
      await _bridge.start(
        pcmStream: pcm,
        sampleRate: _mic.sampleRate,
        encoding: MicrophoneSource.encoding,
      );
      _captureTimer.start();
      final flags = widget.flags;
      Analytics.instance.trackEvent('capture_start', {
        'genre': flags.selectedGenre.name,
        'bpm_min': '${flags.minBpm.round()}',
        'bpm_max': '${flags.maxBpm.round()}',
        'is_pro': flags.isPro ? '1' : '0',
        'platform': kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _startupError = e);
    }
  }

  void _trackCaptureStop() {
    final elapsed = _captureTimer.elapsed.inSeconds;
    final analytics = Analytics.instance;
    final flags = widget.flags;

    analytics.trackEvent('capture_stop', {
      'duration_sec': '$elapsed',
      'reached_stable': _reachedStable ? '1' : '0',
      'final_lock_state': _prevLockState.wireName,
      'genre': flags.selectedGenre.name,
      'is_pro': flags.isPro ? '1' : '0',
    });

    // session_summary при наличии STABLE-кадра
    final r = _stableResult;
    if (_reachedStable && r != null && r.primaryBpm != null) {
      analytics.trackEvent('session_summary', {
        'bpm': r.primaryBpm!.toStringAsFixed(1),
        'confidence': r.confidence.toStringAsFixed(2),
        'key_camelot': r.keyResult?.camelot ?? '',
        'energy_level': r.energyResult?.level.toString() ?? '',
        'duration_sec': '$elapsed',
        'noise_level': r.signalQuality.noiseLevel,
        'snr_db': r.signalQuality.snrEstimateDb?.toStringAsFixed(1) ?? '',
        'onset_rate_hz': r.debug.onsetRateHz.toStringAsFixed(2),
        'harmonic_ambiguity': r.debug.harmonicAmbiguity.toStringAsFixed(2),
        'warnings': r.debug.warnings.join(','),
        'genre': flags.selectedGenre.name,
        'is_pro': flags.isPro ? '1' : '0',
        'platform': kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
      });
    }

    analytics.flush();
  }

  @override
  void dispose() {
    _trackCaptureStop();
    _captureTimer.stop();
    _bridge.dispose();
    _mic.dispose();
    _history.dispose();
    _setlist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_startupError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('TrackScope')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Не удалось запустить захват с микрофона:\n\n$_startupError',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      );
    }
    return AppNavigator(
      results: _bridge.results,
      errors: _bridge.errors,
      rawPcm: _bridge.rawPcm,
      flags: widget.flags,
      historyController: _history,
      onBreak: _bridge.resetEngine,
      setlistService: _setlist,
    );
  }
}
