# Changelog

Все значимые изменения этого проекта будут задокументированы в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), а проект придерживается семантического версионирования после старта релизов.

## [Unreleased]

### Fixed

- **DSP regression (Phase 8, 2026-05-29):** Исправлено зависание в состоянии LOCKING с низкой уверенностью (~30–50%) на стабильных треках. Корневая причина: `ADAPTIVE_WINDOW_LOCKING_SECS` был установлен в 4.0 с (Phase 4.5), что давало только ~13 ударов при 200 BPM → confidence ~0.68, ниже порога 0.72 для STABLE. Увеличено до 6.0 с (совпадает с `lock_min_seconds`), теперь ~20 ударов → confidence ≥ 0.72 → успешный переход в STABLE за ≤12 секунд. (core/dsp/src/lib.rs:242)

### Changed

- **Waveform visualization (Phase 8, 2026-05-29):** Подтверждено соответствие спецификации Traktor DJ bar-column style — острые вертикальные прямоугольные колонки (drawRect), цветовой градиент по bass-энергии (0xFF003D35 → 0xFF00E5CC), без пунктирных линий. Реализация уже корректна с Phase 7. (apps/mobile/lib/viz/waveform_painter.dart, apps/mobile/lib/viz/waveform_column.dart)

- **DSP fast re-lock v2**: re-lock after track change now ≤ 3 s (was 6–8 s)
  - State-based adaptive analysis window: STABLE=full history, LOCKING=6 s (updated from 4 s), SEARCHING/UNSTABLE=2 s
  - Tempo jump detector: threshold 15 BPM triggers `bpm_history` reset + force SEARCHING
  - New `DspConfig` fields: `adaptive_window` (default `true`), `tempo_jump_threshold` (default `15.0`)
  - 6 new streaming regression tests including `tempo_change_185_to_200`, `tempo_change_200_to_170`, `no_false_stable_during_transition`
  - All 43 Rust tests pass; 15/15 QA fixtures PASS

---

### Phase 7.1 — Осциллограф вместо спектрограммы (2026-05-29)

#### Changed

- **`WaveformPainter`** переписан в стиль осциллографа: тёмный фон с сеткой (4×6 линий), glow-проход (`MaskFilter.blur 5px`) + чёткая линия, пунктирный курсор «Now» у правого края, метка «WAVEFORM» в левом верхнем углу. Цвет `accentColor` вместо хардкоданного `#00BFA5`; при клиппинге — `#FF4444`.
- **Главный экран (`main_screen.dart`)**: панель `_SpectrogramView` (35 %) заменена на `_WaveformView` (35 %). Импорт `spectrogram_painter.dart` убран, добавлен `waveform_painter.dart`. `_WaveformView` получает `isClipping` из `DspResult` для мгновенного предупреждения о перегрузе.
- Старая спектрограмма-тайлы полностью убрана из видимого UI. Файл `spectrogram_painter.dart` сохранён.

---

### Phase 7 — UI overhaul: метрическая спектрограмма, live-спектр, design system (2026-05-29)

#### Added

- **`SpectrogramPainter` с метрическими осями** (`apps/mobile/lib/viz/spectrogram_painter.dart`): Y-ось — Hz-метки ([63, 125, 250, 500, 1000, 2000, 4000] Hz) на лог-шкале с горизонтальными gridlines; X-ось — временны́е метки [−8s … 0] с вертикальными gridlines. Курсор «Now» изменён с `Color(0x66FFFFFF)` на `accentColor.withAlpha(153)`. Метка «SPECTROGRAM» в левом верхнем углу.

- **`LiveSpectrumPainter`** (`apps/mobile/lib/viz/live_spectrum_painter.dart`, новый файл): smooth real-time FFT-кривая с gradient fill и peak hold тиками. Логарифмическая X-ось 20 Hz–20 kHz. Получает `latestNorms` и `peakHoldValues` из `VizController`, читает ровно один раз за hop. Метка «LIVE SPECTRUM» в левом верхнем углу.

- **`AppTheme`** (`apps/mobile/lib/ui/design_tokens.dart`, новый файл): централизованные цветовые и типографические константы. Акцент `#00E5CC`, фон `#07070F`, JetBrains Mono через `google_fonts`.

- **`VizController.latestNorms` + `peakHoldValues`** (`apps/mobile/lib/viz/viz_controller.dart`): третий FFT-потребитель в `_scheduleFFT()` — fixed-dBFS нормализация (ref `_kRefMag`, floor `_kFloorDb`). Peak hold: 30 колонок (~1.5 с), decay ×0.90 после истечения. FFT вычисляется ровно один раз за hop.

- **Glassmorphism-карточка** (`apps/mobile/lib/ui/main_screen.dart`): `BackdropFilter(ImageFilter.blur(12, 12))` + `ClipRRect(r=16)` + border `Colors.white.withAlpha(18)`.

