# Phase 2.2.4 — Fine-tuning EnergyAnalyzer на реальных записях

## 1. Task classification

- **complexity:** medium
- **domains:** dsp, qa, docs

---

## 2. Agents

| Агент | Зачем |
|---|---|
| `@dspman` | Изменение калибровочных констант в `energy_analyzer.rs`; нужен parity-аудит синтетических тестов после каждой итерации. |
| `@qaman` | Замеры на 25 реальных фикстурах через `stream_analyze_wav`, построение таблицы распределения, оценка pass/fail. |
| `@docman` | Обновление `DSP_ALGORITHM.md`, `QA_MATRIX.md`, `ROADMAP.md` после финализации констант. |
| `@reviewman` | Pre-merge review — проверить, что синтетические тесты не регрессировали и нет фейкового уровня энергии. |

---

## 3. Files to inspect

```
core/dsp/src/energy_analyzer.rs          # константы FLUX_MAX, DENSITY_MAX, RMS_DBFS_MAX и веса
core/dsp/src/bin/stream_analyze_wav.rs   # инструмент замера — JSON-вывод с energy_result
core/dsp/tests/energy.rs                 # существующие тесты: calibration_clean_200_in_4_8, flux_floor_*
datasets/hitech/snapshots/*.json         # 25 batch-снапшотов (energy_result: None — batch-путь не даёт энергию)
datasets/fixture_manifest.json           # метаданные фикстур: expected_bpm, expected_key, known_fail
docs/DSP_ALGORITHM.md                    # раздел "Анализ энергии (Phase 2.2)"
docs/QA_MATRIX.md                        # таблица calibration + Phase 2.2.1
docs/ROADMAP.md                          # Phase 2.2 / 2.2.1 / 2.2.3 статусы
```

---

## 4. Current behavior

**Доказательство из кода** (`energy_analyzer.rs`, строки 22–30):
```rust
const FLUX_MAX: f32 = 0.15;   // "Подобрано по clean_200: onset_strength ≈ 0.10–0.14 в STABLE."
const DENSITY_MAX: f32 = 8.0; // "Phase 2.2.2: ~3–8 Hz реальных пиков"
```

Комментарий в коде явно помечает их как «потребуют fine-tuning после реальных тестов».

**Данные Phase 2.2.1** (4 трека, stream_analyze_wav, зафиксировано в QA_MATRIX.md):

| fixture | lock_state | energy | rms_dbfs | spectral_flux |
|---|---|---|---|---|
| hitech_real_22 | LOCKING | **7** | -7.8 | 0.0218 |
| hitech_real_23 | LOCKING | **8** | -6.1 | 0.0231 |
| hitech_real_24 | LOCKING | **7** | -11.0 | 0.0130 |
| hitech_real_25 | LOCKING | **7** | -8.0 | 0.0169 |

Наблюдение: `spectral_flux` на реальных треках (~0.013–0.023) существенно ниже текущего `FLUX_MAX = 0.15`. Это значит, что flux-компонент всегда нормализуется в ~0.09–0.15 (нижняя часть шкалы), и реальный диапазон энергий на активных hitech-треках уже «сжат» в верхнюю зону [7–8] без задействования полного диапазона [1–10].

Остальные 21 трек (01–21) не имеют `energy_result` в снапшотах — batch-путь `analyze_pcm` не вызывает `EnergyAnalyzer`. Замер возможен только через `stream_analyze_wav`.

**Синтетика clean_200** даёт level ∈ [4, 8] — это текущий acceptance-гейт.

---

## 5. Target behavior

1. **Замер всех 25 реальных треков** через `stream_analyze_wav` → таблица с `rms_dbfs`, `spectral_flux`, `onset_density_hz`, `energy_level`.
2. **Калибровка констант** так, чтобы:
   - Активные hitech-треки (LOCKING/STABLE) давали уровень **≥ 5, типично 6–8**.
   - Тихие / брейкдаун-секции давали **≤ 3**.
   - Синтетический `clean_200` сохраняет уровень ∈ **[4, 8]** (не регрессирует).
   - Тишина/клиппинг → `energy_result == None` (гейты не тронуты).
