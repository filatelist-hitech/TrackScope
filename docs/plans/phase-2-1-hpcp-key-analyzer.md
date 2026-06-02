# Phase 2.1 — HPCP KeyAnalyzer

## 1. Task classification

- **Complexity:** high
- **Domains:** dsp · qa · docs

Обоснование high: HPCP требует FFT-конвейера (окно → DFT → хроматограмма),
Krumhansl-Schmuckler–корреляции против 24 профилей, скользящего 8-секундного
аккумулятора и Camelot-маппинга. Нужна новая зависимость (`rustfft`), интеграция
в `DspEngine` и парсинг нового JSON-поля в Dart.

---

## 2. Agents

| Агент | Навык | Зачем |
|---|---|---|
| `@dspman` | `dsp-tempo-analysis` | Реализация алгоритма HPCP + K-S в Rust |
| `@qaman` | `qa-audio-dataset` | Синтетические тест-фикстуры для pitch class detection |
| `@archman` | — | Аудит контракта: KeyResult в DspResult и Dart, FFI-prioр к расширению |
| `@docman` | — | Раздел Key Detection в `docs/DSP_ALGORITHM.md`, обновить ROADMAP |
| `@reviewman` | `review-gate` | Pre-merge гейт: anti-fake проверка, тесты зелёные |

---

## 3. Files to inspect

| Файл / директория | Роль |
|---|---|
| `core/dsp/src/key_analyzer.rs` | Основная реализация (сейчас `todo!()`) |
| `core/dsp/src/lib.rs` | `DspEngine` — добавить поле `key_analyzer`, заполнять `key_result` |
| `core/dsp/Cargo.toml` | Добавить `rustfft = "6"` |
| `core/dsp/tests/` | Добавить `key_detection.rs` |
| `core/ffi/src/lib.rs` | Только аудит: `key_result` сериализуется через JSON; изменений нет |
| `apps/mobile/lib/dsp/dsp_result.dart` | Добавить `KeyResult`, `MusicalKey`, `KeyMode` + парсинг |
| `apps/mobile/test/dsp_debug_test.dart` | Расширить: тест парсинга `key_result` из JSON |
| `docs/DSP_ALGORITHM.md` | Новый раздел «Детекция тональности» |
| `docs/ROADMAP.md` | Отметить Phase 2.1 в процессе |

---

## 4. Current behavior

- `KeyAnalyzer::new`, `push_samples`, `current_key`, `reset` — все три метода завершаются `todo!()`, помечены `#[allow(dead_code)]`.
- `DspEngine` не содержит `KeyAnalyzer` как поле.
- `DspResult.key_result` всегда `None`; поле присутствует в структуре, но заполняется в трёх местах как `key_result: None` (строки 888, 949, 1572 в `lib.rs`).
- JSON `key_result` отсутствует в каждом снапшоте (`skip_serializing_if = "Option::is_none"`).
- `DspResult.fromJson` в Dart не парсит `key_result` (поле игнорируется).

---

## 5. Target behavior

- `KeyAnalyzer` реализован и вызывается из `DspEngine`.
- При наличии достаточного аудио `DspResult.key_result` содержит:
  - `key`: `MusicalKey` (C, Db, D, …, B)
  - `mode`: `KeyMode` (Major / Minor)
  - `camelot`: `CamelotKey { number: 1–12, letter: 'A'|'B' }`
  - `confidence`: 0.0–1.0 (нормализованный коэффициент корреляции Пирсона)
- `key_result == None` при тишине, клиппинге (`CLIPPED_MIC`) и слабой уверенности (< `KEY_CONFIDENCE_THRESHOLD = 0.25`).
- Dart парсит и предоставляет `KeyResult` через `DspResult.keyResult`.
- `cargo test --workspace` → все тесты зелёные.
- `flutter test` → все тесты зелёные.

---

## 6. Data contracts

### Rust (уже в контракте, не ломать)

```rust
// core/dsp/src/key_analyzer.rs
pub struct KeyResult {
    pub key: Option<MusicalKey>,    // None пока confidence < порога
    pub mode: Option<KeyMode>,
    pub camelot: Option<CamelotKey>,
    pub confidence: f32,            // 0.0..1.0
}

// core/dsp/src/lib.rs
pub struct DspResult {
    // ... existing fields ...
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key_result: Option<KeyResult>,  // None → поле отсутствует в JSON
}
```

