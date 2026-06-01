// Сценарий выдачи разрешения на доступ к микрофону.
//
// На первой сборке: запрашиваем `Permission.microphone`. Пока запрос в
// процессе — показываем небольшой спиннер. При выдаче — рисуем builder
// живого экрана. При отказе (в том числе permanently denied) — рисуем
// экран-объяснение с прямой ссылкой в настройки. Приложение никогда
// молча не переключается на синтетический аудио-источник.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

enum _PermState { checking, granted, denied, permanentlyDenied }

class PermissionGate extends StatefulWidget {
  const PermissionGate({
    super.key,
    required this.onGranted,
    required this.onDenied,
  });

  /// Строит UI, который показывается после выдачи доступа к микрофону.
  /// Обычно это живой экран BPM.
  final WidgetBuilder onGranted;

  /// Строит UI, который показывается при отказе в доступе. Получает
  /// retry-callback, который экран может повесить на кнопку.
  final Widget Function(
      BuildContext context, bool permanentlyDenied, Future<void> Function() retry)
      onDenied;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  _PermState _state = _PermState.checking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _request();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Если пользователь вернулся из системных настроек после отказа —
    // перепроверяем статус.
    if (state == AppLifecycleState.resumed &&
        _state != _PermState.granted) {
      _request();
    }
  }

  Future<void> _request() async {
    if (mounted) setState(() => _state = _PermState.checking);
    final status = await Permission.microphone.request();
    if (!mounted) return;
    setState(() {
      if (status.isGranted) {
        _state = _PermState.granted;
      } else if (status.isPermanentlyDenied) {
        _state = _PermState.permanentlyDenied;
      } else {
        _state = _PermState.denied;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _PermState.checking:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case _PermState.granted:
        return widget.onGranted(context);
      case _PermState.denied:
      case _PermState.permanentlyDenied:
        return widget.onDenied(
            context, _state == _PermState.permanentlyDenied, _request);
    }
  }
}