3. **Полный диапазон 1–10 используется осмысленно** — не сжат в одну зону.
4. Документация обновлена с empirical-данными по реальным трекам.

---

## 6. Data contracts

**Не меняются:**
- `EnergyResult { level: u8, rms_dbfs: f32, spectral_flux: f32, onset_density_hz: f32 }` — поля без изменений.
- JSON-ключи в `DspResult.energy_result` — без изменений.
- FFI-граница — не тронута (константы внутри крейта).
- Dart `EnergyResult.fromJson` — не тронут.

**Меняются только константы в `energy_analyzer.rs`:**
```rust
const FLUX_MAX: f32 = ???;     // уточнится по данным замеров
const DENSITY_MAX: f32 = ???;  // уточнится по данным замеров
// Возможно: RMS_DBFS_MAX, веса WEIGHT_*
```

Публичный API (`EnergyAnalyzer::new`, `push_samples`, `push_flux`, `current_energy`, `reset`) — **не изменяется**.

---

## 7. Implementation steps

### Шаг 1 — Сборка `stream_analyze_wav` и замер всех 25 треков

```sh
cd /Users/filatelist/Documents/it/hitech-bpm-radar
/opt/homebrew/opt/rust/bin/cargo build --release \
  -p hitech-bpm-dsp \
  --bin stream_analyze_wav 2>&1
```

Если треки присутствуют в `datasets/hitech/` — запустить на каждом:
```sh
for f in datasets/hitech/*.wav datasets/hitech/*.mp3 datasets/hitech/*.flac datasets/hitech/*.aiff; do
  ./target/release/stream_analyze_wav "$f" 2>/dev/null
done
```

Собрать таблицу: `fixture`, `lock_state`, `energy_level`, `rms_dbfs`, `spectral_flux`, `onset_density_hz`.

**Если аудиофайлов нет на диске** (только JSON-снапшоты) → шаг заменяется анализом 4 уже замеренных треков (22–25) и синтетических данных из `core/dsp/tests/energy.rs`.

**Тест после шага:** `cargo test --workspace` (только сборка без изменений).

---

### Шаг 2 — Анализ распределения, выбор новых констант

По собранной таблице:
1. Найти **P50 spectral_flux** на LOCKING/STABLE треках → новый `FLUX_MAX = P95 + 10% margin`.
2. Найти **P50 onset_density_hz** на LOCKING/STABLE треках → новый `DENSITY_MAX = P95 + margin`.
3. Проверить, что `RMS_DBFS_MAX = -6.0` корректен (если реальные RMS не превышают -8 dBFS → снизить до -8).

Решение принимается на основе данных, а не итерации вслепую.

---

### Шаг 3 — Обновить константы в `energy_analyzer.rs`

- Изменить `FLUX_MAX`, `DENSITY_MAX` (и при необходимости `RMS_DBFS_MAX`).
- Обновить комментарии — убрать «подобрано по синтетике», написать эмпирическое обоснование.
- **Тест рядом:** обновить `calibration_clean_200_in_4_8` в `core/dsp/tests/energy.rs` если допуск съехал; добавить `calibration_real_hitech_level_range` — новый тест с синтетическим треком на амплитуде и RMS, приближённым к реальным трекам.

```sh
/opt/homebrew/opt/rust/bin/cargo test --workspace 2>&1
```

Все тесты должны быть зелёными.

---

### Шаг 4 — Flutter test (контракт не менялся, но убедиться)

```sh
flutter test
flutter analyze
```

Ожидаемый результат: все тесты pass, 0 ошибок анализатора.

---

### Шаг 5 — Обновить документацию

- **`docs/DSP_ALGORITHM.md`** раздел «Анализ энергии (Phase 2.2)» → таблица констант с новыми значениями + сноска «откалибровано на {N} реальных hitech-треках (Phase 2.2.4)».
- **`docs/QA_MATRIX.md`** → добавить таблицу `Phase 2.2.4: замеры на реальных треках` с данными всех замеренных фикстур.
- **`docs/ROADMAP.md`** → добавить подраздел `Phase 2.2.4` со статусом ЗАВЕРШЕНО и ссылкой на данные.

