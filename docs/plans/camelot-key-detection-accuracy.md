# Plan: Camelot Key Detection Accuracy

**Задача:** устранить систематическую ошибку KeyAnalyzer, из-за которой детектор
возвращает только 4A (F minor) или 4B (Ab major) вне зависимости от входного сигнала.

---

## 1. Task classification

- **Complexity:** high
- **Domains:** dsp, qa, docs

---

## 2. Agents

| Агент | Почему |
|---|---|
| `@dspman` | Основные изменения в `core/dsp/src/key_analyzer.rs` — HPCP-алгоритм |
| `@qaman` | Расширение тест-матрицы: синтетические аккорды в 5+ разных тональностях |
| `@reviewman` | Pre-merge review anti-fake инвариантов и корректности алгоритма |
| `@docman` | Обновление DSP_ALGORITHM.md, QA_MATRIX.md, ROADMAP.md |

---

## 3. Files to inspect

```
core/dsp/src/key_analyzer.rs          ← основной алгоритм HPCP + K-S
core/dsp/tests/key_detection.rs       ← существующие тесты (все проходят)
core/dsp/src/lib.rs                   ← гейт key_result (строки 619–628)
docs/DSP_ALGORITHM.md                 ← раздел «Детекция тональности»
docs/QA_MATRIX.md                     ← матрица тестов key
docs/ROADMAP.md                       ← Phase 2.1 и Phase 13.1
.claude/docs/project-map.md           ← обновлять после каждого шага
```

---

## 4. Current behavior (с evidence)

**Симптом:** KeyAnalyzer почти всегда возвращает `4A` (F minor) или `4B` (Ab major),
независимо от реального ключа трека.

**Диагностика root cause (проведена перед написанием плана):**

### Root Cause 1 — 1/f normalization создаёт систематический Ab-bias

В `extract_hpcp_frame` (строка 326):
```rust
let power = buf[k].norm_sqr() / freq;  // 1/f-нормализация
```

Для равномерного спектра при FREQ_MIN=100 Hz накопленный вес по pitch class:
```
Ab (8): 10.0%  ← +1.70% от идеальных 8.33%
Db (1): 10.5%  ← +2.17% от идеальных 8.33%
D  (2):  7.1%  ← -1.23% ниже нормы
E  (4):  6.9%  ← -1.43% ниже нормы
```

Первый анализируемый бин (k=9, freq≈105.5 Hz) отображается на **pitch class 8 (Ab)**
и имеет максимальный вес 1/f = 0.00948. Второй бин (k=10, freq≈117.2 Hz) → Bb.

Ab, Bb, Db — три из четырёх наиболее переоценённых классов —
принадлежат обоим ключам F minor и Ab major (они относительные тональности).

### Root Cause 2 — MINOR_PROFILE[3] = 5.38 усиливает F minor bias

K-S minor profile: вес minor 3rd = 5.38 (наивысший вне тоники).
Для F minor (root=5): minor 3rd = (3+5)%12 = 8 = **Ab**.
Если HPCP[8] систематически завышен (RC1), F minor получает двойное усиление.

### Root Cause 3 — Hard round() vs Gaussian

`pitch_class = (semitones.round() as i32).rem_euclid(12)`
— дискретное отображение, не учитывает, что реальные FFT-бины могут быть «между»
соседними полутонами. При 100–200 Hz ширина бина ≈ ширине полутона → 50% ошибок.

**Evidence от диагностики:**
```
Original (1/f, FREQ_MIN=100):   Ab bias = +1.70%, max deviation = 2.2%
Proposed (Gaussian+count-norm, FREQ_MIN=200): Ab bias = -0.22%, max deviation = 0.7%
```

---

## 5. Target behavior

- KeyAnalyzer возвращает разные Camelot-позиции в зависимости от реальной тональности
- На синтетических аккордах: точность ≥ правильный pitch class ±1 semitone
- На равномерном шуме: HPCP отклонение от идеальных 8.33% ≤ ±2% (vs текущие ±2.2%)
- Существующие тесты (11 unit + 7 integration) остаются зелёными
- 4A и 4B могут появляться только когда сигнал действительно в F minor / Ab major

---

## 6. Data contracts

**Контракт `KeyResult` — НЕ меняется:**
```rust
pub struct KeyResult {
    pub key: Option<MusicalKey>,
    pub mode: Option<KeyMode>,
    pub camelot: Option<CamelotKey>,
    pub confidence: f32,
}
```

**Контракт `DspResult.key_result: Option<KeyResult>` — НЕ меняется.**

**Публичный API `KeyAnalyzer::new`, `push_samples`, `current_key`, `reset` — НЕ меняется.**

