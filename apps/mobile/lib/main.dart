// App entry point. Wires the permission gate, the microphone source,
// the capture bridge (which owns the DSP worker isolate), and the live
// UI together. No BPM math, no fake values, no fallback to synthetic
// audio if capture fails — the UI surfaces the error instead.

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff00a884)),
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

/// Owns the [CaptureBridge] and [MicrophoneSource] for the lifetime of
/// the live screen. Constructs them in `initState`, tears them down in
/// `dispose` — kept here (not in app state) so the bridge handle does
/// not survive a permission revoke.
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
              'Could not start microphone capture:\n\n$_startupError',
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
      debugBuilder: (_) => DebugScreen(results: _bridge.results),
    );
  }
}
