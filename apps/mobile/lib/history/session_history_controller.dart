// Session history controller.
//
// Управляет текущей сессией и списком прошлых сессий.
// Новая сессия создаётся на init; закрывается на dispose().
// Снимки добавляются не чаще 1 раза в 30 секунд при primaryBpm != null.
// Персистентность — SessionStore (SharedPreferences).
//
// ChangeNotifier для реактивности UI.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../dsp/dsp_result.dart';
import '../monetization/feature_flags.dart';
import 'bpm_history.dart';
import 'session.dart';
import 'session_store.dart';

const _kThrottleSeconds = 30;

class SessionHistoryController extends ChangeNotifier {
  SessionHistoryController({
    required FeatureFlags flags,
    required Stream<DspResult> resultsStream,
  }) : _flags = flags {
    _currentSession = _newSession();
    _subscription = resultsStream.listen(_onResult);
    _loadSessions();
  }

  final FeatureFlags _flags;

  late Session _currentSession;
  final List<Session> _pastSessions = [];
  StreamSubscription<DspResult>? _subscription;
  DateTime? _lastSnapshotTime;

  // ── Public API ──────────────────────────────────────────────────────────────

  Session get currentSession => _currentSession;

  /// Все сессии (текущая если есть данные + прошлые), свежие сверху.
  List<Session> get allSessions {
    final result = <Session>[];
    if (_currentSession.hasData) result.add(_currentSession);
    result.addAll(_pastSessions.reversed);
    return List.unmodifiable(result);
  }

  /// Плоский список BpmSample для совместимости с экспортом.
  List<BpmSample> get flatSamples {
    final all = <BpmSample>[];
    for (final s in allSessions) {
      for (final snap in s.snapshots) {
        all.add(BpmSample(
          bpm: snap.bpm,
          lockState: snap.lockState,
          timestamp: snap.timestamp,
          confidence: snap.confidence,
        ));
      }
    }
    return all;
  }

  bool get isEmpty => allSessions.isEmpty;

  // Legacy compat: used by HistoryScreen.isAtLimit banner
  bool get isAtLimit => false;

  // Legacy compat: used by bpm_history_test.dart
  BpmHistory get history => _BpmHistoryAdapter(this);

  void clear() {
    _currentSession = _newSession();
    _pastSessions.clear();
    _lastSnapshotTime = null;
    SessionStore.save([]);
    notifyListeners();
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  static Session _newSession() => Session(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        startTime: DateTime.now(),
      );

  void _onResult(DspResult result) {
    if (result.primaryBpm == null) return;

    final now = DateTime.now();
    if (_lastSnapshotTime != null &&
        now.difference(_lastSnapshotTime!).inSeconds < _kThrottleSeconds) {
      return;
    }

    _lastSnapshotTime = now;
    _currentSession.snapshots.add(SessionSnapshot(
      timestamp: now,
      bpm: result.primaryBpm!,
      confidence: result.confidence,
      lockState: result.lockState,
    ));
    _persistAsync();
    notifyListeners();
  }

  Future<void> _loadSessions() async {
    final sessions = await SessionStore.load();
    _pastSessions.addAll(sessions);
    notifyListeners();
  }

  void _persistAsync() {
    final toSave = List<Session>.from(_pastSessions);
    if (_currentSession.hasData) toSave.add(_currentSession);
    SessionStore.save(toSave);
  }

  void _closeCurrentSession() {
    _currentSession.endTime = DateTime.now();
    if (_currentSession.hasData) {
      _pastSessions.add(_currentSession);
    }
    SessionStore.save(List.from(_pastSessions));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _closeCurrentSession();
    super.dispose();
  }
}

/// Adapter для обратной совместимости с тестами и экспортом через BpmHistory.
class _BpmHistoryAdapter extends BpmHistory {
  _BpmHistoryAdapter(this._ctrl) : super(const FeatureFlags(isPro: true));

  final SessionHistoryController _ctrl;

  @override
  List<BpmSample> get samples => _ctrl.flatSamples;

  @override
  bool get isAtLimit => false;

  @override
  void add(BpmSample sample) {}

  @override
  void clear() => _ctrl.clear();
}
