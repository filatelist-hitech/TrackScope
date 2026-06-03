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

import 'package:flutter/material.dart';

import 'capture/capture_bridge.dart';
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
    _startCapture();
  }

  Future<void> _startCapture() async {
    try {
      final pcm = await _mic.start();
      await _bridge.start(
        pcmStream: pcm,
        sampleRate: _mic.sampleRate,
        encoding: MicrophoneSource.encoding,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _startupError = e);
    }
  }

  @override
  void dispose() {
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