- **`AnimatedSwitcher`-бейджи** с `ValueKey<LockState>` — плавный fade 200 мс при смене состояния захвата.

- **JetBrains Mono** (`pubspec.yaml`: `google_fonts: ^6.2.1`) для BPM-числа и числовых метрик.

- **4 новых widget-теста** (`apps/mobile/test/widget_test.dart`): UNSTABLE→'нестабильно', BREAKDOWN→'брейк', NOISE_ONLY→'только шум', LOCKING→'захват'.

#### Changed

- Раскладка главного экрана: `SpectrumBarsPainter (45%) + WaveformPainter (15%)` заменены на `Spectrogram (35%) + LiveSpectrum (22%)`. Info-блок увеличен до 43%.

- Бейдж CLIPPED_MIC: метка изменена с `'перегруз микрофона'` на `'перегруз'` (короче, умещается в pill).

- Все локальные цветовые константы (`_kBg`, `_kSurface`, `_kTeal`) заменены на `AppTheme.*`.

- `RepaintBoundary` обёрнут вокруг `SpectrogramPainter`, `LiveSpectrumPainter` и glassmorphism-карточки.

---

### Phase 6 — стабилизация BPM-отображения (2026-05-29)

#### Added

- **Параболическая интерполяция пика автокорреляции** (`core/dsp/src/lib.rs`, `tempo_autocorrelation()`): дробный лаг `k_frac = k + (A[k+1] - A[k-1]) / (2·(2·A[k] - A[k-1] - A[k+1]))` снижает ошибку дискретизации с до ~2 BPM/лаг до < 0.2 BPM для любого BPM-значения. Fallback к целому лагу на плоских вершинах и выходах за диапазон.

- **BPM candidate history в `DspEngine`** (`core/dsp/src/lib.rs`): скользящий буфер N=3 значений `primary_bpm` в STABLE, заменяет мгновенное значение медианой. Очищается при любом не-STABLE кадре.

- **`BpmDisplay`** (`apps/mobile/lib/capture/bpm_display.dart`): display-layer EMA (α=0.2) для большого BPM-числа в `MainScreen`. Активен только в STABLE; снэп к первому значению без задержки. Добавлен параметр `displayBpm` в `_InfoTable`.

- **`core/dsp/tests/stability.rs`** — 7 новых Rust-тестов: `parabolic_flat_peak_no_panic`, `parabolic_precision_200_bpm`, `streak_stability_{180,195,200,220}_bpm`, `bpm_history_clears_on_state_change`. Streak-допуск ±0.5 BPM (строже базового ±1.0 BPM).

- **`apps/mobile/test/bpm_display_test.dart`** — 8 unit-тестов `BpmDisplay`: null на не-STABLE, snap, EMA, сброс, re-entry, anti-fake, reset(), сходимость.

#### Changed

- Большое BPM-число на главном экране теперь показывается только в STABLE (было: LOCKING + STABLE). Во время LOCKING отображается `—`.

#### Diagnostic (Phase 6 pre-fix measurements)

При `hop_sec = 0.0025 с`:
- 195 BPM, lag=123 → 195.1 BPM; lag=124 → 193.5 BPM; с интерполяцией → 195.0 BPM
- 180 BPM, lag=133 → 180.5 BPM; lag=134 → 179.1 BPM; с интерполяцией → 180.0 BPM
- 220 BPM, lag=109 → 220.2 BPM; lag=110 → 218.2 BPM; с интерполяцией → 220.0 BPM

### Phase 5 UI — редизайн главного экрана (2026-05-27)

#### Added

- **`apps/mobile/lib/viz/viz_controller.dart`** — `VizController` (`ChangeNotifier`): подписывается на `CaptureBridge.rawPcm`, хранит ~4-секундный кольцевой буфер PCM-16 LE → f32, запускает Dart-side FFT через `compute()` (~50 мс интервал). Никогда не смотрит в `DspResult`, не вычисляет BPM. LUT (256 `Color`-записей, 7 контрольных точек) и 256 `Paint`-объектов предвычислены при инициализации — `Color.lerp` не вызывается в горячем пути рендеринга.

- **`apps/mobile/lib/viz/spectrogram_painter.dart`** — `SpectrogramPainter` (`CustomPainter`): скроллящаяся FFT-карта (время → право, частота → верх, яркость = логарифм амплитуды). 200 колонок × 128 бинов (0–6 кГц). Использует `VizController.lutPaints` — Paint создаются один раз.

- **`apps/mobile/lib/viz/waveform_painter.dart`** — `WaveformPainter` (`CustomPainter`): амплитуда PCM vs время, центрированная нулевая линия. Цвет teal `#00BFA5`, краснеет (`#F44336`) когда `DspResult.signal_quality.clipping == true`.

