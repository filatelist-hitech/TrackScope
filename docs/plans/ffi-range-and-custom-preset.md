# Plan: FFI `new_with_range` + Custom(min, max) preset

## 1. Task classification

- **complexity:** medium
- **domains:** dsp (FFI), mobile, ui

## 2. Agents

- **@dspman** — добавление нового FFI-символа в `core/ffi/src/lib.rs` и соответствующий Rust-тест.
- **@mobileman** — Dart-биндинг `new_with_range`, Custom-пресет в `AppSettings`, wire в `CaptureBridge`/`dsp_worker`.
- **@reviewman** — pre-merge review перед закрытием задачи.

## 3. Files to inspect

| Файл | Зачем |
|---|---|
| `core/ffi/src/lib.rs` | Добавить `hitech_bpm_engine_new_with_range(min, max)` |
| `core/ffi/tests/ffi_contract.rs` | Добавить тест нового символа |
| `apps/mobile/lib/dsp/bindings.dart` | Dart-биндинг нового символа |
| `apps/mobile/lib/dsp/engine.dart` | Передать `maxBpm` при создании движка |
| `apps/mobile/lib/capture/capture_bridge.dart` | Параметр `maxBpm` → worker |
| `apps/mobile/lib/capture/dsp_worker.dart` | Выбор `new` / `new_with_min_bpm` / `new_with_range` |
| `apps/mobile/lib/features/genre_preset/genre_preset.dart` | Добавить `custom` вариант |
| `apps/mobile/lib/settings/app_settings.dart` | Поля `customMin`, `customMax`; логика выбора символа |
| `apps/mobile/lib/screens/settings_screen.dart` | UI для Custom-пресета |
| `.claude/docs/project-map.md` | Обновить после каждого модуля |

## 4. Current behavior (с evidence)

1. **FFI**: существует только `hitech_bpm_engine_new_with_min_bpm(min_bpm: f32)` — `target_bpm_max` жёстко берётся из `DspConfig::default()` (230.0). Символа `new_with_range` нет — `grep new_with_range core/ffi/src/lib.rs` → пусто.

2. **Dart bindings** (`apps/mobile/lib/dsp/bindings.dart`): только `engineNewWithMinBpm` (строка 64). `maxBpm` нигде не передаётся.

3. **CaptureBridge** (`apps/mobile/lib/capture/capture_bridge.dart`, строка 34): принимает `minBpm` — `maxBpm` отсутствует.

4. **GenrePreset** (`apps/mobile/lib/features/genre_preset/genre_preset.dart`): 7 вариантов (hitechPsy…hardcore), Custom — отсутствует.

5. **AppSettings**: `customMin`/`customMax` — отсутствуют.

## 5. Target behavior

1. FFI-символ `hitech_bpm_engine_new_with_range(min_bpm: f32, max_bpm: f32)` создаёт движок с обоими зажатыми порогами.
2. Dart-биндинг и `CaptureBridge` принимают `maxBpm`; `dsp_worker` выбирает нужный конструктор.
3. `GenrePreset.custom` добавлен — Pro-only. При выборе UI показывает два слайдера/поля `min` и `max`.
4. `AppSettings.customMin` / `customMax` сохраняются в SharedPreferences; по умолчанию 155 / 230.
5. При смене пресета на любой не-Custom `CaptureBridge` пересоздаётся с `(min, max)` из `GenrePreset.bpmRange`. При Custom — с `(customMin, customMax)`.

## 6. Data contracts

### Новый FFI-символ
```c
// core/ffi/src/lib.rs
#[no_mangle]
pub extern "C" fn hitech_bpm_engine_new_with_range(
    min_bpm: f32,
    max_bpm: f32,
) -> *mut HitechBpmEngine;
// min зажимается [80, 260], max зажимается [min+10, 300]
// не-finite → default (155, 230)
```

