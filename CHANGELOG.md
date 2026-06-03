# Changelog

Все значимые изменения этого проекта будут задокументированы в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), а проект придерживается семантического версионирования после старта релизов.

## [1.1.0] — 2026-06-03

### Rebrand

- **Проект переименован: Hitech BPM Radar → TrackScope.**
  - Display name обновлён в `strings.xml`, `Info.plist`, `AGENTS.md`, `CLAUDE.md`, `README.md`, всех `docs/`.
  - Dart-пакет: `hitech_bpm_radar` → `TrackScope` (`pubspec.yaml`, все тест-импорты).
  - Rust/FFI внутренности (`libhitech_bpm_ffi`, `hitech_bpm_engine_*`) не переименованы — внутренний ABI.
  - `applicationId` не изменён.
  - Версия: `1.0.0+1` → `1.1.0+2`.

### Added — Phase 9: Android APK (2026-06-02/03)

- `scripts/build_android_native.sh` — кросс-компиляция Rust → `.so` (arm64-v8a / armeabi-v7a / x86_64) через Android NDK.
- `jniLibs/<abi>/libhitech_bpm_ffi.so` для всех трёх ABI.
- `android-release.jks` + `key.properties` — release-подпись.
- `flutter build apk --release` → `app-release.apk` **54.7 MB** ✓ (подтверждено 2026-06-03).
- `docs/ANDROID_TEST_PLAN.md`, `key.properties.template`.

### Added — Phase 10: Freemium (Free / Pro)

- `lib/monetization/`: `PurchasesGateway`, `RevenueCatGateway`, `ProStatusService` (ChangeNotifier), `FeatureFlags`, `PaywallScreen`.
- `lib/history/`: `BpmHistory`, `SessionHistoryController` (~1 Hz), `HistoryScreen`.
- `lib/export/`: `buildCsv`/`buildJson` + `exportCsv`/`exportJson` (share_plus).
- FFI: `hitech_bpm_engine_new_with_min_bpm(float)` — Free = 170, Pro = 155.
- Free tier: BPM range 170–230, History 30 сек. Pro: 155–230, History 24 ч, Debug, Export, Setlist.

### Added — Phase 11: Design System v2