- **`CaptureBridge.rawPcm`** (`Stream<Uint8List>`): новый broadcast-стрим в `capture_bridge.dart`, форкнутый от PCM-источника до отправки в DSP-воркер. Используется `VizController` — DSP-изолят не затронут.

- **Редизайн `apps/mobile/lib/ui/main_screen.dart`**: три секции — спектрограмма (~45 %), волноформа (~15 %), информационная таблица (~40 %). `RepaintBoundary` вокруг каждой визуализации. Тёмная тема (`#0A0A0F`), monospace-шрифт для числовых полей. Таблица содержит: крупный BPM (52 sp), badge состояния захвата (русские метки для всех 7 состояний), уверенность, уровень входа, лучший кандидат, полутемп/двойной темп, клиппинг, уровень шума. `primary_bpm == null` → «—», не «0».

- **Badge lock_state** с русскими метками и цветами: поиск (серый), захват (янтарный), стабильно (зелёный), нестабильно (оранжевый), брейк (синий), перегруз микрофона (красный), только шум (фиолетовый).

- **Тёмная тема** в `main.dart`: `ThemeData.dark()` с `scaffoldBackgroundColor: #0A0A0F`, `primary: #00BFA5`.

- **`fftea: ^1.5.0`** в `pubspec.yaml` — чистый Dart FFT без platform channels, безопасен в любом изоляте. Обоснование: требуется Dart-side FFT для спектрограммы без зависимости от Rust DSP.

#### Changed

- **`apps/mobile/test/widget_test.dart`** — обновлены smoke-тесты: новые русские метки badge (стабильно, поиск, перегруз микрофона), плейсхолдер «Ожидание микрофона…», тест навигации на debug screen. Добавлен тест для CLIPPED_MIC (null BPM + ⚠ ПЕРЕГРУЗ).

- **`docs/MOBILE_AUDIO.md`** — новый раздел «Dart-side визуализации (Phase 5)»: изолятная топология, FFT-параметры, таблица цветовой палитры LUT, описание RepaintBoundary и известные ограничения.

#### Known limitations (Phase 5)

- `compute()` создаёт новый Dart-изолят при каждом FFT-вызове (~20/с). На слабых устройствах возможны кратковременные подтормаживания при отрисовке спектрограммы. Замена на персистентный viz-изолят — следующий патч.
- Waveform использует поточечную выборку (не RMS) — на очень тихом сигнале может выглядеть «зубчато».
- iOS Simulator не поддерживает захват микрофона — `VizController.hasData == false`, показывается плейсхолдер.

### Phase 4 (частичная реализация, 2026-05-26)

#### Added
- **`apps/mobile/lib/capture/bpm_smoother.dart`** — новый Dart-класс `BpmSmoother`, реализующий три UI-слоя стабилизации: (1) медианный фильтр последних N=5 снэпшотов `primary_bpm` (~250 мс при 50 мс опросе), (2) EMA уверенности α=0.2, (3) гистерезис выхода из `STABLE` — K=3 подряд идущих не-`STABLE` кадров. `CLIPPED_MIC` / `BREAKDOWN` / `NOISE_ONLY` сбрасывают гистерезис немедленно. Сглаживание расположено в Dart, не в Rust, чтобы Rust DSP оставался parity-тестируемым без модификации.
- **SNR-оценка в Rust** (`core/dsp/src/lib.rs`): функция `estimate_snr_db` — перцентильный метод (20-й перцентиль = шумовой пол, 80-й = уровень сигнала). Вызывается из `measure_signal`, результат попадает в `signal_quality.snr_estimate_db`. До Phase 4 `snr_estimate_db` всегда был `null`; теперь не `null` для реальных шумовых входов через Rust-путь.
- **SNR-based `signal_factor`** (`core/dsp/src/lib.rs`): использует `snr_estimate_db`, когда доступен, вместо fallback на категориальный `noise_level`. Градация: SNR >= 20 dB → 1.0; 10–20 dB → 0.72–1.0; 3–10 dB → 0.45–0.72; < 3 dB → 0.28.

#### Changed
- **`apps/mobile/lib/capture/capture_bridge.dart`** — интегрирован `BpmSmoother`: `_smoother.smooth(parsed)` применяется перед отправкой `DspResult` в UI-стрим; `_smoother.reset()` вызывается при `stop()`.
- **`docs/DSP_ALGORITHM.md`** — добавлены: раздел "SNR-оценка и signal_factor" в "Движок уверенности"; новый раздел "Dart-слой сглаживания (Phase 4)" с описанием `BpmSmoother`; обновлена заметка про `snr_estimate_db` в "Текущее состояние имплементации".
- **`docs/ROADMAP.md`** — Phase 4 переведена из "СЛЕДУЮЩАЯ ФАЗА" в "В ПРОЦЕССЕ"; задачи 4.1 и 4.2 (SNR-часть) отмечены выполненными; открытые подзадачи явно помечены бэклогом.
- **`docs/QA_MATRIX.md`** — обновлена дата верификации (26.05.2026); добавлена заметка о поведении `snr_estimate_db` в Python vs Rust.