Изменяется только внутренняя функция `extract_hpcp_frame` — приватная, не входит в ABI.

**Константы (внутренние, меняются):**
- `FREQ_MIN: f32` → `100.0` → **`200.0`**
- Новые: `SIGMA_CENTS: f32 = 14.0` (Gaussian width)
- Опционально: `TEMPERLEY_MAJOR`, `TEMPERLEY_MINOR` (альтернативные профили)

---

## 7. Implementation steps

Каждый шаг заканчивается `cargo test --workspace` + `flutter test`.

### Step 1 — Диагностический тест: HPCP flatness assertion ✓

Добавить тест `hpcp_is_approximately_flat_for_uniform_spectrum` в
`core/dsp/tests/key_detection.rs`:

```rust
// Белый шум → KeyAnalyzer direct → avg_hpcp должен отклоняться от 8.33% не более чем на 2%
// Этот тест ПАДАЕТ на текущем коде (Ab bias +1.70% > 2.0% порог... или близко к нему)
// После фикса — ПРОХОДИТ.
```

Цель: закрепить диагностику как регрессионный тест ПЕРЕД изменением алгоритма.

**Команды после шага:**
```sh
/opt/homebrew/opt/rust/bin/cargo test --workspace
flutter test
# Обновить .claude/docs/project-map.md
# Обновить docs/DSP_ALGORITHM.md (добавить замечание о диагнозе)
```

### Step 2 — Ядро: заменить 1/f на Gaussian + count-normalization

Файл: `core/dsp/src/key_analyzer.rs`

**Добавить константы:**
```rust
/// Ширина Гауссовой функции для Gaussian pitch class weighting (центы).
/// Стандартное значение HPCP (Gómez 2006): σ = 14 центов.
const SIGMA_CENTS: f32 = 14.0;
```

**Заменить FREQ_MIN:**
```rust
const FREQ_MIN: f32 = 200.0; // было 100.0
```

**Заменить тело цикла в `extract_hpcp_frame`:**

*Было:*
```rust
let semitones = 12.0 * (freq / C4_HZ).log2();
let pitch_class = (semitones.round() as i32).rem_euclid(12) as usize;
let power = buf[k].norm_sqr() / freq;  // 1/f
hpcp[pitch_class] += power;
```

*Стало:*
```rust
let semitones = 12.0 * (freq / C4_HZ).log2();
let nearest = semitones.round() as i32;
let cents_off = (semitones - nearest as f32) * 100.0;
let power = buf[k].norm_sqr();  // без 1/f

// Gaussian-вес на ближайший полутон
let w = (-cents_off * cents_off / (2.0 * SIGMA_CENTS * SIGMA_CENTS)).exp();
let pc = nearest.rem_euclid(12) as usize;
hpcp[pc] += power * w;
hpcp_count[pc] += w;

// Gaussian-хвост на соседний полутон
let adj = if cents_off > 0.0 { nearest + 1 } else { nearest - 1 };
let cents_adj = (semitones - adj as f32) * 100.0;
let w_adj = (-cents_adj * cents_adj / (2.0 * SIGMA_CENTS * SIGMA_CENTS)).exp();
let pc_adj = adj.rem_euclid(12) as usize;
hpcp[pc_adj] += power * w_adj;
hpcp_count[pc_adj] += w_adj;
```

**Добавить count-normalization после цикла (перед L2):**
```rust
// Count-normalization: компенсирует неравное покрытие pitch classes
// в линейном FFT (высокие октавы имеют больше бинов на полутон).
for i in 0..HPCP_BINS {
    if hpcp_count[i] > 1e-9 {
        hpcp[i] /= hpcp_count[i];
    }
}
```

**Добавить локальную переменную `hpcp_count` в `extract_hpcp_frame`:**
```rust
let mut hpcp = [0.0f32; HPCP_BINS];
let mut hpcp_count = [0.0f32; HPCP_BINS];  // NEW
```

**Команды после шага:**
```sh
/opt/homebrew/opt/rust/bin/cargo test --workspace 2>&1 | tail -20
flutter test
# Обновить .claude/docs/project-map.md
# Обновить docs/DSP_ALGORITHM.md (замены констант и логики)
# Обновить docs/ROADMAP.md (фикс внутри Phase 13.1 / добавить Phase 13.2)
```

### Step 3 — Новые интеграционные тесты: ≥5 различных тональностей

Добавить в `core/dsp/tests/key_detection.rs`:

