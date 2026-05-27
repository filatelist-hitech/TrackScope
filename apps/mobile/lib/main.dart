// Точка входа приложения. Связывает gate разрешений, источник микрофона,
// FFI-мост захвата (который владеет изолятом DSP-воркера) и живой UI.
// Никаких вычислений BPM, никаких фейковых значений, никакого отката на
// синтетический звук при сбое захвата — UI показывает ошибку.

import 'package:flutter/material.dart';

import 'capture/capture_bridge.dart';
import 'capture/microphone_source.dart';
import 'permissions/permission_gate.dart';
import 'ui/debug_screen.dart';
import 'ui/main_screen.dart';
import 'ui/permission_denied_screen.dart';

void main() {
  runApp(const HitechBpmRadarApp());
}

class HitechBpmRadarApp extends StatelessWidget {
  const HitechBpmRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hitech BPM Radar',
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
class _LiveCaptureScaffold extends StatefulWidget {
  const _LiveCaptureScaffold();

  @override
  State<_LiveCaptureScaffold> createState() => _LiveCaptureScaffoldState();
}

class _LiveCaptureScaffoldState extends State<_LiveCaptureScaffold> {
  final CaptureBridge _bridge = CaptureBridge();
  final MicrophoneSource _mic = MicrophoneSource();
  Object? _startupError;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_startupError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hitech BPM Radar')),
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
    return MainScreen(
      results: _bridge.results,
      errors: _bridge.errors,
      rawPcm: _bridge.rawPcm,
      debugBuilder: (_) => DebugScreen(results: _bridge.results),
    );
  }
}