#### Known limitations (Phase 4)
- MA-сглаживание огибающей онсетов в Rust не добавлялось: тест показал ложную периодичность на `unstable_club_simulation`. Остаётся бэклогом задачи 4.2.
- `snr_estimate_db` может оставаться `null` на синтетических пульсах без фонового шума — ожидаемое поведение.
- Python-анализатор эмитит `snr_estimate_db: null` для всех фикстур — SNR-оценка реализована только в Rust.

### Phase 4.3 — Snapshot-based тестирование на реальных записях (2026-05-26)

#### Added
- **`tools/offline-lab/offline_lab.py snapshot`** — новая подкоманда. Принимает директорию с аудиофайлами (WAV/AIFF/FLAC), конвертирует каждый через ffmpeg в 16-бит моно PCM WAV 44100 Гц, прогоняет Python-анализатор и Rust-бинарник `analyze_wav` на одном и том же PCM-окне (по умолчанию 30 сек), сохраняет JSON-снапшот в `<dir>/snapshots/<name>.json`. Аудиофайлы не коммитятся (copyright/размер); снапшоты коммитятся. Флаги: `--input DIR`, `--force`, `--duration SECS`, `--cargo PATH`, `--release`.
- **`datasets/hitech/snapshots/`** — 21 JSON-снапшот реальных hitech/psytrance-треков (180–210 BPM), захваченных из `datasets/hitech/`. Каждый снапшот содержит `captured_at`, `category`, `expected_bpm_hint`, `fixture_sha256` (SHA-256 30-секундного PCM-окна), полные поля `python` и `rust` (`DspResult` с `debug`, `signal_quality`, `candidates`), `source_file`.
- **`datasets/fixture_manifest.json`** — единый список фикстур с допусками на фикстуру. Обновляется автоматически командой `snapshot`. Поля на запись: `name`, `snapshot` (путь), `category`, `bpm_tolerance`, `lock_state_must_match`.
- **`tools/offline-lab/parity.py`** — расширен тремя новыми режимами поверх legacy-синтетического режима:
  - **По умолчанию (все manifest-фикстуры)** — читает `datasets/fixture_manifest.json`, загружает снапшоты, сравнивает `python.primary_bpm` vs `rust.primary_bpm` с per-fixture `bpm_tolerance`. Работает в CI без аудиофайлов.
  - **`--fixture-set real`** — только `category: real` из манифеста.
  - **`--fixture-set synthetic`** — только legacy-режим (live-генерация синтетических фикстур, прежнее поведение baseline).
  - **`--live --input DIR`** — перезапускает текущий Rust-анализатор на аудиофайлах, сравнивает с Python из снапшота. Используется после DSP-изменений для проверки drift до обновления снапшотов.

#### Changed
- **`docs/QA_MATRIX.md`** — добавлена секция "Реальные фикстуры (Phase 4.3)": обоснование допуска ±4 BPM (структурный предел Python `float64` vs Rust `f32` через ~4800 членов автокорреляции), таблица 21 реальной фикстуры с `expected_bpm_hint`, детектированным BPM, delta, lock_state, результатом.
- **`tools/offline-lab/README.md`** — переписан: документирует команду `snapshot` (флаги, формат JSON), все режимы `parity.py` (таблица флагов), формат `fixture_manifest.json` с описанием полей и допусков.
- **`docs/ROADMAP.md`** — задача 4.3 "Реальные тестовые записи" обновлена с "НЕ НАЧАТО" на "ЗАВЕРШЕНО"; задача 4.4 "Регрессионное покрытие реального микрофона" — parity.py расширен (✓), остальные подзадачи сохраняют статус.

#### Known limitations (Phase 4.3)
- `hitech_real_10`: оба анализатора детектируют ~146.7 BPM при BPM-подсказке 196 — вероятная half-time ловушка в конкретной записи. Документировано в QA_MATRIX.md; снапшот корректен (отражает реальный вывод движка).
- `parity.py --live` требует присутствия аудиофайлов локально и ffmpeg в PATH.
- Python `snr_estimate_db: null` во всех снапшотах — ожидаемо (SNR-оценка только в Rust).

---

### Added
- `scripts/build_ios_native.sh` — bash-скрипт для кросс-компиляции `libhitech_bpm_ffi.a` под `aarch64-apple-ios` через rustup. Разрешает конфликт двух Rust-тулчейнов: явно переставляет PATH на `~/.rustup/toolchains/stable-aarch64-apple-darwin/bin`, чтобы cargo использовал rustup-управляемый тулчейн с iOS-таргетом, а не Homebrew-rustc. Копирует `.a` в `apps/mobile/ios/Frameworks/`.

