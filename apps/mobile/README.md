# apps/mobile

Граница Flutter-мобильного приложения.

Это приложение владеет разрешениями микрофона, интеграцией нативного аудио-моста, рендером живого результата, отладочным выводом и историей сессий. Оно не должно считать BPM вне `core/dsp`.

## Текущее состояние (Phase 7 — UI overhaul)

### Главный экран (`lib/ui/main_screen.dart`)

Экран делится на три зоны:

| Зона | Высота | Содержимое |
|---|---|---|
| Спектрограмма | ~35 % | Скроллящаяся FFT-карта (200 колонок × 128 бинов) с метрическими осями (Hz и время), тепловая LUT, курсор «Now» акцентным цветом |
| Live spectrum | ~22 % | Текущий FFT-кадр в виде сглаженной кривой с gradient fill и peak hold тиками, логарифмическая X-ось 20–20 000 Hz |
| Glassmorphism-карточка | ~43 % | `DspResult`-поля: BPM (JetBrains Mono 52 sp), анимированный бейдж захвата, уверенность, уровень входа, лучший кандидат, ×½ / ×2, клиппинг, шум |

Если микрофон ещё не активен → плейсхолдер «Ожидание микрофона…» в обеих визуализационных панелях (реальный Flutter-виджет, находим тестами).

### Design system (`lib/ui/design_tokens.dart`)

- Фон: `#07070F`, поверхность: `#0F0F1A`, акцент: `#00E5CC`
- Типографика: **JetBrains Mono** (через `google_fonts ^6.2.1`) для BPM-числа и числовых метрик
- Glassmorphism-карточка: `BackdropFilter(ImageFilter.blur(12, 12))` + `ClipRRect(r=16)`
- Бейджи: `AnimatedSwitcher` (200 мс fade) + `ValueKey<LockState>`

### Состояния захвата (русские метки)

| `LockState` | Метка | Цвет |
|---|---|---|
| `STABLE` | стабильно | `#00C853` (зелёный) |
| `LOCKING` | захват | `#FFB300` (янтарный) |
| `UNSTABLE` | нестабильно | `#FFB300` (янтарный) |
| `BREAKDOWN` | брейк | `#00E5CC` (акцент / teal) |
| `CLIPPED_MIC` | перегруз | `#FF4444` (красный) |
| `NOISE_ONLY` | только шум | `#9B59B6` (фиолетовый) |
| `SEARCHING` | поиск | тёмный нейтральный |

### Визуализация (`lib/viz/`)

- **`VizController`** (`ChangeNotifier`) — FFT-пайплайн: единственный вызов `compute()` за hop (~20 раз/с) питает три потребителя: `specCols`, `smoothedBars` и `latestNorms`/`peakHoldValues`. Нет двойного FFT.
- **`SpectrogramPainter`** — 25 600 `drawRect`-вызовов + оси; `Paint`-объекты предаллоцированы в LUT (256 штук).
- **`LiveSpectrumPainter`** — smooth-кривая через `quadraticBezierTo` (~426 bezier-сегментов), gradient fill, peak hold тики; fixed dBFS нормализация.
- Все три компонента обёрнуты в `RepaintBoundary`.

### Unified FFT Pipeline

```
Raw PCM → VizController._scheduleFFT()
              ↓ compute() → mags: Float64List (512 бинов, read-only)
              │
   ┌──────────┼──────────────────┐
   ▼          ▼                  ▼
specCols  smoothedBars     latestNorms + peakHoldValues
```

FFT вычисляется ровно один раз за hop. Подробнее: `docs/MOBILE_AUDIO.md` → «Unified FFT Pipeline (Phase 7)».

### Параметры FFT

| Параметр | Значение |
|---|---|
| Библиотека | `fftea 1.5.0+1` (pure Dart) |
| Размер FFT (`_kFftSize`) | 1024 samples |
| Hop | 2400 samples (~50 мс при 48 кГц) |
| Положительных бинов | 512 |
| Дисплей-бинов спектрограммы | 128 (0–6 кГц) |
| Видимый диапазон LiveSpectrum | ~426 бинов (20–20 000 Hz) |
| Окно | Hann |
| Нормализация latestNorms | fixed dBFS, ref `_kRefMag`, floor −60 dBFS |
| Peak hold | 30 колонок × 0.90 decay |

## Сборка и тесты

```sh
# из корня воркспейса
/opt/homebrew/opt/rust/bin/cargo test --workspace
python3 -m unittest discover core/tests
/opt/homebrew/opt/nodejs/bin/node --test core/dsp/index.test.js
python3 tools/offline-lab/offline_lab.py report

# из apps/mobile/
flutter pub get
flutter analyze
flutter test
```

## Регенерация FFI-биндингов

`lib/dsp/bindings.dart` закоммичен. Перегенерировать после изменения C-хедера:

```sh
# из apps/mobile/
flutter pub run ffigen --config pubspec.yaml
```

## Известные ограничения (Phase 7)

- FFT запускается через `compute()` ~20 раз/с; при высокой частоте spawn'а изолятов на слабых устройствах возможна задержка — мониторить на реальных девайсах.
- `BackdropFilter` (glassmorphism card) несёт GPU-стоимость на слабых устройствах; при необходимости заменить на сплошной фон.
- `snr_estimate_db` на чистых синтетических пульсах может оставаться `null` — ожидаемое поведение.
- iOS-симулятор не поддерживает захват микрофона — визуализации будут показывать плейсхолдер; тестировать на реальном устройстве.
