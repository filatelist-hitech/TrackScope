// Сглаживающий слой поверх сырых `DspResult`-снапшотов из Rust DSP.
//
// Находится в Dart-изоляте главного потока (главный изолят), а не в
// DSP-воркере: это намеренно. Rust-ядро должно эмитить сырую уверенность
// без UI-сглаживания, чтобы сохранялась parity-тестируемость. Слой Dart
// отвечает только за стабилизацию показаний на экране.
//
// Три механизма, реализованных здесь:
//
// 1. **Медианный фильтр BPM** — скользящее окно из последних
//    [_bpmWindowSize] ненулевых значений `primary_bpm`. Медиана вместо
//    среднего: устойчива к выбросам и не «тянет» показание к краям.
//    Задержка ≈ [_bpmWindowSize] × интервал_опроса (по умолчанию 250 мс
//    при 50 мс опроса) — значительно меньше окна анализа (12 с).
//
// 2. **Экспоненциальное сглаживание уверенности** (EMA, α = 0.2) —
//    медленно следует за уверенностью, подавляя мелкое дрожание
//    показания процента захвата. Реальное падение (например, брейкдаун)
//    не скрывается: α достаточно мало, чтобы EMA упала за несколько кадров.
//
// 3. **Гистерезис выхода из STABLE** — после входа в STABLE движок
//    удерживает состояние ещё [_stableHysteresisFrames] кадров при
//    мимолётных LOCKING/UNSTABLE/SEARCHING флуктуациях. Это предотвращает
//    мигание значка «захвачено» при кратких провалах уверенности. Однако
//    критические состояния (CLIPPED_MIC, BREAKDOWN, NOISE_ONLY) немедленно
//    сбрасывают гистерезис — честность важнее стабильности отображения.
//
// ВАЖНО: этот класс никогда не вычисляет BPM. Он только фильтрует
// значения, которые уже вычислило Rust-ядро. Если `primary_bpm` из DSP
// равен null, окно очищается и медиана возвращает null.

import 'dart:collection';

import '../dsp/dsp_result.dart';

/// Сглаживает серию `DspResult`-снапшотов для стабильного UI-отображения.
///
/// Не изменяет `candidates` — они всегда передаются как есть, чтобы
/// debug-экран видел полный сырой список из Rust.
class BpmSmoother {
  BpmSmoother({
    int bpmWindowSize = 5,
    double confidenceAlpha = 0.2,
    int stableHysteresisFrames = 3,
  })  : _bpmWindowSize = bpmWindowSize,
        _confidenceAlpha = confidenceAlpha,
        _stableHysteresisFrames = stableHysteresisFrames;

  int _bpmWindowSize;
  final double _confidenceAlpha;
  final int _stableHysteresisFrames;

  /// Update the median-window size at runtime (e.g. when AppSettings change).
  /// If [value] is smaller than the current buffer, excess oldest entries are
  /// removed immediately so the next smooth() uses the new size.
  set windowSize(int value) {
    assert(value >= 1);
    _bpmWindowSize = value;
    while (_bpmWindow.length > _bpmWindowSize) {
      _bpmWindow.removeFirst();
    }
  }

  int get windowSize => _bpmWindowSize;

  final Queue<double> _bpmWindow = Queue();
  double? _smoothedConf;
  bool _wasStable = false;
  int _nonStableCount = 0;

  /// Применяет сглаживание к [raw] и возвращает новый снапшот.
  ///
  /// `candidates`, `signalQuality` и `timing` передаются без изменений.
  DspResult smooth(DspResult raw) {
    // ── 1. Медианный фильтр BPM ─────────────────────────────────────────
    if (raw.primaryBpm != null) {
      _bpmWindow.addLast(raw.primaryBpm!);
      while (_bpmWindow.length > _bpmWindowSize) {
        _bpmWindow.removeFirst();
      }
    } else {
      // DSP вернул null → сигнал ненадёжен, сбрасываем окно.
      _bpmWindow.clear();
    }

    double? smoothedBpm;
    if (_bpmWindow.isNotEmpty) {
      final sorted = _bpmWindow.toList()..sort();
      smoothedBpm = sorted[sorted.length ~/ 2];
    }

    // ── 2. EMA уверенности ───────────────────────────────────────────────
    final rawConf = raw.confidence.clamp(0.0, 1.0);
    if (_smoothedConf == null) {
      _smoothedConf = rawConf;
    } else {
      _smoothedConf =
          _confidenceAlpha * rawConf + (1.0 - _confidenceAlpha) * _smoothedConf!;
    }
    final smoothedConf = _smoothedConf!.clamp(0.0, 1.0);

    // ── 3. Гистерезис выхода из STABLE ──────────────────────────────────
    final lockState = _applyHysteresis(raw.lockState);

    // Если гистерезис удержал STABLE, но DSP-BPM был null (ещё не захвачен
    // до сглаживания), используем последнее медианное значение из окна.
    // Если окно пусто — null, честно.
    final double? finalBpm = switch (lockState) {
      LockState.stable || LockState.locking => smoothedBpm ?? raw.primaryBpm,
      _ => null,
    };

    return DspResult(
      primaryBpm: finalBpm,
      confidence: smoothedConf,
      lockState: lockState,
      signalQuality: raw.signalQuality, // передаём as-is для debug-экрана
      candidates: raw.candidates, // raw-кандидаты никогда не скрываем
      timing: raw.timing,
      debug: raw.debug, // debug-метрики пробрасываем без изменений
    );
  }

  /// Сбросить внутреннее состояние (вызывать при reset сессии захвата).
  void reset() {
    _bpmWindow.clear();
    _smoothedConf = null;
    _wasStable = false;
    _nonStableCount = 0;
  }

  LockState _applyHysteresis(LockState rawState) {
    // Критические состояния: немедленно сбрасываем гистерезис.
    // Мы не имеем права удерживать STABLE при клиппинге, брейкдауне
    // или noise-only — это было бы ложью.
    if (rawState == LockState.clippedMic ||
        rawState == LockState.breakdown ||
        rawState == LockState.noiseOnly) {
      _wasStable = false;
      _nonStableCount = 0;
      return rawState;
    }

    if (_wasStable && rawState != LockState.stable) {
      _nonStableCount++;
      if (_nonStableCount < _stableHysteresisFrames) {
        // Удерживаем STABLE ещё один кадр — кратковременная флуктуация.
        return LockState.stable;
      }
      // Превышен порог — официально покидаем STABLE.
      _wasStable = false;
      _nonStableCount = 0;
    } else if (rawState == LockState.stable) {
      _wasStable = true;
      _nonStableCount = 0;
    }

    return rawState;
  }
}