### Fixed
- **iOS: `dlsym symbol not found` при запуске** — iOS линкер выкидывал Rust-символы из `.a` через dead-code stripping; `DynamicLibrary.process()` не находил их. Исправлено добавлением `-force_load $(PROJECT_DIR)/Frameworks/libhitech_bpm_ffi.a` в `OTHER_LDFLAGS` для Debug и Release конфигураций Runner в `apps/mobile/ios/Runner.xcodeproj/project.pbxproj`.
- **iOS: микрофонное разрешение молча denied** — `permission_handler` 12.x требует compile-time флага `PERMISSION_MICROPHONE=1` в `GCC_PREPROCESSOR_DEFINITIONS`; без него `Permission.microphone.request()` возвращает `denied`, не показывая системный диалог. Исправлено добавлением флага в `post_install` в `apps/mobile/ios/Podfile`.
- **iOS: `DynamicLibrary.process()` вместо `DynamicLibrary.open()`** — для статически слинкованной `.a` библиотеки нужно открывать символы из текущего процесса, а не из файла. `apps/mobile/lib/dsp/engine.dart` теперь вызывает `DynamicLibrary.process()` для iOS через приватную функцию `_openLibrary(libraryPath)`.

### Changed
- `record` обновлён с `^5.1.2` до `^6.0.0` (resolved: 6.2.1) — исправляет несовместимость `record_linux 0.7.2` с `record_platform_interface 1.6.0`, которая вызывала ошибку компиляции даже при сборке под iOS (Dart компилирует все platform implementations).
- `permission_handler` обновлён с `^11.3.1` до `^12.0.0` (resolved: 12.0.1) — aligned с требованиями Podfile compile-time flags.
- `docs/MOBILE_AUDIO.md` дополнен разделами: сборка нативной библиотеки для iOS, Xcode-конфигурация (`-force_load`, Library Search Paths), `PERMISSION_MICROPHONE=1` в Podfile, результаты реального устройства Phase 3.
- `docs/ROADMAP.md` — Phase 1, 2, 3 помечены как ЗАВЕРШЕНО; Phase 4 расширена конкретными задачами по наблюдениям с iPhone 11.

### Phase 3: подтверждено на реальном устройстве

iPhone 11, iOS 26.3.1, 2026-05-26. Треки hitech-psytrance 192/200/207 BPM, комнатный микрофон (~1 м). Детектировано ~187–196 BPM, уровень -10 до -12 dBFS, lock_state `LOCKING` при 52–62% уверенности. Пайплайн конца в конец подтверждён работающим; точность ±5–8 BPM через комнатный микрофон — Phase 4 задача.

---

### Changed (translations)
- Полный перевод человекочитаемой поверхности репозитория на русский: документация (`docs/`, корневые `README.md`, `AGENTS.md`, `CLAUDE.md`), все per-module `README.md`, `CHANGELOG.md`, тела субагентов и навыков `.claude/agents/*.md`, `.claude/skills/*/SKILL.md`, `.claude/commands/*.md`, UI-строки в `apps/mobile/lib/`, `NSMicrophoneUsageDescription` в `apps/mobile/ios/Runner/Info.plist`, комментарии в Rust / Python / Dart / JS-коде. Идентификаторы, JSON-ключи контракта, значения enum `LockState`, имена фикстур, лог-сообщения и slash-команды остались английскими — поведение и тесты сохраняются. Глоссарий: `docs/GLOSSARY.md`. План: `docs/plans/translations-russian.md`.

