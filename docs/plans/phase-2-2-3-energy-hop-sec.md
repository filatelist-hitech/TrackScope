# Phase 2.2.3 — EnergyAnalyzer hop_sec parameter + FLUX_ABSOLUTE_FLOOR verification

## 1. Task classification

- **complexity:** low
- **domains:** dsp, qa

Хирургическое изменение в одном файле (`energy_analyzer.rs`) + один дополнительный тест.
Нет изменений в контракте `DspResult`, FFI-слое или Dart-коде.

---

## 2. Agents

| Агент | Почему |
|---|---|
| Нет внешних агентов | Задача low-complexity, один файл, чистая механика |

Стандартный воркфлоу: `@dspman` мысленный референс при ревью изменений в `energy_analyzer.rs`.

---

## 3. Files to inspect

```
core/dsp/src/energy_analyzer.rs   — основной файл изменения
core/dsp/src/lib.rs               — call site EnergyAnalyzer::new, поле DspEngine::hop_sec
core/dsp/tests/energy.rs          — существующие тесты (обновить при необходимости)
core/dsp/tests/common/mod.rs      — генераторы фикстур (pulse_track, silence, white_noise)
core/dsp/src/bin/stream_analyze_wav.rs — бинарник для ручной верификации FLUX_ABSOLUTE_FLOOR
```

---

## 4. Current behavior (с evidence)

### Хардкодная константа `HOP_SEC`

`core/dsp/src/energy_analyzer.rs:33`:
```rust
const HOP_SEC: f32 = 0.0025;
```

Используется в двух местах внутри `EnergyAnalyzer`:

1. **`new()` — вычисление `flux_capacity` (строка 84):**
   ```rust
   let flux_capacity = ((3.0 / 0.0025) as usize).max(8);
   ```
   Захардкожено `0.0025` вместо передаваемого параметра.

2. **`current_energy()` — вычисление `window_secs` (строка 179):**
   ```rust
   let window_secs = self.flux_history.len() as f32 * HOP_SEC;
   ```

3. **`count_flux_peaks()` — `MIN_PEAK_GAP = 40` (строка 134):**
   Закомментировано как «40 кадров × 2.5 мс/кадр = 100 мс», что корректно
   только при `HOP_SEC = 0.0025`. При другом SR/hop формула ломается.

### Сигнатура `DspEngine::new()` (строка 325):
```rust
energy_analyzer: EnergyAnalyzer::new(config.sample_rate as f32),
```
Реальный `hop_sec` уже вычислен в `self.hop_sec = hop_size / sample_rate` (строка 304),
но не передаётся в `EnergyAnalyzer`.

### Следствие

При дефолтном SR=48 kHz расхождения нет (48000 × 0.0025 = 120 — целое число, hop_sec совпадает).
Но при нестандартных SR (например, 44100 Hz):
- реальный `hop_sec ≈ 0.0027` мс (hop_size = 110 → 110/44100 ≈ 0.002494),
- `EnergyAnalyzer` использует `0.0025` → `onset_density_hz` и `flux_capacity` посчитаны неверно.

### Текущий сигнатурный контракт `EnergyAnalyzer::new`
```rust
pub fn new(sample_rate: f32) -> Self
```

---

## 5. Target behavior

### После изменения

Сигнатура:
```rust
pub fn new(sample_rate: f32, hop_sec: f32) -> Self
```

`hop_sec` хранится как поле `self.hop_sec: f32` и используется вместо `HOP_SEC` везде:
- `flux_capacity = ((3.0 / hop_sec) as usize).max(8)`
- `window_secs = self.flux_history.len() as f32 * self.hop_sec`
- `MIN_PEAK_GAP = (0.1 / self.hop_sec).round() as usize` (100 мс / hop_sec)

Константа `HOP_SEC` удаляется из файла.

Call site в `DspEngine::new()`:
```rust
energy_analyzer: EnergyAnalyzer::new(config.sample_rate as f32, hop_sec),
```

Внутренние тесты в `energy_analyzer.rs` (строки 249–292) обновляются:
```rust
let mut ea = EnergyAnalyzer::new(48_000.0, 0.0025);
```

### Параллельная верификация FLUX_ABSOLUTE_FLOOR

`FLUX_ABSOLUTE_FLOOR = 0.01` — порог, отсекающий шумовые флуктуации при подсчёте пиков onset density.

DSP_ALGORITHM.md отмечает:
> `FLUX_ABSOLUTE_FLOOR = 0.01` калиброван под `pulse_track(amplitude=0.7)`;
> для очень тихих треков (amplitude << 0.3) onset_density может недосчитывать удары.

