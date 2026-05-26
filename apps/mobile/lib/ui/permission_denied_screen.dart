import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shown when microphone access is denied. The retry path differs by
/// state: a soft denial can re-prompt; a permanent denial sends the
/// user into system settings via `openAppSettings()`.
class PermissionDeniedScreen extends StatelessWidget {
  const PermissionDeniedScreen({
    super.key,
    required this.permanentlyDenied,
    required this.onRetry,
  });

  final bool permanentlyDenied;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Microphone access')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'We need the microphone to detect BPM',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Hitech BPM Radar listens to the music around you and runs '
                'the tempo detection on-device. Audio is never recorded, '
                'stored, or sent anywhere.',
              ),
              const SizedBox(height: 24),
              if (permanentlyDenied)
                Text(
                  'You previously denied microphone access permanently. '
                  'Open system settings and enable the microphone permission '
                  'for this app to continue.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else
                const Text(
                  'You can grant microphone access now. We will not start '
                  'listening until you do.',
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.mic),
                  label: Text(permanentlyDenied
                      ? 'Open system settings'
                      : 'Grant microphone access'),
                  onPressed: () async {
                    if (permanentlyDenied) {
                      await openAppSettings();
                    } else {
                      await onRetry();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