### Added
- Phase 3 мобильный мост (шаг 2 — платформенные файлы, захват микрофона, живой UI):
  - `apps/mobile/android/` + `apps/mobile/ios/` сгенерированы через `flutter create --platforms=android,ios .` с org `dev.hitech.bpmradar`. Существующий Dart-код сохранён.
  - `AndroidManifest.xml` объявляет `<uses-permission android:name="android.permission.RECORD_AUDIO" />`.
  - `ios/Runner/Info.plist` объявляет `NSMicrophoneUsageDescription` с человекочитаемым текстом для пользователя («Hitech BPM Radar слушает через микрофон, чтобы определить BPM окружающей музыки. Аудио остаётся на вашем устройстве и нигде не записывается и не отправляется.»).
  - `apps/mobile/lib/capture/`:
    - `microphone_source.dart` — тонкая оболочка над `package:record` 5.x, открывает PCM16 моно 48 кГц через `startStream()`.
    - `dsp_worker.dart` — точка входа изолята, владеет FFI-хэндлом, декодирует PCM16 → Float32 через `s / 32768.0`, вызывает `DspEngine.pushSamples`, опрашивает `engine.analyzeJson()` на UI-частоте (по умолчанию 20 Гц), форвардит raw JSON в основной изолят.
    - `capture_bridge.dart` — оркестратор основного изолята. Поднимает воркер, форвардит `PushPcm`-сообщения через `SendPort`, переэмитит распарсенный `DspResult` в broadcast-стрим и `CaptureError` в стрим ошибок. UI никогда не видит сырых байтов.
    - `capture_messages.dart` — типизированные конверты сообщений (`WorkerInit`, `PushPcm`, `ResetEngine`, `StopWorker`, `DspResultMessage`, `WorkerReady`, `WorkerError`).
  - `apps/mobile/lib/permissions/permission_gate.dart` — обёртка над `package:permission_handler`. Запрашивает `Permission.microphone`, перепроверяет на resume приложения, поэтому возврат из системных настроек переключает состояние автоматически.
  - `ios/Runner/Info.plist` объявляет `NSMicrophoneUsageDescription` с человекочитаемой копией.
  - `apps/mobile/lib/ui/`:
    - `main_screen.dart` — `StreamBuilder<DspResult>`, рендерит основной BPM (с плейсхолдером `— —` при null, никогда не догадка), процент уверенности + бар, бейдж состояния захвата, метр качества сигнала в dBFS, чип клиппинга и спарклайн недавнего BPM.
    - `debug_screen.dart` — тот же стрим, раскладывает полный список кандидатов с relation-лейблами (`main`, `raw`, `half_time`, `double_time`, `normalized_from_*`), score, `source_bpm`, каждое поле `signal_quality` и метрики тайминга. Half- и double-time-кандидаты всегда видимы.
    - `permission_denied_screen.dart` — экран-объяснение с `openAppSettings()` deep-link на permanent denial, кнопкой мягкого re-prompt'а в остальных случаях.
  - `apps/mobile/lib/main.dart` перепроводка: `PermissionGate` → `_LiveCaptureScaffold` владеет `CaptureBridge` + `MicrophoneSource` на время жизни экрана; ошибки старта захвата всплывают как помеченный экран ошибки, никогда как синтетический fallback.
  - `apps/mobile/lib/dsp/engine.dart` — добавлен аксессор `String analyzeJson()`, чтобы воркер форвардил raw JSON без промежуточного декода.
  - `apps/mobile/test/widget_test.dart` — 7 widget-тестов, покрывающих: рендер живого `STABLE` из синтетического снэпшота, баннер ошибки захвата из стрима ошибок, видимость кандидатов на отладочном экране (main + half_time), debug-screen в режиме ожидания, `SEARCHING` никогда не показывает выдуманный BPM, копию settings на permanent denial, кнопку повтора на soft denial.
- Новые Flutter-зависимости (обоснованные):
  - `record: ^5.1.2` — pure-Dart захват микрофона с `startStream()` PCM-байтовым стримом на Android / iOS / macOS / Linux / Web. Избавляет от написания кастомных platform channels.
  - `permission_handler: ^11.3.1` — runtime-запрос разрешения + `openAppSettings()` deep-link.

### Changed
- `docs/MOBILE_AUDIO.md` переписан под конкретный пайплайн: выбор пакета, изолятная модель, таблица формата кадров по платформам, политика задержки, anti-fake-гарантии.
- Секция `apps/mobile` в `docs/ARCHITECTURE.md` обновлена с «будущей границы» на живую Flutter-раскладку (`lib/dsp/`, `lib/capture/`, `lib/permissions/`, `lib/ui/`).
- `README.md` — Текущая фаза + инструкции «Как запустить мобильное приложение»; ссылается на новый чек-лист ручных тестов.

### Added
- `docs/MANUAL_TEST_CHECKLIST.md` — приёмка на уровне устройства: сборка / запуск, сценарий разрешения (grant / soft deny / permanent deny + возврат из settings), живой захват против эталонного 200 BPM, проверки тишины + клиппинга + half-time-ловушки, содержание отладочного экрана, выдерживание 60 с плавности.