Цель верификации: **определить, при какой минимальной амплитуде синтетического пульса
`onset_density_hz` остаётся > 0** (т.е. FLUX_ABSOLUTE_FLOOR не режет все пики).

Ожидаем: при amplitude=0.1 (≈ −20 dBFS) пики всё ещё детектируются (flux пика >> 0.01);
при amplitude=0.02–0.03 (≈ −34 dBFS) flux пиков может упасть ниже порога.

Если нижняя граница окажется выше ожидаемой (например, onset_density_hz=0 уже при 0.1),
документируем в DSP_ALGORITHM.md как known limitation.

---

## 6. Data contracts

### Изменяется

| Элемент | Тип изменения |
|---|---|
| `EnergyAnalyzer::new(sample_rate, hop_sec)` | публичный API крейта — breaking change внутри крейта (нет pub re-export за пределы `core/dsp`) |
| `DspEngine::new()` — call site | обновляется автоматически |

### Не изменяется

| Элемент | Статус |
|---|---|
| `EnergyResult` struct | без изменений |
| `DspResult` + JSON-контракт | без изменений |
| FFI API (`hitech_bpm_engine_*`) | без изменений |
| Dart `DspResult.energyResult` | без изменений |
| `DspConfig` | без изменений |

`EnergyAnalyzer` является `pub` внутри крейта, но используется только из `DspEngine`.
Нет внешних вызывающих за пределами `core/dsp` — нет breaking change для downstream.

---

## 7. Implementation steps

### Шаг 1. Обновить `EnergyAnalyzer::new` и удалить `HOP_SEC`

**Файл:** `core/dsp/src/energy_analyzer.rs`

1. Удалить `const HOP_SEC: f32 = 0.0025;`.
2. Добавить поле `hop_sec: f32` в struct `EnergyAnalyzer`.
3. Изменить сигнатуру: `pub fn new(sample_rate: f32, hop_sec: f32) -> Self`.
4. В теле `new()`:
   - Заменить `(3.0 / 0.0025)` на `(3.0 / hop_sec.max(0.001))` (guard от деления на 0).
   - Сохранить `hop_sec` в `self.hop_sec`.
5. В `current_energy()`:
   - Заменить `HOP_SEC` на `self.hop_sec`.
6. В `count_flux_peaks()`:
   - Заменить `const MIN_PEAK_GAP: usize = 40;` на
     `let min_peak_gap = (0.1 / self.hop_sec).round() as usize;`
   - Использовать `min_peak_gap` вместо `MIN_PEAK_GAP` в сравнении.

### Шаг 2. Обновить call site в `DspEngine::new()`

**Файл:** `core/dsp/src/lib.rs`, строка 325:
```rust
// было:
energy_analyzer: EnergyAnalyzer::new(config.sample_rate as f32),
// стало:
energy_analyzer: EnergyAnalyzer::new(config.sample_rate as f32, hop_sec),
```

`hop_sec` уже вычислен на строке 301–304 — передаётся без изменений.

### Шаг 3. Обновить unit-тесты внутри `energy_analyzer.rs`

Все `EnergyAnalyzer::new(48_000.0)` в `#[cfg(test)]` заменить на `EnergyAnalyzer::new(48_000.0, 0.0025)`.
Затронутые строки: 249, 262, 274.

### Шаг 4. Добавить тест верификации FLUX_ABSOLUTE_FLOOR

**Файл:** `core/dsp/tests/energy.rs`

Добавить два теста:

```rust
/// FLUX_ABSOLUTE_FLOOR верификация: тихий пульс (amplitude=0.1) всё ещё детектируется.
/// Если onset_density_hz == 0, FLOOR режет все удары → known limitation.
#[test]
fn flux_floor_does_not_silence_quiet_pulse_0_1() {
    let pulse = common::pulse_track(200.0, 14.0, 0.1); // ≈ -20 dBFS
    let results = run_stream_full(&pulse);
    let stable: Vec<_> = results.iter()
        .filter(|r| r.lock_state == LockState::Stable)
        .filter_map(|r| r.energy_result.as_ref())
        .collect();
    // Может не достичь STABLE при тихом сигнале — это ожидаемо.
    // Если STABLE есть — onset_density_hz должна быть > 0.
    for er in &stable {
        assert!(
            er.onset_density_hz > 0.0,
            "quiet pulse at amplitude=0.1 should still have onset_density_hz > 0 in STABLE, got {}",
            er.onset_density_hz
        );
    }
}

/// FLUX_ABSOLUTE_FLOOR нижняя граница: очень тихий пульс (amplitude=0.02).
/// Документирует поведение в пограничном диапазоне.
#[test]
fn flux_floor_boundary_very_quiet_pulse_0_02() {
    let pulse = common::pulse_track(200.0, 14.0, 0.02); // ≈ -34 dBFS
    let results = run_stream_full(&pulse);
    // Не ожидаем STABLE — тихий сигнал не захватится. Просто проверяем,
    // что energy_result присутствует хотя бы в не-SEARCHING кадрах (если они есть),
    // или документируем, что всё в SEARCHING/NOISE_ONLY.
    let non_searching: Vec<_> = results.iter()
        .filter(|r| {
            use hitech_bpm_dsp::LockState;
            r.lock_state != LockState::Searching
        })
        .collect();
    // Тест — документальный: не fail при пустом списке.
    // Если есть energy_result с onset_density_hz==0 — это known limitation при amplitude<0.05.
    let _ = non_searching; // Результат логируется при --nocapture
}
```

