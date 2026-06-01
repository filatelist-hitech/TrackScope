import 'package:flutter/foundation.dart';

/// Tap-tempo BPM вычислитель.
///
/// Пользователь нажимает кнопку в такт музыке; контроллер вычисляет
/// BPM из средних интервалов между тапами. Не меняет DSP-логику —
/// только вспомогательный инструмент для ручной проверки / синхронизации.
/// Free tier.
class TapTempoController extends ChangeNotifier {
  final _taps = <DateTime>[];

  static const _maxTaps = 8;
  static const _maxIntervalMs = 3000;

  /// Текущий вычисленный BPM или `null`, если тапов меньше двух.
  double? get bpm {
    if (_taps.length < 2) return null;
    final intervals = List.generate(
      _taps.length - 1,
      (i) => _taps[i + 1].difference(_taps[i]).inMilliseconds,
    );
    final avg = intervals.reduce((a, b) => a + b) / intervals.length;
    return 60000 / avg;
  }

  /// Количество зарегистрированных тапов.
  int get tapCount => _taps.length;

  void tap() {
    final now = DateTime.now();
    if (_taps.isNotEmpty &&
        now.difference(_taps.last).inMilliseconds > _maxIntervalMs) {
      _taps.clear();
    }
    _taps.add(now);
    if (_taps.length > _maxTaps) _taps.removeAt(0);
    notifyListeners();
  }

  void reset() {
    _taps.clear();
    notifyListeners();
  }
}