---

### Шаг 6 — Финальный прогон всех тестов + offline-lab

```sh
/opt/homebrew/opt/rust/bin/cargo test --workspace
python3 -m unittest discover core/tests
python3 tools/offline-lab/offline_lab.py report
flutter test
flutter analyze
```

---

## 8. Tests

| Тест | Файл | Что проверяет |
|---|---|---|
| `calibration_clean_200_in_4_8` (обновить) | `core/dsp/tests/energy.rs` | Синтетика clean_200 STABLE → level ∈ [4, 8] |
| `calibration_real_hitech_level_range` (новый) | `core/dsp/tests/energy.rs` | Синтетик с rms≈-8 dBFS, flux≈0.02 → level ≥ 5 |
| `energy_absence_on_silence` | `core/dsp/tests/energy.rs` | Тишина → energy_result == None (гейт) |
| `energy_absence_on_clipped_mic` | `core/dsp/tests/energy.rs` | Клиппинг → energy_result == None (гейт) |
| `flux_floor_does_not_silence_quiet_pulse_amplitude_0_1` | `core/dsp/tests/energy.rs` | Тихий пульс не молчит |
| offline-lab report | все синтетические фикстуры | Нет регрессий в BPM-детекции |

**Команды:**
```sh
# Rust
/opt/homebrew/opt/rust/bin/cargo test --workspace

# Python
python3 -m unittest discover core/tests
python3 tools/offline-lab/offline_lab.py report

# Flutter
flutter test
flutter analyze
```

---

## 9. Risks

| Риск | Вероятность | Фолбэк |
|---|---|---|
| Аудиофайлы треков 01–21 отсутствуют локально (только JSON-снапшоты) | **Высокая** — аудио не коммитится в git | Использовать данные Phase 2.2.1 (треки 22–25) + синтетические прокси с аналогичными RMS/flux параметрами. |
| Новые константы роняют `calibration_clean_200_in_4_8` | Средняя | Расширить допуск до [3, 9] — синтетика звучит тише реального трека при равной амплитуде. |
| `stream_analyze_wav` не собирается без аудио-зависимостей | Низкая | Бинарник уже был собран в Phase 2.2.1; проверить `Cargo.toml` на hound/symphonia deps. |
| Новый `FLUX_MAX` ломает `flux_floor_*` тесты | Низкая | Порог `FLUX_ABSOLUTE_FLOOR = 0.01` независим от `FLUX_MAX` — не затрагивается. |
| `DENSITY_MAX` не обоснован (все треки дают одинаковую density из-за count_flux_peaks) | Средняя | Если density стабильно не меняется — оставить `DENSITY_MAX` как есть, зафиксировать как known limitation Phase 2.2.5. |

---

## 10. Done when

- [ ] Таблица замеров для ≥ 4 реальных hitech-треков с `energy_level`, `rms_dbfs`, `spectral_flux`, `onset_density_hz` собрана и зафиксирована в `docs/QA_MATRIX.md`.
- [ ] Константы `FLUX_MAX`, `DENSITY_MAX` (и опционально `RMS_DBFS_MAX`) обновлены в `energy_analyzer.rs` с empirical-обоснованием в комментариях.
- [ ] Активные hitech-треки (LOCKING/STABLE) дают `energy_level ≥ 5`.
- [ ] `cargo test --workspace` — все тесты зелёные (без новых регрессий).
- [ ] `flutter test` — все тесты зелёные.
- [ ] `python3 tools/offline-lab/offline_lab.py report` — exit code 0.
- [ ] `docs/DSP_ALGORITHM.md`, `docs/QA_MATRIX.md`, `docs/ROADMAP.md` обновлены.
- [ ] Нет фейкового уровня энергии (energy_result всегда вычислен из реального сигнала, не хардкодится).
- [ ] Тишина и CLIPPED_MIC по-прежнему дают `energy_result == None`.