- Phase 3 мобильный мост (шаг 1 — FFI-binding и DSP-обёртка, ещё без микрофона):
  - `core/ffi/include/hitech_bpm_ffi.h` — публичный C ABI-заголовок; единственный источник истины для `ffigen` и любого нативного потребителя.
  - `apps/mobile/lib/dsp/bindings.dart` — Dart FFI-биндинги для `hitech_bpm_engine_*` и `hitech_bpm_string_free`. Закоммичены руками, но регенерируются через `ffigen:`-конфиг в `apps/mobile/pubspec.yaml`, чтобы контрибьюторам не нужен был локальный libclang только ради сборки.
  - `apps/mobile/lib/dsp/dsp_result.dart` — типизированный взгляд на JSON `DspResult` (enum LockState, SignalQuality, TempoCandidate, DspTiming). Парсит, что решил Rust; никакой BPM-математики.
  - `apps/mobile/lib/dsp/engine.dart` — обёртка `DspEngine`, владеет нативным хэндлом, маршалит `Float32List` PCM в pinned-нативную память, опрашивает `analyze_json` на таймере UI-частоты (по умолчанию 50 мс) и выставляет распарсенные снэпшоты в broadcast-`Stream<DspResult>`. Захват микрофона — следующий патч; пока вызывающий (тест или будущий аудио-мост) поставляет PCM.
  - `apps/mobile/test/dsp_engine_test.dart` — Flutter-тест, собирает `libhitech_bpm_ffi` через `cargo build --release -p hitech-bpm-ffi`, прогоняет 13 с синтетического 200 BPM PCM через Dart-биндинг и проверяет `lock_state == STABLE`, `primary_bpm` в пределах ±2 BPM, видимость half-time-кандидата и что 14 с тишины никогда не достигают `STABLE`. Также проверяет, что broadcast-стрим эмитит распарсенные снэпшоты, пока есть подписка.
  - `apps/mobile/test/helpers/native_library.dart` — находит / собирает workspace-dylib, чтобы Flutter-тест-слой прогонял тот же Rust DSP, который продакшен-приложение будет загружать.
  - `apps/mobile/test/helpers/synthetic_pulse.dart` — детерминированный генератор kick'а на 200 BPM, зеркалирующий `core/ffi/tests/ffi_contract.rs::pulse_200_bpm`.
- Новые Flutter-зависимости (обоснованные):
  - `ffi: ^2.1.0` — требуется для аллокации `Pointer<Float>` при передаче PCM-кадров в Rust.
  - `ffigen: ^13.0.0` (dev) — регенерирует `bindings.dart` из C-заголовка, когда ABI развивается.

- Граница FFI `analyze`: `hitech_bpm_engine_analyze_json` возвращает текущий скользящий `DspResult` как heap-owned UTF-8 JSON C-строку; `hitech_bpm_string_free` освобождает её. Flutter / нативные потребители теперь могут читать темп, уверенность, состояние захвата, качество сигнала и полный список кандидатов без владения параллельной BPM-имплементацией. JSON пересекает границу на UI-частоте опроса (~10–30 Гц); аудио-поток продолжает вызывать только `push_samples`, который остаётся легковесным по аллокациям.
- `core/ffi/tests/ffi_contract.rs` прогоняет `push_samples` + `analyze_json` end-to-end через C ABI на чистом пульсе 200 BPM, на тишине и на null-хэндле. Проверяет форму JSON, захват `STABLE` на 13 с чистого сигнала, primary_bpm в пределах ±2 BPM, видимость half-time-кандидата и anti-fake-гейт того, что тишина никогда не достигает `STABLE`.
- Phase 2 потоковое DSP-ядро — `DspEngine` теперь держит **скользящую историю онсетов**: `pcm_window`, `pcm_pending`, `onset_history` и `prev_frame_rms`. На каждом `push_samples` только *новая* PCM-область конвертируется в spectral-flux-кадры и аппендится в ограниченное onset-кольцо; самые старые записи сбрасываются с хвоста. CPU-стоимость на push не зависит от длительности стрима.
- Общий пост-онсетный пайплайн `analyze_from_envelope`, используемый и пакетным `analyze_pcm`, и потоковым `DspEngine::analyze`, поэтому оба пути выдают эквивалентные установившиеся снэпшоты `DspResult`.
- Три новых Rust-теста streaming в `core/dsp/tests/streaming.rs`:
  - `streaming_first_lock_under_six_seconds_for_200_bpm` — движок покидает `SEARCHING` в пределах `lock_min_seconds` на чистом пульсе 200 BPM.
  - `streaming_stable_lock_under_twelve_seconds_for_200_bpm` — движок достигает `STABLE` с `primary_bpm` в пределах ±2 BPM за `stable_min_seconds`.
  - `streaming_reflects_mid_stream_tempo_change_within_one_window` — 12 с 180 BPM, конкатенированных с 12 с 200 BPM; движок захватывает 180, проходит через не-`STABLE`-состояние во время изменения и догоняет ~200 BPM в пределах одного окна анализа. Доказывает, что движок не подменяет молча один темп другим, оставаясь `STABLE`.
- `core/dsp/tests/streaming_perf.rs` (`--ignored`) — release-режим, тайминг-обвязка для `push_samples` + `analyze` на 60-секундном стриме чанками по 100 мс, проверяет верхнюю границу 200 мс на push.

### Changed
- `DspEngine` теперь pre-sizes свои кольца из `DspConfig` в `new()`. Публичное API не изменилось: `new`, `config`, `push_samples`, `analyze`, `analyze_raw_candidates` и `reset` сохраняют существующие сигнатуры.
- `docs/DSP_ALGORITHM.md` документирует скользящую историю онсетов и новые streaming-тесты.

