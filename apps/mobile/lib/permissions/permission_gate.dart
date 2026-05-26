// Permission flow for microphone access.
//
// On first build: request `Permission.microphone`. While the request is
// pending, render a small spinner. On grant, render the live screen
// builder. On denial (including permanently denied), render the
// explainer screen with a settings deep-link — the app never silently
// falls back to a synthetic audio source.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

enum _PermState { checking, granted, denied, permanentlyDenied }

class PermissionGate extends StatefulWidget {
  const PermissionGate({
    super.key,
    required this.onGranted,
    required this.onDenied,
  });

  /// Build the UI shown once microphone access is granted. Typically
  /// the live BPM screen.
  final WidgetBuilder onGranted;

  /// Build the UI shown when access is denied. Receives a retry
  /// callback the screen can wire to a button.
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
    // If the user came back from system settings after a deny, re-check.
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
