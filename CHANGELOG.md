# Changelog

Все значимые изменения этого проекта будут задокументированы в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), а проект придерживается семантического версионирования после старта релизов.

## [Unreleased]

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