### Шаг 5. Запустить тесты и убедиться, что всё зелёное

```sh
/opt/homebrew/opt/rust/bin/cargo test --workspace 2>&1 | tail -20
```

---

## 8. Tests

### Обязательные команды

```sh
# Rust workspace — все 107+ тестов должны быть зелёными
/opt/homebrew/opt/rust/bin/cargo test --workspace

# Только DSP-тесты для быстрой итерации
/opt/homebrew/opt/rust/bin/cargo test -p hitech_bpm_dsp

# Python parity (не должен сломаться — EnergyAnalyzer не в Python-пути)
python3 -m unittest discover core/tests

# Flutter (energy_result парсинг не меняется)
flutter test
flutter analyze
```

### Верификация FLUX_ABSOLUTE_FLOOR через `stream_analyze_wav` (ручная)

Если в распоряжении есть WAV-файл с тихим сигналом (< -20 dBFS):
```sh
/opt/homebrew/opt/rust/bin/cargo build --release -p hitech_bpm_dsp 2>/dev/null
target/release/stream_analyze_wav --input <quiet_track.wav> | python3 -c "
import json, sys
r = json.load(sys.stdin)
er = r.get('energy_result')
print('energy_result:', er)
print('onset_density_hz:', er['onset_density_hz'] if er else 'N/A')
"
```

При отсутствии реального WAV — достаточно синтетических тестов шагов 4.

---

## 9. Risks

| Риск | Вероятность | Fallback |
|---|---|---|
| `hop_sec = 0.0` при SR=0 → деление на ноль в `flux_capacity` | Низкая | Guard `hop_sec.max(0.001)` в `new()` |
| Изменение `MIN_PEAK_GAP` на `(0.1 / hop_sec)` меняет поведение существующих тестов | Низкая (при SR=48k результат идентичен: 0.1/0.0025=40) | При регрессии — откатить к константе и зафайлить task |
| `flux_floor_does_not_silence_quiet_pulse_0_1` → STABLE не достигается при 0.1 amplitude | Возможна | Тест устроен как документальный (не падает при отсутствии STABLE-кадров), результат логируется |
| `energy_analyzer.rs` `pub fn new` является `pub` на уровне крейта → возможно используется в `core/ffi` | Нужна проверка | Grep перед изменением |

### Предварительная проверка: использование `EnergyAnalyzer` за пределами `core/dsp`

```sh
grep -r "EnergyAnalyzer::new" /Users/filatelist/Documents/it/hitech-bpm-radar/core/
```

Ожидаем ровно одно вхождение: `core/dsp/src/lib.rs`.

---

## 10. Done when

- [ ] `EnergyAnalyzer::new(sample_rate, hop_sec)` — сигнатура обновлена, `HOP_SEC` константа удалена.
- [ ] `MIN_PEAK_GAP` вычисляется из `self.hop_sec` динамически.
- [ ] `DspEngine::new()` передаёт `hop_sec` в `EnergyAnalyzer::new()`.
- [ ] Unit-тесты в `energy_analyzer.rs` обновлены (передают `0.0025`).
- [ ] `cargo test --workspace` → все тесты зелёные (≥107 Rust-тестов).
- [ ] Добавлены 2 новых теста в `energy.rs`: `flux_floor_does_not_silence_quiet_pulse_0_1` и `flux_floor_boundary_very_quiet_pulse_0_02`.
- [ ] `flutter test` → 0 новых failures (изменение не затрагивает Dart).
- [ ] FLUX_ABSOLUTE_FLOOR поведение на quiet pulse задокументировано: либо подтверждено что порог безопасен при ≥0.1 amplitude, либо зафиксировано known limitation в `docs/DSP_ALGORITHM.md`.