### JSON (новый поле при наличии результата)

```json
{
  "primary_bpm": 198.4,
  "key_result": {
    "key": "A",
    "mode": "Minor",
    "camelot": { "number": 8, "letter": "A" },
    "confidence": 0.73
  }
}
```

### Dart (новый код в `dsp_result.dart`)

```dart
class KeyResult {
  final String? key;       // "C", "Db", ... "B" или null
  final String? mode;      // "Major" | "Minor" | null
  final String? camelot;   // "8A", "12B", ... или null
  final double confidence;
}

// DspResult получает поле:
final KeyResult? keyResult;
```

### FFI-контракт

`key_result` сериализуется внутри JSON-блоба `hitech_bpm_engine_analyze_json`. FFI-граница не меняется. Никаких новых C ABI символов.

---

## 7. Implementation steps

### Шаг 1 — Добавить зависимость `rustfft`

**Файл:** `core/dsp/Cargo.toml`

```toml
[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
rustfft = "6"
```

`rustfft` — чистый Rust, no_std-совместимый, без C-зависимостей. Размер добавки ~100 KB в release-бинарь.

**Проверка:** `cargo check --workspace` должен пройти после добавления.

---

### Шаг 2 — Реализовать `KeyAnalyzer::new` и структуры данных

**Файл:** `core/dsp/src/key_analyzer.rs`

Внутренние поля:

```rust
use rustfft::{FftPlanner, num_complex::Complex};
use std::collections::VecDeque;

const HPCP_BINS: usize = 12;
const FRAME_SIZE: usize = 4096;   // ~85 мс при 48 kHz
const HOP_SIZE: usize = 2048;     // 50% overlap → 23 кадра/сек
const KEY_WINDOW_SECS: f32 = 8.0; // ёмкость аккумулятора
const KEY_CONFIDENCE_THRESHOLD: f32 = 0.25; // ниже → key = None

pub struct KeyAnalyzer {
    sample_rate: f32,
    fft_planner: FftPlanner<f32>,
    pcm_pending: Vec<f32>,
    hpcp_buffer: VecDeque<[f32; HPCP_BINS]>,
    buffer_capacity: usize,     // = ceil(sample_rate * KEY_WINDOW_SECS / HOP_SIZE)
    scratch: Vec<Complex<f32>>, // pre-alloc FFT scratch
    window: Vec<f32>,           // Hanning window FRAME_SIZE
}
```

`new(sample_rate)`:
- Вычислить `buffer_capacity`
- Предвычислить Hanning-окно: `window[i] = 0.5 * (1 - cos(2π*i/(N-1)))`
- Инициализировать `FftPlanner`

---

### Шаг 3 — Реализовать `extract_hpcp_frame`

Приватная функция `fn extract_hpcp_frame(frame: &[f32], sample_rate: f32, fft: &dyn Fft<f32>, scratch: &mut Vec<Complex<f32>>, window: &[f32]) -> [f32; 12]`:

1. Применить Hanning-окно к frame.
2. Скопировать в `Vec<Complex<f32>>`, Im=0.
3. `fft.process()` in-place.
4. Для каждого бина `k` (1..N/2):
   - `freq = k * sample_rate / FRAME_SIZE`
   - Пропустить если freq < 50 Hz или freq > 5000 Hz (kick не считаем, верхние биns тоже не нужны)
   - `pitch_class = ((12.0 * (freq / C_REF).log2()).round() as i32 % 12 + 12) % 12`
     где `C_REF = 261.63` Hz (C4)
   - `power = spectrum[k].norm_sqr()`
   - Добавить `power` в `hpcp[pitch_class]`
5. L2-нормализовать результат: если сумма > 0 → делим каждый бин на L2-норму.

**Тест сразу:** юнит-тест `hpcp_frame_a440_has_peak_at_class_9` — сигнал 440 Hz → pitch class 9 (A).

---

### Шаг 4 — Реализовать `push_samples`