### Performance
- `push_samples` (release, чанки 100 мс на 48 кГц): медиана 42µs → **29µs** (−31%), p95 119µs → **50µs** (−58%), max 329µs → **78µs** (−76%).
- `analyze` (release): медиана 2591µs → **1747µs** (−33%), p95 3236µs → **2167µs** (−33%), max 8272µs → **2553µs** (−69%).
- Полная стоимость на чанк (push + analyze): медиана 2633µs → **1776µs** (−33%); max 8601µs → **2631µs** (−69%).

### Ранее в [Unreleased]

- Rust DSP теперь авторитативный продакшен-анализатор. `cargo test --workspace` прогоняется герметично, без сабпроцесса `python3`.
- `core/dsp/tests/common/mod.rs` — общий детерминированный Rust-фикстурный модуль, зеркалирующий `core/tests/helpers/synthetic_fixtures.py`. Покрывает тишину, белый/розовый шум, чистые 170/180/190/200/220, half-time- и double-time-ловушки, сильный и восстановимый клиппинг, брейкдаун, плотный hitech-басс и нестабильную клубную симуляцию.
- Тест `canonical_fixture_inventory_round_trip` в `core/dsp/tests/offline_contract.rs` обходит весь Rust-фикстурный инвентарь и проверяет anti-fake-инварианты.
- `core/dsp/src/bin/analyze_wav.rs` — Rust-CLI, читает 16-битный PCM WAV и эмитит `DspResult` как JSON; используется отдельным parity-инструментом.
- `tools/offline-lab/parity.py` — opt-in кросс-языковая проверка дрифта, запускает Python-анализатор и Rust-бинарник `analyze_wav` на одних и тех же WAV-фикстурах и табулирует pet-фикстурный дрифт в `primary_bpm`, `confidence`, `lock_state` и relation'ах кандидатов.
- `serde` / `serde_json`-derives на публичных DSP-типах результата (`DspResult`, `TempoCandidate`, `SignalQuality` и т.д.), чтобы контракт результата сериализовался в ту же форму JSON, что эмитит Python.

### Changed
- `core/dsp/tests/offline_contract.rs` теперь потребляет общий модуль фикстур `common::*`; дублирующиеся генераторы убраны.
- `docs/DSP_ALGORITHM.md` документирует позицию Rust-as-source-of-truth и parity-рефакторинг (вариант A — без Python-сабпроцесса в `cargo test`).
- `docs/QA_MATRIX.md` добавляет таблицу инвентаря Rust-фикстур и новую команду валидации `parity.py`.
- `README.md` документирует герметичный воркфлоу `cargo test` и опциональную кросс-языковую проверку дрифта `parity.py`.

### Removed
- `core/dsp/tests/python_parity.rs`. Rust-контракт проверяется напрямую в `offline_contract.rs`; кросс-языковое сравнение переехало в отдельный инструмент `tools/offline-lab/parity.py`.

## [0.0.1] - 2026-05-25 (базовая линия offline-DSP-лаборатории Phase 1)

### Added
- Офлайн-DSP-лаборатория Phase 1: генератор синтетических фикстур, Python-референс-анализатор (`core/dsp/tempo.py`), Rust-крейт (`core/dsp/src/lib.rs`), Node-офлайн-анализатор (`core/dsp/index.js`) и детерминированный гейт `tools/offline-lab/offline_lab.py report`.
- Hitech-нормализация кандидатов: raw < 130 BPM эмитит `normalized_from_half`, raw > 260 BPM эмитит `normalized_from_double`; raw, half-time, double-time и нормализованные кандидаты — все сохраняются.
- Автомат состояния захвата, покрывающий `SEARCHING`, `LOCKING`, `STABLE`, `UNSTABLE`, `BREAKDOWN`, `CLIPPED_MIC`, `NOISE_ONLY`.
- Градированная обработка клиппинга: мягкий клиппинг ограничивает уверенность ниже `STABLE`, сохраняя кандидатов видимыми; сильный клиппинг (отношение клиппированных кадров >= 5%) форсит `CLIPPED_MIC` и подавляет `primary_bpm`.
- Штраф за гармоническую неоднозначность, применённый к оценке уверенности, чтобы близкий-второй кандидат проседал финальную уверенность.
- Новая фикстура `recoverable_clipped_200` и строка offline-lab для проверки поведения мягкого клиппинга.
- Parity-тест Rust ↔ Python `core/dsp/tests/python_parity.rs`, прогоняющий Python-анализатор поверх общей фикстурной матрицы.
- Запись QA-матрицы и заметки в DSP-алгоритме для градированного клиппинга и parity-покрытия.

### Notes
- Никакого хардкода BPM в продакшен-путях; тишина, шум-без-сигнала и сильно клиппированные входы возвращают `primary_bpm: null`.
- Half-time- и double-time-кандидаты никогда не скрываются — они остаются в списке кандидатов с relation/source-метаданными.

[Unreleased]: https://github.com/filatelist-hitech/hitech-bpm-radar/compare/main...HEAD
