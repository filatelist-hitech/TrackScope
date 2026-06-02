import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../dsp/dsp_result.dart';
import 'setlist_entry.dart';

/// Сервис записи сетлиста: накапливает STABLE BPM-снапшоты во время сета.
///
/// Дедупликация: новая запись создаётся только если BPM изменился на > 0.5
/// или прошло > 5 секунд с момента последней записи. Это предотвращает
/// flood одинаковых строк при стабильном темпе.
///
/// Pro-only: проверка происходит на уровне UI (`FeatureFlags.canAccessSetlist`).
/// Сервис сам по себе не проверяет tier.
class SetlistService extends ChangeNotifier {
  final _entries = <SetlistEntry>[];
  bool _isRecording = false;

  static const _deduplicateBpmDelta = 0.5;
  static const _deduplicateSeconds = 5;

  bool get isRecording => _isRecording;

  List<SetlistEntry> get entries => List.unmodifiable(_entries);

  int get entryCount => _entries.length;

  Duration get duration {
    if (_entries.length < 2) return Duration.zero;
    return _entries.last.timestamp.difference(_entries.first.timestamp);
  }

  double? get averageBpm {
    if (_entries.isEmpty) return null;
    return _entries.map((e) => e.bpm).reduce((a, b) => a + b) /
        _entries.length;
  }

  void startRecording() {
    _entries.clear();
    _isRecording = true;
    notifyListeners();
  }

  void stopRecording() {
    _isRecording = false;
    notifyListeners();
  }

  /// Вызывается per `DspResult` (например из CaptureBridge stream).
  /// Пишет только STABLE с ненулевым BPM; дедуплицирует.
  void onDspResult(DspResult result) {
    if (!_isRecording) return;
    if (result.lockState != LockState.stable) return;
    if (result.primaryBpm == null) return;

    final bpm = result.primaryBpm!;
    final now = DateTime.now();

    if (_entries.isNotEmpty) {
      final lastEntry = _entries.last;
      final bpmDelta = (bpm - lastEntry.bpm).abs();
      final secsSinceLast =
          now.difference(lastEntry.timestamp).inSeconds;
      if (bpmDelta < _deduplicateBpmDelta &&
          secsSinceLast < _deduplicateSeconds) {
        return;
      }
    }

    _entries.add(SetlistEntry(
      timestamp: now,
      bpm: bpm,
      lockState: result.lockState,
      confidence: result.confidence,
      inputLevelDbfs: result.signalQuality.inputLevelDbfs ?? 0.0,
    ));
    notifyListeners();
  }

  /// Экспорт всех записей в JSON-строку.
  String exportJson() {
    final list = _entries.map((e) => e.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert({
      'exported_at': DateTime.now().toIso8601String(),
      'entry_count': _entries.length,
      'duration_seconds': duration.inSeconds,
      'entries': list,
    });
  }

  /// Экспорт всех записей в CSV-строку.
  String exportCsv() {
    final buf = StringBuffer()..writeln(setlistCsvHeader);
    for (final e in _entries) {
      buf.writeln(e.toCsvRow());
    }
    return buf.toString();
  }

  void clear() {
    _entries.clear();
    _isRecording = false;
    notifyListeners();
  }
}