```
d_major_chord_detects_d_major_10b  — D4+F#4+A4 → Camelot 10B
g_minor_chord_detects_g_minor_6a   — G4+Bb4+D5 → Camelot 6A
e_minor_chord_detects_e_minor_9a   — E4+G4+B4  → Camelot 9A
bb_major_chord_detects_bb_major_6b — Bb4+D5+F5 → Camelot 6B
no_4a_4b_bias_on_broad_spectrum    — white noise → key != Some(F) И != Some(Ab), или None
hpcp_flat_for_uniform_noise        — avg_hpcp bias < ±2% от 8.33%
```

**Команды после шага:**
```sh
/opt/homebrew/opt/rust/bin/cargo test --workspace 2>&1 | tail -20
flutter test
# Обновить .claude/docs/project-map.md
# Обновить docs/QA_MATRIX.md (новые строки key_detection)
```

### Step 4 (опционально) — Добавить Temperley (2001) профили

Файл: `core/dsp/src/key_analyzer.rs`

Temperley major: `[5.0, 2.0, 3.5, 2.0, 4.5, 4.0, 2.0, 4.5, 2.0, 3.5, 1.5, 4.0]`
Temperley minor: `[5.0, 2.0, 3.5, 4.5, 2.0, 4.0, 2.0, 4.5, 3.5, 2.0, 1.5, 4.0]`

Логика: выбрать профиль с максимальной корреляцией среди K-S AND Temperley (48 итераций).

**Когда нужно:** если после Step 2–3 ключ по-прежнему смещён в конкретные позиции —
Temperley minor снижает вес minor 3rd (4.5 vs K-S 5.38), что ещё больше уменьшает F minor bias.

**Команды после шага:**
```sh
/opt/homebrew/opt/rust/bin/cargo test --workspace
flutter test
# Обновить .claude/docs/project-map.md
# Обновить docs/DSP_ALGORITHM.md (описание Temperley)
```

### Step 5 — Регрессия: offline_lab + полный тест-прогон

```sh
python3 tools/offline-lab/offline_lab.py report
/opt/homebrew/opt/rust/bin/cargo test --workspace
flutter test
flutter analyze
```

Все 15/15 синтетических фикстур должны оставаться PASS.
Key detection тесты: ≥ 11 + 6 новых = ≥ 17 тестов PASS.

**Команды после шага:**
```sh
# После валидации — обновить все документы:
# docs/DSP_ALGORITHM.md — раздел HPCP, константы, Gaussian формула
# docs/QA_MATRIX.md — строки key-detection + Phase 13.2 секция
# docs/ROADMAP.md — Phase 13.2: KeyAnalyzer accuracy fix
# .claude/docs/project-map.md
```

---

## 8. Tests

### Существующие (должны оставаться зелёными)

| Тест | Файл |
|---|---|
| `a440_sine_maps_to_pitch_class_a` | `key_detection.rs` |
| `c4_sine_maps_to_pitch_class_c` | `key_detection.rs` |
| `a_minor_chord_detects_a_minor_camelot_8a` | `key_detection.rs` |
| `silence_no_key` | `key_detection.rs` |
| `clipped_mic_suppresses_key_result` | `key_detection.rs` |
| `white_noise_low_confidence_or_no_key` | `key_detection.rs` |
| `reset_clears_key_state` | `key_detection.rs` |
| `camelot_all_24_entries_are_unique` | `key_detection.rs` |
| 11 unit-тестов в `key_analyzer.rs` | inline |
| 218 Flutter тестов | `flutter test` |
| 15/15 offline_lab report | `offline_lab.py report` |

### Новые (добавляются в Step 1 и Step 3)

| Тест | Ожидание | Шаг |
|---|---|---|
| `hpcp_is_approximately_flat_for_uniform_spectrum` | max HPCP deviation < 2% от 8.33% | Step 1 |
| `d_major_chord_detects_d_major_10b` | D major = Camelot 10B | Step 3 |
| `g_minor_chord_detects_g_minor_6a` | G minor = Camelot 6A | Step 3 |
| `e_minor_chord_detects_e_minor_9a` | E minor = Camelot 9A | Step 3 |
| `bb_major_chord_detects_bb_major_6b` | Bb major = Camelot 6B | Step 3 |
| `no_4a_4b_bias_on_broad_spectrum` | white noise → NOT 4A/4B систематически | Step 3 |

### Команды для запуска

```sh
# Rust (включает key_detection.rs)
/opt/homebrew/opt/rust/bin/cargo test --workspace

# Конкретно key-тесты:
/opt/homebrew/opt/rust/bin/cargo test -p hitech-bpm-dsp --test key_detection

# Flutter
flutter test
flutter analyze

# QA-отчёт
python3 tools/offline-lab/offline_lab.py report
```