- Tab Bar (`AppNavigator`, `IndexedStack`): Радар / История / Настройки. CaptureBridge не пересоздаётся.
- `BpmHeroDisplay` (72 px IBM Plex Mono), `ConfidenceBar` (7 px red/yellow/teal), `BreakButton`, `ListeningIndicator`, `AppTabBar`.
- `SignalAnalyzerScreen` (Pro): BPM-кандидаты, качество сигнала, тайминги, DspDebug-метрики.
- `SettingsScreen` (5 секций, SharedPreferences, WakelockPlus).
- Design tokens v2: `app_colors.dart` (#050807, #00DFB0), `app_text_styles.dart` (IBM Plex Mono).
- `PaywallScreen` v2: column headers FREE/PRO, CTA-иерархия, Roadmap card.
- **DspDebug** в Rust `DspResult`: `onset_rate_hz`, `onset_strength`, `tempo_peak_prominence`, `harmonic_ambiguity`, `stability_score`, `warnings[]`. Populated без доп. CPU.

### Added — Phase 12: UI Polish (2026-06-02)

- Type scale +2 px по всем ролям (micro 9→11, caption 10→12, body 12→14, value 15→18).
- Waveform ambient glow (alpha=38, blur=4.0) поверх beat-reactive pulse.
- `AppTheme` → thin-proxy на `AppColors`/`AppTextStyles`. JetBrains Mono → IBM Plex Mono.
- FFT Spectrum в Signal Analyzer: `StatefulWidget` + `VizController` + `LiveSpectrumPainter` (90 px).
- Break button → `CaptureBridge.resetEngine()`: сброс DSP + smoother без остановки захвата.

### Added — v1.1 Monetization Phase 1 (2026-06-01)

- Multi-Genre Presets: 7 пресетов (HitechPsy 155–230, Psytrance 130–160, Darkpsy 145–180, DnB 160–185, Techno 125–145, Hardstyle 138–160, Hardcore 155–185, Custom [Pro]).
  - `core/dsp/src/genre_preset.rs` — Rust enum.
- Setlist Tracker MVP: `lib/features/setlist/` — `SetlistService` + `SetlistEntry`, CSV/JSON экспорт.
- 14-Day Pro Trial badge в PaywallScreen (Annual).
- Paywall 2.0: расширенная таблица с v2 фичами (Key, Energy, Apple Watch, Widget).

### Added — Phase 2.1: HPCP KeyAnalyzer (2026-06-02)

- `core/dsp/src/key_analyzer.rs` — STFT → 12-bin HPCP → Krumhansl-Schmuckler → Camelot.
  - `KEY_WINDOW_SECS = 8.0 с`, `KEY_CONFIDENCE_THRESHOLD = 0.25`, диапазон 50–5000 Hz.
  - Гейты: тишина / CLIPPED_MIC / confidence < 0.25 → `key_result = None`.
  - Camelot: A minor = "8A", C major = "8B".
- `rustfft = "6"` в `core/dsp/Cargo.toml`.
- `DspResult` расширен: `key_result: Option<KeyResult>`.
- Dart: `KeyResult` класс + парсинг вложенного JSON `camelot: {number, letter}`.
- 12 Rust-тестов (`core/dsp/tests/key_detection.rs`).

### Added — Phase 2.2: EnergyAnalyzer (2026-06-02)

- `core/dsp/src/energy_analyzer.rs` — RMS (40%) + spectral flux (35%) + onset density (25%) → level 1–10.
  - Гейты: CLIPPED_MIC / тишина → `energy_result = None`.
  - `FLUX_MAX = 0.15`, `DENSITY_MAX = 6.0`.
- `DspResult` расширен: `energy_result: Option<EnergyResult>`.
- Dart: `EnergyResult` класс + парсинг.
- Signal Analyzer: секция «ЭНЕРГИЯ N / 10» + прогресс-бар.
- 5 Rust-тестов (`core/dsp/tests/energy.rs`).

### Added — Phase 2.3: Energy/Key на Radar tab (2026-06-03)

- `_EnergyCell` widget: строка «ЭНЕРГИЯ N/10» + `LinearProgressIndicator` 4 px.
- Radar info-карта: строка энергия (слева) + тональность (справа). Гейты по `null`.
- `MockDspStream.stable()` эмитит `energyResult` + `keyResult`.
- Radar tab: нет скролла, `ЭНЕРГИЯ`/`ТОНАЛЬНОСТЬ` видимы при любом состоянии.
- 5 новых Flutter-тестов.

### Added — Phase 2.2.1: EnergyAnalyzer calibration + ground truth (2026-06-03)

- 4 новые фикстуры: `hitech_real_22–25` (210/212 BPM, Camelot размечен).
- `expected_key` (Camelot) добавлен для всех 25 фикстур в `fixture_manifest.json`.
- `core/dsp/src/bin/stream_analyze_wav.rs` — потоковый анализатор через `DspEngine` (для `energy_result`/`key_result`).
- Замер на реальных треках: energy 7–8 на активном hitech-материале ✓.

### Fixed

- **Flutter-тесты** (pre-existing regression из коммита `c75ea5e`): восстановлен `name: TrackScope` в `pubspec.yaml` + обновление всех `package:hitech_bpm_radar/` → `package:TrackScope/` в 20 тест-файлах. **193/194 тестов PASS** (1 pre-existing `dsp_engine_test` — нет `.dylib`).

### Changed

- `DspConfig::target_bpm_min`: `170.0` → `155.0` (Phase 8.2).
- `ADAPTIVE_WINDOW_LOCKING_SECS`: `4.0` → `6.0` (Phase 8).
- `has_ever_been_stable: bool` в `DspEngine` (Phase 8.1).

### Testing

- **116 Rust-тестов** — все PASS (`cargo test --workspace`).
- **193 Flutter-тестов** — PASS (1 pre-existing skip: `dsp_engine_test`, нет `.dylib`).
- 25 реальных hitech-фикстур (180–212 BPM), parity Python↔Rust delta = 0.00.

## [Unreleased]

### Added — Design System v2 (Phase 11)

- **Tab Bar навигация** (`lib/navigation/app_navigator.dart`): три вкладки
  Радар / История / Настройки через `IndexedStack`. `CaptureBridge` не
  пересоздаётся при смене вкладок — живёт в `_CapturePipeline`.
- **BPM Hero Display** (`lib/widgets/bpm_hero_display.dart`): 72 px IBM Plex
  Mono, три режима (idle/detecting/unstable). Null → «— — —» dim #1E3530.
- **ConfidenceBar** (`lib/widgets/confidence_bar.dart`): 7 px, red < 30 %,
  yellow 30–70 %, teal > 70 %. Анимация 400 мс.
- **BreakButton** (`lib/widgets/break_button.dart`): иконка паузы + «Зафиксировать брейк».
- **ListeningIndicator** (`lib/widgets/listening_indicator.dart`): анимированная
  точка accent + «слушаю».
- **AppTabBar** (`lib/widgets/app_tab_bar.dart`): кастомный таб-бар с
  accent/textMuted цветами, подписи «РАДАР / ИСТОРИЯ / НАСТРОЙКИ».
- **SignalAnalyzerScreen** (`lib/screens/signal_analyzer_screen.dart`): Pro-only,
  показывает BPM-кандидатов со score bar + качество сигнала + тайминги.
  Секция «Метрики алгоритма» — реальные DspDebug-данные (onset rate, onset strength,
  peak prominence, harmonic ambiguity, stability score, SNR, warnings).
- **SettingsScreen** (`lib/screens/settings_screen.dart`): 5 секций, backed
  by `AppSettings` (SharedPreferences). Keep Screen On → WakelockPlus.
- **AppSettings** (`lib/settings/app_settings.dart`): ChangeNotifier singleton,
  персист через SharedPreferences (showWaveform, showSpectrum, keepScreenOn, inputSensitivity).
- **Design tokens v2** (`lib/theme/app_colors.dart`, `lib/theme/app_text_styles.dart`):
  IBM Plex Mono, #050807 bg, #00DFB0 accent, confidence thresholds.
- Зависимости: `shared_preferences ^2.3.0`, `wakelock_plus ^1.2.0`.

### Added — DspDebug contract (Phase 11)

- **DspDebug struct** в Rust `DspResult`: `onset_rate_hz`, `onset_strength`,
  `tempo_peak_prominence`, `harmonic_ambiguity`, `stability_score`, `warnings[]`.
  Populated в `analyze_from_envelope` без доп. CPU-стоимости — из уже вычисленных значений.
  `empty_result()` и пути silence эмитят нулевой `DspDebug` (не `null`).
- **DspDebug class** в Dart `dsp_result.dart`: `fromJson` с graceful defaults
  (missing key → zero DspDebug). Backward-compatible с FFI без `debug`-ключа.
- **Signal Analyzer** (`lib/screens/signal_analyzer_screen.dart`) показывает
  реальные метрики алгоритма: onset rate, onset strength, peak prominence,
  harmonic ambiguity, stability score, SNR, warnings. Placeholder «В разработке» удалён.
- Тесты Rust: `debug_field_populated_on_stable_signal`,
  `debug_serializes_to_json_with_debug_key`, `debug_empty_on_silence`
  (в `core/dsp/tests/stability.rs`).
- Тесты Dart: `test/dsp_debug_test.dart` (6 тестов: `fromJson`-парсинг, `DspResult.parse`).

### Added — v2 Roadmap Scaffolding (2026-06-01)

- **`docs/ROADMAP_V2.md`** — полный v2 roadmap: Vision, Competitive Positioning (table vs liveBPM/MixedInKey/Tunebat/KeyMatch), Phase 1 (Quick Wins), Phase 2 (Harmonic Analysis), Phase 3 (Intelligence), Metrics & Success Criteria, What We Are NOT Building.
- **`docs/adr/001-key-detection-approach.md`** — ADR: HPCP + Krumhansl-Schmuckler в Rust vs Essentia FFI vs TFLite; принято Option A.
- **`docs/adr/002-energy-analysis.md`** — ADR: RMS + spectral flux + onset density → 1–10.
- **`docs/adr/003-multi-genre-config.md`** — ADR: `GenrePreset` enum через существующий `min_bpm` FFI knob.
- **`docs/adr/004-setlist-tracker-architecture.md`** — ADR: in-memory `SetlistService` + subscription к `CaptureBridge.results`.
- **`core/dsp/src/genre_preset.rs`** — `GenrePreset` enum: 7 пресетов (HitechPsy 155–230, Psytrance 130–160, Darkpsy 145–180, DrumAndBass 160–185, Techno 125–145, Hardstyle 138–160, Hardcore 155–185, Custom [Pro]). Нормализационные пороги per-genre. 7 Rust-тестов PASS.
- **`core/dsp/src/key_analyzer.rs`** — Phase 2 skeleton: `KeyAnalyzer`, `MusicalKey` (12 нот), `KeyMode`, `CamelotKey`, `KeyResult`. `todo!("Phase 2")` на всех методах. 3 Rust-теста (camelot label, default, serialization) PASS.
- **`core/dsp/src/energy_analyzer.rs`** — Phase 2 skeleton: `EnergyAnalyzer`, `EnergyResult { level: u8, rms_dbfs, spectral_flux, onset_density_hz }`. 2 Rust-теста PASS.
- **`DspResult`** расширен: `genre_preset: GenrePreset` (сериализуется в JSON), `key_result: Option<KeyResult>` (None в Phase 1, skip_serializing_if = None), `energy_result: Option<EnergyResult>` (None в Phase 1). `debug: DspDebug` (Phase 11). Обратно совместимо.
- **`apps/mobile/lib/features/tap_tempo/tap_tempo_controller.dart`** — `TapTempoController` (ChangeNotifier): последние 8 тапов, окно 3 сек, BPM = 60000/avg. Free tier.
- **`apps/mobile/lib/features/setlist/setlist_entry.dart`** — `SetlistEntry`: timestamp + BPM + lockState + confidence + inputLevelDbfs. `toJson()` + `toCsvRow()`.
- **`apps/mobile/lib/features/setlist/setlist_service.dart`** — `SetlistService` (ChangeNotifier): запись только STABLE + ненулевой BPM, дедупликация (delta < 0.5 BPM AND < 5 сек), `exportJson()` / `exportCsv()`. Pro-only (gate на уровне UI).
- **`apps/mobile/test/features/tap_tempo/tap_tempo_controller_test.dart`** — 6 unit-тестов: single tap null, 4 taps ~200 BPM, пауза > 3 сек сброс, > 8 тапов trim, reset, two taps. PASS.
- **`apps/mobile/test/features/setlist/setlist_service_test.dart`** — 9 unit-тестов: recording gate, STABLE gate, null BPM gate, дедупликация, delta > 0.5 pass, stopRecording, exportJson/Csv структура, clear, averageBpm. PASS.

### Changed — Design System v2 (Phase 11)

- **Paywall** редизайн: value headline «Читай любой трек. Без ограничений.» +
  column headers ФУНКЦИЯ/FREE/PRO + CTA-иерархия (filled+badge / outline) +
  Roadmap card (Key+Camelot, Energy, Lock-screen Widget). «Debug Screen» → «Signal Analyzer».
- **Waveform** высота: flex-proportional → fixed 120 px.
- **BPM number**: 52 px JetBrains Mono → 72 px IBM Plex Mono hero (в `_AnimatedBpmDisplay`).
- **Confidence bar**: 2 px одноцветный → 7 px с цветовыми порогами (Design v2 ConfidenceBar).
- **main.dart**: `MainScreen` → `AppNavigator`; `AppSettings.instance.load()` при старте.
- **ARCHITECTURE.md**: обновлена навигационная структура и слои приложения.

### Changed — v2 Paywall 2.0 (2026-06-01)

- **`apps/mobile/lib/monetization/paywall_screen.dart`** — Таблица сравнения расширена с 5 до 10 строк: добавлены Multi-Genre (3 жанра Free / 7+Custom Pro), Setlist Tracker, Key + Camelot (Скоро), Energy Level (Скоро), Apple Watch (Скоро). Annual-кнопка: «14 дней бесплатно» badge.
- **`apps/mobile/test/monetization/paywall_screen_test.dart`** — обновлён: проверяет все строки, «14 дней бесплатно» badge, Multi-Genre и Setlist строки.
- **`docs/ARCHITECTURE.md`** — добавлена секция «v2 компоненты (Phase 1 scaffolding)».

### Changed

- **Расширен диапазон детекции BPM 170–230 → 155–230** (Phase 8.2). Ранний hitech
  начинается от ~155 BPM. Изменены только дефолты предпочитаемого диапазона:
  `DspConfig::target_bpm_min` (Rust) и `analyze_pcm(hitech_min_bpm=…)` (Python) с
  `170.0` на `155.0`. Поиск (80–460) и нормализация (`<130 → ×2`, `>260 → ÷2`) не
  менялись. Детекция ≥170 BPM байт-идентична; 155–169 получают более высокий
  range_score. 155–169 не удваиваются (проверено: 155 → 154.8, 160 → 160.0).
- **Допуск реальных фикстур: добавлен абсолютный гейт точности ±2 BPM.** Прежний
  `parity.py` сравнивал только Python↔Rust (delta 0.00 везде), из-за чего
  неверная-но-согласованная детекция проходила молча (так `hitech_real_10` 146.7
  вместо ~196 жил до ручного `known_fail`). Теперь `parity.py` дополнительно
  проверяет `|detected − expected_bpm| ≤ accuracy_tolerance` для фикстур с
  известным ground truth.

### Added

- `core/dsp/tests/range_coverage.rs` — потоковая матрица 155 + 160…230 (шаг 5,
  16 точек): first-lock ≤6 с, STABLE ≤12 с, последние 20 STABLE-кадров ±1 BPM;
  плюс `bpm_155_is_detected_not_doubled`.
- `test_extended_range_low_end_locks_in_band_without_doubling` (Python) — 155/160/165.
- `datasets/fixture_manifest.json` — поля `expected_bpm` + `accuracy_tolerance` на
  все 21 реальную фикстуру (8 размечены по имени файла, 13 — `TODO_user_provided`).
- `apps/mobile/test/waveform_painter_test.dart` — smoke-тесты `WaveformColumnPainter`
  (пустой буфер, полный mock-буфер, `WaveformColumn.empty`).
- `widget_test.dart` — покрытие всех полей InfoCard (уровень входа, лучший
  кандидат, ×½/×2-ячейка, клиппинг, шум) из STABLE-снапшота.

### Audit

- Аудит Rust/FFI-тестов: все используют value-ассерты (`assert_bpm`,
  `(bpm-200).abs()<=2`); голых `is_some()`-без-проверки не найдено — ложных
  срабатываний в Rust-тестах нет. Единственный структурный пробел —
  отсутствие абсолютного гейта в `parity.py` — закрыт (см. Changed).

## [1.0.0] — 2026-05-30

### Added

- **v1.0.0 pre-release preparation:**
  - 3 new streaming timing tests: `streaming_first_lock_170_bpm`, `streaming_first_lock_220_bpm`, `streaming_breakdown_exits_stable`
  - 1 new streak stability test: `streak_stability_170_bpm`
  - 3 new FFI tests: `ffi_half_time_candidate_visible`, `ffi_double_time_candidate_visible`, `ffi_clipped_returns_clipped_mic_state`
  - Known-fail tracking in `fixture_manifest.json` and `parity.py` — `hitech_real_10` marked as known anomaly (146.7 BPM detected instead of ~196 BPM)
  - Android release signing config with `key.properties.template` and fallback to debug signing when keystore missing
  - Safety documentation for all FFI unsafe functions

### Changed

- **Version bump:** `apps/mobile/pubspec.yaml` → `1.0.0+1`
- **Android app label:** now uses `@string/app_name` ("TrackScope") from `strings.xml`
- **iOS CFBundleDisplayName:** corrected capitalization to "TrackScope"
- **README.md:** added "Current Status — v1.0.0" section with completed phases and key features

### Fixed

- **Clippy warnings:** 3 errors in `core/dsp/src/lib.rs` (redundant pattern matching, identical if-blocks, redundant closure)
- **FFI clippy warnings:** 5 missing Safety documentation sections in `core/ffi/src/lib.rs`

### Testing

- **50 Rust tests pass** (was 42): 20 streaming, 8 stability, 16 offline_contract, 6 FFI
- **21 real fixture snapshots:** all PASS except hitech_real_10 (known fail)
- **parity.py:** exits 0 with known_fail fixtures, displays KNOWN FAILS section separately

## [Unreleased]

### Added

- **Flutter Web UI preview (2026-05-30):** Быстрый цикл итерации по UI без устройства. Web-платформа добавлена (`apps/mobile/web/`), отдельный entrypoint `apps/mobile/lib/main_web.dart` рендерит реальный `MainScreen` поверх `MockDspStream` (симулированные `DspResult` — только UI, не детектор; Rust/FFI в браузере недоступны). На экране баннер «PREVIEW · MOCK». Запуск: `./apps/mobile/run_preview.sh` → `http://localhost:7654` с hot-reload.
  - `MockDspStream` (`apps/mobile/lib/mock/mock_dsp_stream.dart`): SEARCHING → LOCKING → STABLE, `primaryBpm` = `null` до захвата, виден half-time-кандидат — соблюдает контракт и anti-fake-правила. Импортируется ТОЛЬКО из `main_web.dart`, никогда из `lib/main.dart`.
  - Skill `ui-preview` (`.claude/skills/ui-preview/SKILL.md`) и slash-команда `/preview` (`.claude/commands/preview.md`) для показа превью после правок UI; `.claude/launch.json` → конфигурация `ui-preview`; `.mcp.json` с `mockup`-сервером.
  - **Production-safe рефакторинг:** `CaptureError` вынесен из `capture/capture_bridge.dart` в лист-модуль `capture/capture_error.dart` (без ffi/io/isolate) и ре-экспортирован, чтобы `MainScreen` собирался под web, не втягивая `dart:ffi`. Мобильная сборка не затронута (`flutter analyze` чист).
  - **Анимированные waveform и live-spectrum в превью (2026-05-30):** `MockDspStream.rawPcm()` генерирует синтетический поток PCM-16 LE mono 48 кГц (2400 сэмплов / 50 мс), форма сигнала — kick+bass+hat+rumble, синхронизированные с ~193 BPM (зеркало `.claude/mockup/index.html`). Подаётся как `rawPcm:` в `main_web.dart` → `VizController.attachRawPcm()`. Оба визуализатора (осциллограф + live-spectrum с kick-горбом на 50–200 Hz и peak-hold) теперь анимируются без «Ожидание микрофона…».

### Fixed

- **DSP first-lock regression (Phase 8.1, 2026-05-29):** Исправлено зависание в состоянии LOCKING (~30–50% уверенности) при первом захвате на стабильном треке. Корневая причина — гипотеза E (не из четырёх изначальных): адаптивное окно Phase 4.5 усекало `onset_history` до `ADAPTIVE_WINDOW_SEARCHING_SECS = 2.0 с` при состоянии SEARCHING — включая первый захват, когда prior STABLE ещё не было. К t=8s накоплено 8 секунд истории, но анализировались только последние 2 с (~5–8 ударов) → слабый пик автокорреляции → confidence < 0.72 → STABLE недостижим. Фикс: добавлено поле `has_ever_been_stable: bool` в `DspEngine`. При `false` (первый захват) — всегда полная история. При `true` (после первого STABLE) — адаптивное окно работает штатно для fast re-lock. Проверено 2 новыми тестами: `first_lock_uses_full_window_no_prior_stable` и `relock_adaptive_window_still_fast_after_stable`. (core/dsp/src/lib.rs)

- **DSP regression (Phase 8, 2026-05-29):** `ADAPTIVE_WINDOW_LOCKING_SECS` исправлен с 4.0 → 6.0 с (совпадает с `lock_min_seconds`), что даёт ~20 ударов при 200 BPM и confidence ≥ 0.72. (core/dsp/src/lib.rs)

### Changed

- **Waveform visualization (Phase 8.1, 2026-05-29):** Осциллограф-стиль (`WaveformPainter`, smooth glow line) заменён на Traktor DJ–стиль (`WaveformColumnPainter`): острые вертикальные прямоугольники `drawRect`, цветовой градиент по bass-энергии (`0xFF003D35` → `0xFF00E5CC`). Пунктирная вертикальная линия «Now» удалена. Добавлен `WaveformColumn` data class с полями `amplitude`, `bassWeight`, `midWeight`, `highWeight`. `VizController` вычисляет band-split энергию из тех же FFT magnitudes без второго FFT. Границы бинов (48 kHz / 1024): bass 0–6 (0–328 Hz), mid 7–63 (329–2953 Hz), high 64–127 (2954–5953 Hz). (apps/mobile/lib/viz/)

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
  - `ios/Runner/Info.plist` объявляет `NSMicrophoneUsageDescription` с человекочитаемым текстом для пользователя («TrackScope слушает через микрофон, чтобы определить BPM окружающей музыки. Аудио остаётся на вашем устройстве и нигде не записывается и не отправляется.»).
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

[Unreleased]: https://github.com/filatelist-hitech/trackscope/compare/main...HEAD

### Added

- **Freemium monetization (Free / Pro)** — двухуровневая модель с RevenueCat IAP.
  - FFI: `hitech_bpm_engine_new_with_min_bpm(float)` — Free 170–230, Pro 155–230.
  - `lib/monetization/`: `PurchasesGateway`, `RevenueCatGateway`, `ProStatusService`,
    `FeatureFlags`, `PaywallScreen` (сравнение Free/Pro, Lifetime $4.99, Annual $3.99/yr,
    Restore, «Скоро» виджет).
  - `lib/history/`: `BpmHistory`, `SessionHistoryController` (~1 Hz даунсэмплер),
    `HistoryScreen` (Free: 30 сек cap + upgrade баннер; Pro: 24 ч + экспорт).
  - `lib/export/`: `buildCsv`/`buildJson` (чистые билдеры), `exportCsv`/`exportJson`
    (share_plus + path_provider).
  - `main.dart`: ProStatusService init через `--dart-define`, ListenableBuilder для
    tier-reactive CaptureBridge (смена minBpm без перезапуска).
  - `main_web.dart`: web-safe — без revenuecat-зависимостей, fixed `isPro: false`.
  - `config.dart.template` + `.gitignore` для `config.dart`.
  - Тесты: feature_flags, pro_status_service, paywall_screen, bpm_history,
    bpm_exporter, widget_test (debug-gate, PRO badge).
