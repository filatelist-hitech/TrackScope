// Web-only точка входа для UI-превью на localhost:7654.
//
// Использует `MockDspStream` вместо реального DSP-движка: Rust/FFI
// недоступны в браузере, поэтому live-детекция здесь невозможна. Это
// честный mockup — только UI, не детектор. Над экраном рисуется баннер
// «PREVIEW · MOCK DATA».
//
// Запуск: `./run_preview.sh` (flutter run -d web-server --target
// lib/main_web.dart). НЕ импортируется из `lib/main.dart` (мобильный
// продакшен-путь использует настоящий DspEngine через CaptureBridge).
//
// Превью отражает полную навигацию с AppNavigator (Radar / History / Settings).
// Freemium: constructs fixed FeatureFlags for preview; no
// `revenuecat_gateway.dart` import — keeps web tree clean.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'capture/capture_error.dart';
import 'dsp/dsp_result.dart';
import 'features/genre_preset/genre_preset.dart';
import 'features/setlist/setlist_service.dart';
import 'history/session_history_controller.dart';
import 'mock/mock_dsp_stream.dart';
import 'monetization/feature_flags.dart';
import 'monetization/pro_status_service.dart';
import 'monetization/purchases_gateway.dart';
import 'navigation/app_navigator.dart';
import 'settings/app_settings.dart';

/// Fake gateway для web-превью: всегда Pro, никаких сетевых вызовов.
class _PreviewProGateway implements PurchasesGateway {
  @override
  Future<void> configure({required String iosKey, required String androidKey}) async {}

  @override
  Future<bool> getIsPro() async => true;

  @override
  Future<PurchaseResult> purchaseLifetime() async => PurchaseResult.success;

  @override
  Future<PurchaseResult> purchaseAnnual() async => PurchaseResult.success;

  @override
  Future<PurchaseResult> restore() async => PurchaseResult.success;

  @override
  Stream<bool> get onProChanged => const Stream.empty();
}

void main() async {
  assert(kIsWeb, 'main_web.dart предназначен только для web-сборки превью');
  WidgetsFlutterBinding.ensureInitialized();

  // Минимальная инициализация для web-превью
  await AppSettings.instance.load();

  // Инициализируем ProStatusService с fake Pro-шлюзом для превью
  ProStatusService.instance.configureGateway(_PreviewProGateway());
  await ProStatusService.instance.initialize(iosKey: '', androidKey: '');

  // Начни с режима active для демонстрации
  MockDspStream.setMode(MockDspMode.active);
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();

  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  late Stream<DspResult> results;
  late Stream<Uint8List> rawPcm;

  @override
  void initState() {
    super.initState();
    results = MockDspStream.stable().asBroadcastStream();
    rawPcm = MockDspStream.rawPcm();
  }

  @override
  Widget build(BuildContext context) {
    const errors = Stream<CaptureError>.empty();

    return MaterialApp(
      title: 'Hitech BPM Radar — UI Preview',
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
      home: Banner(
        message: 'PREVIEW · MOCK DATA · localhost:7654',
        location: BannerLocation.topStart,
        color: const Color(0xFFB00020),
        child: _PreviewScaffold(
          results: results,
          errors: errors,
          rawPcm: rawPcm,
        ),
      ),
    );
  }
}

class _PreviewScaffold extends StatefulWidget {
  final Stream<DspResult> results;
  final Stream<CaptureError> errors;
  final Stream<Uint8List> rawPcm;

  const _PreviewScaffold({
    required this.results,
    required this.errors,
    required this.rawPcm,
  });

  @override
  State<_PreviewScaffold> createState() => _PreviewScaffoldState();
}

class _PreviewScaffoldState extends State<_PreviewScaffold> {
  late Stream<DspResult> _results;
  late Stream<Uint8List> _rawPcm;
  late SessionHistoryController _historyController;
  late SetlistService _setlistService;
  var _currentMode = MockDspMode.active;

  @override
  void initState() {
    super.initState();
    _results = widget.results;
    _rawPcm = widget.rawPcm;

    // Убедитесь, что ProStatusService инициализирован и имеет Pro-статус
    assert(
      ProStatusService.instance.initialized,
      'ProStatusService не инициализирован',
    );
    assert(
      ProStatusService.instance.isPro,
      'ProStatusService не в Pro-статусе',
    );

    // Инициализируем контроллеры для полной навигации
    final flags = FeatureFlags(
      isPro: ProStatusService.instance.isPro,
      selectedGenre: GenrePreset.hitechPsy,
    );
    _historyController = SessionHistoryController(
      flags: flags,
      resultsStream: _results,
    );
    _setlistService = SetlistService();
  }

  @override
  void dispose() {
    _historyController.dispose();
    _setlistService.dispose();
    super.dispose();
  }

  void _switchMode(MockDspMode mode) {
    setState(() {
      _currentMode = mode;
    });
    MockDspStream.setMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050807),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0c0f),
        elevation: 0,
        toolbarHeight: kToolbarHeight + 20,
        title: const Text(
          'BPM Radar Preview',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ModeButton(
                  label: 'IDLE',
                  isActive: _currentMode == MockDspMode.idle,
                  onTap: () => _switchMode(MockDspMode.idle),
                ),
                const SizedBox(width: 8),
                _ModeButton(
                  label: 'ACTIVE',
                  isActive: _currentMode == MockDspMode.active,
                  onTap: () => _switchMode(MockDspMode.active),
                ),
                const SizedBox(width: 8),
                _ModeButton(
                  label: 'UNSTABLE',
                  isActive: _currentMode == MockDspMode.unstable,
                  onTap: () => _switchMode(MockDspMode.unstable),
                ),
              ],
            ),
          ),
        ],
      ),
      body: AppNavigator(
        results: _results,
        errors: widget.errors,
        rawPcm: _rawPcm,
        flags: FeatureFlags(isPro: true, selectedGenre: GenrePreset.hitechPsy),
        historyController: _historyController,
        onBreak: () {
          // Mock break button — просто переключаемся в режим поиска
          _switchMode(MockDspMode.idle);
        },
        setlistService: _setlistService,
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF00DFB0) : const Color(0xFF1A2D24),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive ? const Color(0xFF00DFB0) : const Color(0xFF1A2D24),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isActive ? const Color(0xFF000000) : const Color(0xFF7AB8AA),
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

