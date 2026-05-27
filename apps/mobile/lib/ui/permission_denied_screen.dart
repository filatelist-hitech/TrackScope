import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Показывается при отказе в доступе к микрофону. Путь повторной
/// попытки зависит от состояния: мягкий отказ можно перезапросить;
/// постоянный отказ ведёт пользователя в системные настройки через
/// `openAppSettings()`.
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
      appBar: AppBar(title: const Text('Доступ к микрофону')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Нужен микрофон для определения BPM',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Hitech BPM Radar слушает музыку вокруг и считает темп '
                'прямо на устройстве. Аудио никогда не записывается, '
                'не сохраняется и никуда не отправляется.',
              ),
              const SizedBox(height: 24),
              if (permanentlyDenied)
                Text(
                  'Ранее вы отказали в доступе к микрофону навсегда. '
                  'Откройте системные настройки и включите разрешение '
                  'микрофона для этого приложения, чтобы продолжить.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else
                const Text(
                  'Вы можете выдать доступ к микрофону сейчас. Мы не '
                  'начнём слушать, пока вы этого не сделаете.',
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.mic),
                  label: Text(permanentlyDenied
                      ? 'Открыть системные настройки'
                      : 'Выдать доступ к микрофону'),
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