### Dart binding (bindings.dart)
```dart
typedef _EngineNewWithRangeC = ffi.Pointer<HitechBpmEngine> Function(ffi.Float, ffi.Float);
typedef _EngineNewWithRangeDart = ffi.Pointer<HitechBpmEngine> Function(double, double);
Pointer<HitechBpmEngine> engineNewWithRange(double min, double max);
```

### CaptureBridge constructor
```dart
CaptureBridge({double? minBpm, double? maxBpm, ...})
// если maxBpm != null → worker вызывает new_with_range
// если только minBpm → new_with_min_bpm (backwards compat)
// если ничего → new
```

### AppSettings (новые поля)
```dart
double customMin = 155.0;  // SharedPreferences key: 'custom_min_bpm'
double customMax = 230.0;  // SharedPreferences key: 'custom_max_bpm'
```

### GenrePreset (добавить)
```dart
enum GenrePreset {
  ...,
  custom;
  bool get isProRequired => this == custom || ...;
  (double, double) get bpmRange => switch (this) {
    custom => (155.0, 230.0), // placeholder; реальные значения из AppSettings
    ...
  };
}
```

## 7. Implementation steps

Каждый шаг — отдельная единица работы с тестом рядом.

### Шаг 1: Rust FFI — `hitech_bpm_engine_new_with_range`

- `core/ffi/src/lib.rs`: добавить функцию после `new_with_min_bpm`.
  ```rust
  #[no_mangle]
  pub extern "C" fn hitech_bpm_engine_new_with_range(
      min_bpm: f32, max_bpm: f32,
  ) -> *mut HitechBpmEngine {
      let min = if min_bpm.is_finite() { min_bpm.clamp(80.0, 260.0) } else { 155.0 };
      let max = if max_bpm.is_finite() { max_bpm.clamp(min + 10.0, 300.0) } else { 230.0 };
      let cfg = DspConfig { target_bpm_min: min, target_bpm_max: max, ..DspConfig::default() };
      Box::into_raw(Box::new(HitechBpmEngine { inner: DspEngine::new(cfg) }))
  }
  ```
- `core/ffi/tests/ffi_contract.rs`: тест `engine_new_with_range_respects_min_max`:
  - создать движок `(160.0, 200.0)`, скормить 50 с синтетики 180 BPM, убедиться STABLE.
  - создать движок `(170.0, 190.0)`, скормить 30 с синтетики 220 BPM, убедиться что `primary_bpm == null` (вне range).
- Запуск: `cargo test --workspace`.
- Обновить `.claude/docs/project-map.md` (раздел core/ffi).

### Шаг 2: Dart bindings — `engineNewWithRange`

- `apps/mobile/lib/dsp/bindings.dart`: добавить `typedef` и lookup по аналогии с `engineNewWithMinBpm`.
- Unit-тест не нужен (FFI-lookup тестируется интеграционно).
- Обновить `.claude/docs/project-map.md` (раздел apps/mobile/lib/dsp).

### Шаг 3: `CaptureBridge` + `dsp_worker` — пробросить `maxBpm`

- `capture_bridge.dart`: добавить `final double? maxBpm;` в конструктор; передавать в worker-сообщение.
- `dsp_worker.dart`: при инициализации движка:
  ```dart
  if (maxBpm != null) {
    engine = bindings.engineNewWithRange(minBpm ?? 155.0, maxBpm!);
  } else if (minBpm != null) {
    engine = bindings.engineNewWithMinBpm(minBpm!);
  } else {
    engine = bindings.engineNew();
  }
  ```
- `apps/mobile/test/capture_bridge_test.dart` (если существует) или новый smoke-тест.
- Обновить `.claude/docs/project-map.md` (раздел apps/mobile/lib/capture).

### Шаг 4: `GenrePreset.custom`

- `genre_preset.dart`: добавить `custom` в enum.
  - `bpmRange` для custom возвращает `(155.0, 230.0)` — заглушка, реальные значения всегда берутся из `AppSettings.customMin/customMax`.
  - `isProRequired`: `custom` → `true`.
  - `label`: `'Custom'`.
- Обновить `.claude/docs/project-map.md`.

