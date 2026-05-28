// Display-layer EMA для большого BPM-числа на главном экране.
//
// Получает уже сглаженный `DspResult` из `BpmSmoother` и применяет
// финальный EMA-фильтр (α=0.2) только когда lock_state == STABLE.
//
// Три правила:
// 1. Не-STABLE или primary_bpm == null → возвращает null (dash в UI).
// 2. Первый STABLE-кадр → немедленный «снэп» к значению без задержки EMA.
// 3. Последующие STABLE-кадры → EMA: display = α*new + (1-α)*prev.
//    Устраняет остаточное визуальное дрожание после Rust-сглаживания.
//
// Этот класс не вычисляет BPM. Не модифицирует DspResult.
// primary_bpm в DspResult не изменяется — только display-значение.

import '../dsp/dsp_result.dart';

class BpmDisplay {
  static const double _alpha = 0.2;

  double? _displayBpm;
  bool _wasStable = false;

  double? get displayBpm => _displayBpm;

  /// Обновить внутреннее состояние по новому снапшоту и вернуть
  /// значение для отображения (или null, если показывать нечего).
  double? update(DspResult result) {
    final isStable = result.lockState == LockState.stable;
    final bpm = result.primaryBpm;

    if (!isStable || bpm == null) {
      reset();
      return null;
    }

    if (!_wasStable) {
      // Первый STABLE-кадр: снэп без EMA-задержки.
      _displayBpm = bpm;
      _wasStable = true;
    } else {
      _displayBpm = _alpha * bpm + (1.0 - _alpha) * _displayBpm!;
    }
    return _displayBpm;
  }

  /// Сбросить при выходе из STABLE или завершении сессии захвата.
  void reset() {
    _displayBpm = null;
    _wasStable = false;
  }
}
