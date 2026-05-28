// Display-layer EMA для большого BPM-числа на главном экране.
//
// Получает уже сглаженный `DspResult` из `BpmSmoother` и применяет
// финальный EMA-фильтр (α=0.2) только когда lock_state == STABLE.
//
// Три правила:
// 1. Не-STABLE/LOCKING или primary_bpm == null → возвращает null (dash в UI).
// 2. LOCKING (allowLocking=true) → возвращает raw primaryBpm без EMA.
// 3. Первый STABLE-кадр → немедленный «снэп» к значению без задержки EMA.
// 4. Последующие STABLE-кадры → EMA: display = α*new + (1-α)*prev.
//
// Флаг `isLockingDisplay` позволяет UI рендерить BPM с меньшей яркостью
// во время LOCKING, давая пользователю ориентир до стабилизации.
//
// Этот класс не вычисляет BPM. Не модифицирует DspResult.

import '../dsp/dsp_result.dart';

class BpmDisplay {
  static const double _alpha = 0.2;

  BpmDisplay({this.allowLocking = true});

  final bool allowLocking;
  double? _displayBpm;
  bool _wasStable = false;
  bool _isLockingDisplay = false;

  double? get displayBpm => _displayBpm;

  /// true когда текущее отображаемое значение — из LOCKING (без EMA).
  bool get isLockingDisplay => _isLockingDisplay;

  /// Обновить внутреннее состояние по новому снапшоту и вернуть
  /// значение для отображения (или null, если показывать нечего).
  double? update(DspResult result) {
    final isStable = result.lockState == LockState.stable;
    final isLocking = allowLocking && result.lockState == LockState.locking;
    final bpm = result.primaryBpm;

    if ((!isStable && !isLocking) || bpm == null) {
      reset();
      return null;
    }

    if (isLocking) {
      _isLockingDisplay = true;
      _wasStable = false; // обеспечить снэп при следующем входе в STABLE
      _displayBpm = bpm;
      return bpm;
    }

    // STABLE path
    _isLockingDisplay = false;
    if (!_wasStable) {
      _displayBpm = bpm;
      _wasStable = true;
    } else {
      _displayBpm = _alpha * bpm + (1.0 - _alpha) * _displayBpm!;
    }
    return _displayBpm;
  }

  /// Сбросить при выходе из STABLE/LOCKING или завершении сессии захвата.
  void reset() {
    _displayBpm = null;
    _wasStable = false;
    _isLockingDisplay = false;
  }
}