```rust
pub fn push_samples(&mut self, samples: &[f32]) {
    self.pcm_pending.extend_from_slice(samples);
    while self.pcm_pending.len() >= FRAME_SIZE {
        let frame = &self.pcm_pending[..FRAME_SIZE];
        let hpcp = extract_hpcp_frame(frame, ...);
        if self.hpcp_buffer.len() >= self.buffer_capacity {
            self.hpcp_buffer.pop_front();
        }
        self.hpcp_buffer.push_back(hpcp);
        self.pcm_pending.drain(..HOP_SIZE);
    }
}
```

---

### Шаг 5 — Реализовать K-S профили и корреляцию

Константы в `key_analyzer.rs`:

```rust
// Krumhansl-Schmuckler (1990)
const MAJOR_PROFILE: [f32; 12] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
const MINOR_PROFILE: [f32; 12] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];
```

Функция `pearson_correlation(a: &[f32; 12], b: &[f32; 12]) -> f32`:
- Стандартная формула Пирсона (нормализованный результат −1..1).
- Если std == 0 → возвращает 0.0.

Функция `rotate_profile(profile: &[f32; 12], root: usize) -> [f32; 12]`:
- Циклический сдвиг профиля на `root` позиций вправо.

---

### Шаг 6 — Реализовать `current_key`

```rust
pub fn current_key(&self) -> KeyResult {
    if self.hpcp_buffer.is_empty() {
        return KeyResult::default();
    }
    // Аккумулировать среднее HPCP по буферу
    let mut avg_hpcp = [0.0f32; 12];
    for frame in &self.hpcp_buffer {
        for (i, v) in frame.iter().enumerate() { avg_hpcp[i] += v; }
    }
    let n = self.hpcp_buffer.len() as f32;
    avg_hpcp.iter_mut().for_each(|x| *x /= n);

    // Перебрать 24 профиля (12 major + 12 minor)
    let mut best_corr = f32::NEG_INFINITY;
    let mut best_root = 0usize;
    let mut best_mode = KeyMode::Major;
    for root in 0..12usize {
        let maj_corr = pearson_correlation(&avg_hpcp, &rotate_profile(&MAJOR_PROFILE, root));
        if maj_corr > best_corr { best_corr = maj_corr; best_root = root; best_mode = KeyMode::Major; }
        let min_corr = pearson_correlation(&avg_hpcp, &rotate_profile(&MINOR_PROFILE, root));
        if min_corr > best_corr { best_corr = min_corr; best_root = root; best_mode = KeyMode::Minor; }
    }

    // Нормализовать уверенность из [-1,1] → [0,1]
    let confidence = ((best_corr + 1.0) / 2.0).clamp(0.0, 1.0);
    if confidence < KEY_CONFIDENCE_THRESHOLD {
        return KeyResult::default(); // не фейкаем слабую уверенность
    }
    KeyResult {
        key: Some(root_to_musical_key(best_root)),
        mode: Some(best_mode),
        camelot: Some(to_camelot(best_root, best_mode)),
        confidence,
    }
}
```

Реализовать `reset`: очистить `pcm_pending` и `hpcp_buffer`.

**Тест:** `current_key_returns_none_on_empty_buffer` + `current_key_below_threshold_returns_none`.

---

### Шаг 7 — Таблицы маппинга

`root_to_musical_key(root: usize) -> MusicalKey` — match 0→C, 1→Db, ..., 11→B.

`to_camelot(root: usize, mode: KeyMode) -> CamelotKey` — таблица 24 значений:

```
Major: C=8B, Db=3B, D=10B, Eb=5B, E=12B, F=7B, Gb=2B, G=9B, Ab=4B, A=11B, Bb=6B, B=1B
Minor: A=8A, Bb=3A, B=10A, C=5A, Db=12A, D=7A, Eb=2A, E=9A, F=4A, Gb=11A, G=6A, Ab=1A
```

**Тест:** `camelot_mapping_am_is_8a`, `camelot_mapping_c_major_is_8b`.

---

### Шаг 8 — Интегрировать `KeyAnalyzer` в `DspEngine`

**Файл:** `core/dsp/src/lib.rs`

1. Добавить поле в `DspEngine`:

```rust
key_analyzer: KeyAnalyzer,
```

2. В `DspEngine::new` инициализировать:

```rust
key_analyzer: KeyAnalyzer::new(config.sample_rate as f32),
```