---

## 9. Risks

| Риск | Вероятность | Митигация |
|---|---|---|
| **FREQ_MIN=200 Hz отрезает G3 (196 Hz)** — тест G minor chord нужно использовать G4 (392 Hz) | Низкая | Все тестовые аккорды строить выше 200 Hz; в документации отметить как ограничение |
| **Gaussian без 1/f даёт треблу больше веса** — высокочастотный шум/синт искажает HPCP | Средняя | count-normalization уравнивает вклад октав; если нужно — добавить soft-clip по FREQ_MAX |
| **Temperley minor 3rd=4.5 < K-S 5.38** — может снизить accuracy A minor (8A) | Низкая | Запускать оба профиля, брать лучшую корреляцию |
| **Существующий тест `c4_sine_maps_to_pitch_class_c`** — C4=261.63 Hz > 200 Hz, ок | Нет | Нет риска |
| **Regression в BPM-тестах** — key_analyzer изменён, но BPM-путь независим | Нет | `cargo test --workspace` покрывает оба пути |
| **Фреймворк для тестирования chord detection нестабилен** — chord_sine с тихим уровнем → NOISE_ONLY | Средняя | Использовать `analyze_key_direct()` (минуя lock_state гейт) для unit-тестов; `push_and_analyze` для интеграционных |

**Fallback:** если Gaussian+count-norm недостаточен, следующий шаг — CQT (Constant-Q Transform), который нативно работает в логарифмическом частотном пространстве. CQT — стандарт для real-time key detection (Essentia, Madmom). Реализация потребует замены всего FFT-блока.

---

## 10. Done when

- [ ] `cargo test --workspace` зелёный: все существующие тесты проходят + ≥ 6 новых
- [ ] `flutter test` зелёный: 218+ тестов
- [ ] `offline_lab.py report` exit 0: 15/15 PASS (BPM-регрессии не сломаны)
- [ ] `flutter analyze` 0 errors
- [ ] KeyAnalyzer возвращает ≥ 5 различных Camelot-значений на синтетическом тест-сьюте
- [ ] `hpcp_is_approximately_flat_for_uniform_spectrum` проходит: deviation < 2%
- [ ] `no_4a_4b_bias_on_broad_spectrum` проходит: white noise не даёт систематически 4A/4B
- [ ] D major → 10B, G minor → 6A, E minor → 9A, Bb major → 6B (новые тесты PASS)
- [ ] docs/DSP_ALGORITHM.md обновлён: новые константы, Gaussian-формула
- [ ] docs/QA_MATRIX.md обновлён: key detection строки
- [ ] docs/ROADMAP.md обновлён: Phase 13.2 (или фикс в 13.1 секции)
- [ ] .claude/docs/project-map.md обновлён

---

## Приложение: Диагностические данные

### Bias по pitch class (равномерный спектр):

| Подход | Ab bias | Max deviation |
|---|---|---|
| ORIGINAL: 1/f + hard-round + FREQ_MIN=100 | +1.70% | 2.2% |
| PROPOSED: Gaussian + count-norm + FREQ_MIN=200 | -0.22% | 0.7% |

### 4 наиболее переоценённых pitch class при 1/f (FREQ_MIN=100):

```
Db: +2.17%  ← 10.5% вместо 8.33%  
Ab: +1.70%  ← 10.0% вместо 8.33%  ← первый бин (k=9, 105.5 Hz) = Ab
Bb: +0.97%  ← 9.3%  вместо 8.33%  ← второй бин (k=10, 117.2 Hz) = Bb
Eb: +0.77%  ← 9.1%  вместо 8.33%
```

Ab major и F minor содержат {Ab, Bb, Eb, Db} — 4 переоценённых класса из 7 → систематическая победа 4A/4B.

### Математическое обоснование Gaussian HPCP:

Для FFT-бина на частоте f:
```
semitones_float = 12.0 × log₂(f / C4_HZ)
nearest_semitone = round(semitones_float)
cents_off = (semitones_float − nearest_semitone) × 100    [центы, диапазон ±50]
weight = exp(−cents_off² / (2 × 14²))                    [σ = 14 центов]
```

При σ=14 cents: на ±0 cent → 1.0, на ±14 cent → 0.607, на ±50 cent → 0.165.
Соседний полутон при ±50 cent смещении получает weight = 0.165.
Сумма весов на ближайший + соседний: ≈ 0.165 + 0.165 + centre ≈ 1.0 (сохранение энергии).

---

_Составлен: 2026-06-05_
_Домены: dsp, qa, docs_
_Сложность: high_