### Шаг 5: `AppSettings` — `customMin` / `customMax`

- `app_settings.dart`:
  - поля `double customMin = 155.0` и `double customMax = 230.0`.
  - загрузка/сохранение в SharedPreferences (`'custom_min_bpm'`, `'custom_max_bpm'`).
  - метод `setCustomRange(double min, double max)`: валидация `min < max`, `min >= 80`, `max <= 300`; иначе no-op.
  - helper `(double, double) get effectiveBpmRange`: если `selectedGenre == custom` → `(customMin, customMax)`, иначе `selectedGenre.bpmRange`.
- `apps/mobile/test/app_settings_test.dart`: проверить сохранение/загрузку, fallback при невалидных значениях.
- Обновить `.claude/docs/project-map.md`.

### Шаг 6: Wire в `main.dart` — передать `maxBpm` в `CaptureBridge`

- `main.dart` (или где создаётся `CaptureBridge`): читать `AppSettings.effectiveBpmRange`, передавать `minBpm` и `maxBpm` при создании/пересоздании моста при смене tier или пресета.
- Убедиться, что `ListenableBuilder` на `AppSettings` триггерит пересоздание при `setSelectedGenre` или `setCustomRange`.
- Обновить `.claude/docs/project-map.md`.

### Шаг 7: UI для Custom-пресета в `SettingsScreen`

- `settings_screen.dart`: при `selectedGenre == custom` (и Pro) показать два `TextField` / `Slider` для min и max.
  - Вызов `AppSettings.setCustomRange(min, max)` при изменении.
  - При Free — показать paywall-уведомление.
- `apps/mobile/test/screens/settings_screen_custom_test.dart`: проверить:
  - слайдеры видны при Custom + Pro.
  - слайдеры скрыты при не-Custom.
  - paywall-hint виден при Custom + Free.
- `flutter analyze` → 0 errors, `flutter test` → всё зелёное.
- Обновить `.claude/docs/project-map.md`.

## 8. Tests and commands

```sh
# Шаг 1 — Rust FFI
/opt/homebrew/opt/rust/bin/cargo test --workspace

# Шаги 2–7 — Flutter
flutter analyze
flutter test

# Опционально: parity (синтетика)
python3 tools/offline-lab/parity.py --fixture-set synthetic
```

Новые тесты:
- `core/ffi/tests/ffi_contract.rs` → `engine_new_with_range_respects_min_max`
- `apps/mobile/test/app_settings_test.dart` → `custom_range_persists`, `invalid_range_rejected`
- `apps/mobile/test/screens/settings_screen_custom_test.dart` → 3 теста (см. шаг 7)

## 9. Risks

| Риск | Вероятность | Fallback |
|---|---|---|
| `target_bpm_max` в `DspConfig` уже поддерживается — проверить перед реализацией | низкая | grep по `target_bpm_max` в `core/dsp/src/lib.rs` |
| Custom preset: UI слайдеров на малых экранах может обрезаться | средняя | TextField вместо Slider |
| Backwards compat: `CaptureBridge` без `maxBpm` должен работать как раньше | низкая | `maxBpm` опциональный с null-дефолтом |
| `parity.py` не затрагивается (нет Python-изменений) | — | — |

## 10. Done when

- `cargo test --workspace` — зелёный, включая `engine_new_with_range_respects_min_max`.
- `flutter analyze` → 0 errors.
- `flutter test` — зелёный, включая новые тесты CustomRange и SettingsScreen.
- `GenrePreset.custom` существует, Pro-gated, сохраняет `(min, max)` через SharedPreferences.
- `CaptureBridge` передаёт `maxBpm` в worker; worker выбирает `new_with_range` при `maxBpm != null`.
- UI в Settings: Custom + Pro → слайдеры/поля; Custom + Free → paywall-hint.
- `.claude/docs/project-map.md` обновлён после каждого из 7 шагов.
- Никакого фейкового BPM, `STABLE` без evidence, скрытых half/double-кандидатов.