3. В `push_samples` (после добавления PCM в `pcm_window`):

```rust
self.key_analyzer.push_samples(samples);
```

4. В `analyze()` заполнить `key_result` перед возвратом снапшота.
   Только если `lock_state != CLIPPED_MIC && !signal_quality.silence`:

```rust
let key_result = if matches!(lock_state, LockState::ClippedMic)
    || signal_quality.silence {
    None
} else {
    let kr = self.key_analyzer.current_key();
    if kr.key.is_some() { Some(kr) } else { None }
};
```

5. В `DspEngine::reset` добавить `self.key_analyzer.reset()`.

6. В `empty_result` / `analyze_pcm` (batch path) — `key_result: None` остаётся (batch не накапливает ключ).

**Тест:** `key_analyzer_integrated_does_not_panic_on_silence` — `push_samples(zeros)` → `analyze().key_result == None`.

---

### Шаг 9 — Тесты Rust (`core/dsp/tests/key_detection.rs`)

Создать файл. Фикстуры генерируются в памяти (без WAV):

```rust
fn pure_sine(freq_hz: f32, duration_sec: f32, sample_rate: u32) -> Vec<f32>
fn chord_sine(freqs: &[f32], duration_sec: f32, sample_rate: u32) -> Vec<f32>
```

Требуемые тест-кейсы:

| Тест | Фикстура | Ожидаемый результат |
|---|---|---|
| `a440_sine_detects_a` | Синус 440 Hz, 8 с, SR=48k | `key == Some(A)` |
| `c4_sine_detects_c` | Синус 261.63 Hz, 8 с, SR=48k | `key == Some(C)` |
| `a_minor_chord_detects_a_minor` | 440+523+659 Hz (A-C-E), 10 с | `key==A, mode==Minor, confidence>0.3` |
| `silence_no_key` | Нули, 12 с | `key_result == None` |
| `white_noise_low_confidence` | `rand`-шум, 12 с | `confidence < 0.3` → `key == None` |
| `camelot_mapping_am_is_8a` | Unit: `to_camelot(9, Minor)` | `CamelotKey{8,'A'}` |
| `camelot_mapping_c_major_is_8b` | Unit: `to_camelot(0, Major)` | `CamelotKey{8,'B'}` |
| `key_result_absent_from_json_when_none` | DspResult с `key_result: None` | JSON не содержит ключ `"key_result"` |
| `key_result_present_in_json_when_some` | DspResult с KeyResult(A,Minor,8A,0.8) | JSON содержит `"key_result"` |
| `reset_clears_key_state` | 8 с A440 → reset → 1 с шума | `key_result == None` после reset+шума |

Зарегистрировать в `core/dsp/Cargo.toml`:

```toml
[[test]]
name = "key_detection"
path = "tests/key_detection.rs"
```

---

### Шаг 10 — Dart: добавить `KeyResult` в `dsp_result.dart`

```dart
class KeyResult {
  final String? key;      // "C", "Db", ..., "B"
  final String? mode;     // "Major" | "Minor"
  final String? camelot;  // "8A", "8B", ...
  final double confidence;

  const KeyResult({this.key, this.mode, this.camelot, required this.confidence});

  factory KeyResult.fromJson(Map<String, dynamic> json) => KeyResult(
    key: json['key'] as String?,
    mode: json['mode'] as String?,
    camelot: json['camelot'] is Map
        ? '${(json['camelot'] as Map)['number']}${(json['camelot'] as Map)['letter']}'
        : null,
    confidence: _asDoubleOrNull(json['confidence']) ?? 0.0,
  );
}
```

Добавить поле в `DspResult`:

```dart
final KeyResult? keyResult;
```

В `DspResult.fromJson`:

```dart
keyResult: json['key_result'] == null
    ? null
    : KeyResult.fromJson((json['key_result'] as Map).cast<String, dynamic>()),
```

**Тест:** расширить `apps/mobile/test/dsp_debug_test.dart` — парсинг JSON со вложенным `key_result`.

---

### Шаг 11 — Обновить документацию

**Файл:** `docs/DSP_ALGORITHM.md` — новый раздел «Детекция тональности (Phase 2.1)»:
- Описание алгоритма (HPCP → K-S → Camelot)
- Таблица Camelot-маппинга
- Известные ограничения

