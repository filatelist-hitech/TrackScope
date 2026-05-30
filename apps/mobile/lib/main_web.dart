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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'capture/capture_error.dart';
import 'dsp/dsp_result.dart';
import 'mock/mock_dsp_stream.dart';
import 'ui/debug_screen.dart';
import 'ui/main_screen.dart';

void main() {
  assert(kIsWeb, 'main_web.dart предназначен только для web-сборки превью');
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();

  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  // Один broadcast-поток, чтобы и MainScreen, и DebugScreen могли слушать.
  late final Stream<DspResult> _results =
      MockDspStream.stable().asBroadcastStream();
  final Stream<CaptureError> _errors = const Stream<CaptureError>.empty();

  @override
  Widget build(BuildContext context) {
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
      // Баннер делает очевидным, что числа — симуляция, а не реальный захват.
      home: Banner(
        message: 'PREVIEW · MOCK',
        location: BannerLocation.topStart,
        color: const Color(0xFFB00020),
        child: MainScreen(
          results: _results,
          errors: _errors,
          rawPcm: MockDspStream.rawPcm(),
          debugBuilder: (_) => DebugScreen(results: _results),
        ),
      ),
    );
  }
}