**Файл:** `docs/ROADMAP.md` — добавить Phase 2.1 в состоянии «В ПРОЦЕССЕ».

---

## 8. Tests

### Команды валидации

```sh
# Rust: весь воркспейс (включая новый key_detection.rs)
/opt/homebrew/opt/rust/bin/cargo test --workspace

# Конкретный тест-файл в процессе разработки
/opt/homebrew/opt/rust/bin/cargo test -p hitech-bpm-dsp --test key_detection

# Python-регрессия (не трогаем, должна остаться зелёной)
python3 -m unittest discover core/tests

# Dart/Flutter
flutter test
flutter analyze
```

### Тест-инвариант anti-fake

В `key_detection.rs` обязательно:

```rust
// key_result НИКОГДА не содержит значение при тишине
assert!(silence_result.key_result.is_none());
// key_result НИКОГДА не содержит значение при CLIPPED_MIC
// (проверяется через интеграционный тест с severely_clipped_pulse)
```

---

## 9. Risks

| Риск | Вероятность | Влияние | Фолбэк |
|---|---|---|---|
| `rustfft` конфликт версий с воркспейсом | низкая | средняя | Пинить `rustfft = "6.2"` явно; проверить `cargo tree` |
| `FftPlanner` и `KeyAnalyzer` не реализуют `Clone` | средняя | средняя | `DspEngine` уже реализует `Clone` через derive — нужно добавить ручной `Clone` для `KeyAnalyzer` или убрать derive у `DspEngine` и перейти на `Arc`. Фолбэк: `KeyAnalyzer` без Clone, `DspEngine` без derive Clone (заменить на ручной impl) |
| Синус-фикстуры дают неоднозначный ключ | средняя | низкая | Один синус даёт единственный пик HPCP → K-S с root=pitch_class даст высокую корреляцию и для major, и для minor; тест `a440_sine_detects_a` проверяет только `key == Some(A)`, не `mode`. Для `mode`-теста использовать аккорд. |
| HPCP ненадёжен при шуме / брейкдауне | высокая | низкая | Порог `KEY_CONFIDENCE_THRESHOLD = 0.25` → `key_result = None`. Anti-fake: никогда не возвращать ключ с низкой уверенностью |
| Производительность на мобильном (FFT 4096 × 23 fps) | низкая | средняя | `rustfft` uses cached FFT plan; на ARM64 ~0.3 мс/кадр. Если CI perf-тест упадёт → уменьшить FRAME_SIZE до 2048 |
| parity.py чувствителен к новым JSON-полям | низкая | низкая | `key_result` отсутствует в batch-path (`analyze_pcm`), поэтому в JSON снапшотах Python-анализатора его нет. `parity.py` сравнивает `primary_bpm` и `confidence` — новые поля игнорируются |

---

## 10. Done when

| Критерий | Как проверить |
|---|---|
| `cargo test --workspace` → все тесты зелёные (включая `key_detection.rs`) | CI или локально |
| `flutter test` → все тесты зелёные | `flutter test` |
| `flutter analyze` → 0 errors | `flutter analyze` |
| Синус 440 Hz (8 с) → `key_result.key == "A"` | `a440_sine_detects_a` |
| Синус 261.63 Hz (8 с) → `key_result.key == "C"` | `c4_sine_detects_c` |
| Тишина → `key_result == None` в DspResult | `silence_no_key` |
| Шум → `key_result == None` | `white_noise_low_confidence` |
| `CLIPPED_MIC` → `key_result == None` | интеграционный тест в `key_detection.rs` |
| Camelot A minor → "8A", C major → "8B" | `camelot_mapping_*` |
| JSON: `key_result` отсутствует когда `None` | `key_result_absent_from_json_when_none` |
| Dart парсит `key_result` из JSON без паники | `dsp_debug_test.dart` — новый случай |
| `docs/DSP_ALGORITHM.md` обновлён разделом Key Detection | `grep "HPCP" docs/DSP_ALGORITHM.md` |
| Нет хардкодных значений тональности в продакшен-пути | Ревью @reviewman |
| Нет фейкового BPM / hidden half-double кандидатов | anti-fake инвариант в тестах |
