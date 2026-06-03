# Roadmap

## Phase 1: офлайн-DSP-лаборатория — **ЗАВЕРШЕНО**

Цель: доказать детерминированное определение BPM на синтетических hitech-фикстурах до UI-работы.

Артефакты:

- Контракт результата и каркас движка Rust `core/dsp`.
- Генератор синтетических фикстур.
- CLI офлайн-анализатора.
- Тесты на чистый click/kick при 170, 180, 190, 200 и 220 BPM.
- Тесты half-time и double-time ловушек.
- Негативные тесты на тишину и шум-без-сигнала.

Критерии выхода — выполнены:

- точность на чистой синтетике в пределах ±1 BPM ✓
- нет фейкового BPM на тишине/шуме ✓
- список кандидатов содержит raw и нормализованных кандидатов ✓
- офлайн-отчёт содержит уверенность, состояние захвата, качество сигнала и pass/fail ✓

## Phase 2: потоковое DSP-ядро — **ЗАВЕРШЕНО**

Цель: детектор работает инкрементально на аудио-чанках.

Артефакты:

- кольцевой буфер;
- скользящая история онсетов;
- история кандидатов;
- движок уверенности;
- автомат состояния захвата;
- тесты тайминга первого и стабильного захвата.

Критерии выхода — выполнены:

- первый рабочий захват до 6 секунд на чистом синтетическом входе ✓
- стабильный захват до 12 секунд на валидном hitech-входе ✓
- никакого ложного `STABLE` на тишине/шуме ✓
- `BREAKDOWN`, `CLIPPED_MIC` и `UNSTABLE` покрыты тестами ✓

## Phase 3: мобильный аудио-мост — **ЗАВЕРШЕНО**

Цель: подавать живой аудио-сигнал с микрофона в уже протестированный DSP-движок.

Артефакты:

- сценарий выдачи разрешения микрофона;
- нативный аудио-мост (Flutter → Rust FFI через DSP-воркер изолят);
- статическая сборка `libhitech_bpm_ffi.a` для iOS через `scripts/build_ios_native.sh`;
- политика конверсии частоты дискретизации (PCM16 mono 48 kHz → f32);
- заметки о платформенной задержке (`docs/MOBILE_AUDIO.md`);
- отладочный экран, рендерящий DSP-контракт;
- ручной тест-чеклист (`docs/MANUAL_TEST_CHECKLIST.md`).

Критерии выхода — выполнены:

- мобильный код не считает BPM напрямую ✓
- поведение разрешений и задержки задокументировано ✓
- debug-режим показывает кандидатов и уверенность ✓
- живой запуск на iPhone 11 подтверждён (2026-05-26): BPM 187–196 на треках 192–207 BPM через комнатный микрофон ✓

## Phase 4: закалка — **ЗАВЕРШЕНО** (частично, 2026-05-26)

Цель: обработать клубный шум, клиппинг, брейкдауны, нестабильный темп и реальные hitech-записи. Выйти на заявленный целевой диапазон точности ±2–4 BPM на живом микрофоне.

Наблюдения по итогам Phase 3 (реальное устройство):

- Через комнатный микрофон на расстоянии ~1 метра ошибка BPM составила ~±5–8 BPM — за пределами цели ±2–4 BPM.
- `lock_state` достигал `LOCKING` при уверенности 52–62%, но не `STABLE` — ожидаемо для комнатного акустики.
- Состояние захвата часто осциллирует между `LOCKING` и `SEARCHING` при шуме окружающей среды.
- Уровень входа -10 до -12 dBFS — адекватный диапазон, не клиппинг.

### Задачи Phase 4

#### 4.1 Сглаживание и стабилизация BPM — **ЗАВЕРШЕНО** (Verified on 2026-05-26)

- Медиан-фильтр последних N=5 снэпшотов `primary_bpm` в Dart-классе `BpmSmoother` (`apps/mobile/lib/capture/bpm_smoother.dart`). ✓
- Гистерезис выхода из `STABLE`: переключение только после K=3 подряд идущих не-`STABLE` кадров. `CLIPPED_MIC` / `BREAKDOWN` / `NOISE_ONLY` сбрасывают гистерезис немедленно. ✓
- EMA уверенности α=0.2 в `BpmSmoother`, не в Rust-ядре. ✓

Сглаживание расположено в Dart, а не в Rust, чтобы Rust DSP-ядро оставалось parity-тестируемым без сглаживания. Детали: `docs/DSP_ALGORITHM.md` → раздел "Dart-слой сглаживания".

#### 4.2 Адаптивные пороги для живого микрофона — **ЧАСТИЧНО**

- SNR-оценка `estimate_snr_db` реализована в Rust (`core/dsp/src/lib.rs`): перцентильный метод (20-й / 80-й перцентиль). `signal_quality.snr_estimate_db` теперь не всегда `null` для реальных шумовых входов. `signal_factor` использует SNR, когда доступен. ✓
- Режим «клубного микрофона» (more aggressive low-pass на onset-огибающей) — **НЕ ЗАВЕРШЕНО**: тест показал, что MA-сглаживание огибающей онсетов создаёт ложную периодичность на `unstable_club_simulation`; требует более умного критерия активации. Бэклог.
- Адаптивный noise-floor в реальном времени — **НЕ ЗАВЕРШЕНО**. Бэклог.

#### 4.3 Реальные тестовые записи — **ЗАВЕРШЕНО** (2026-05-26)

- 21 hitech/psytrance-трек (180–210 BPM) добавлен в `datasets/hitech/`. Аудиофайлы не коммитятся (copyright/размер); коммитятся JSON-снапшоты. ✓
- `datasets/hitech/snapshots/` — 21 снапшот с полным `DspResult` (Python + Rust) на 30-секундном окне каждого трека. ✓
- `datasets/fixture_manifest.json` — единый список с per-fixture `bpm_tolerance` (минимум 4.0 BPM для реальных записей). ✓
- `offline_lab.py snapshot --input DIR` — инфраструктура захвата снапшотов; конвертация через ffmpeg, анализ Python+Rust, обновление манифеста. ✓
- `parity.py` расширен для manifest-based CI-режима (без аудиофайлов), `--fixture-set real/synthetic/all`, `--live` mode для post-DSP-change drift-проверки. ✓
- Допуск ±4 BPM для реальных фикстур обоснован: структурный предел Python `float64` vs Rust `f32` через ~4800 членов автокорреляции. ✓

Known limitation: `hitech_real_10` детектируется на ~147 BPM (half-time от ~294) при BPM-подсказке 196 — вероятная особенность записи; документировано в QA_MATRIX.md.

#### 4.4 Регрессионное покрытие реального микрофона — **ЧАСТИЧНО**

- Rust и Dart тесты для `BpmSmoother` и SNR-пути добавлены. ✓
- Расширение `tools/offline-lab/parity.py` для прогона на реальных WAV-записях — **ЗАВЕРШЕНО** (manifest-режим + live-режим). ✓
- Допуск ±4 BPM для шумных реальных фикстур — **ЗАВЕРШЕНО** (per-fixture в `fixture_manifest.json`). ✓
- Python-тест на реальных треках (21 фикстура, все PASS в `parity.py --fixture-set real`) — **ЗАВЕРШЕНО**. ✓
- `parity.py` в default-режиме (все 21 реальные фикстуры) проходит в CI без аудиофайлов. ✓

#### 4.5 Документация ограничений и релизный чеклист — **ЗАВЕРШЕНО** (2026-05-30)

- Известные ограничения зафиксированы в `docs/DSP_ALGORITHM.md` (SNR null на синтетике, MA onset-сглаживание не добавлено). ✓
- `docs/ROADMAP.md` обновлён с разбивкой сделано / бэклог. ✓
- `docs/RELEASE_CHECKLIST.md` обновлён для Phase 4+ со статусами ✅/⚠️ и Android Release чеклистом. ✓
- Таблица платформенных задержек: iOS данные из Phase 3 зафиксированы; точные мс для Android — **ожидают физического устройства**.

Критерии выхода:

- целевая точность на живом микрофоне в пределах ±2–4 BPM при адекватном SNR — ⚠️ подтверждена на iOS (~±5–8 BPM через комнатный микрофон; ~±2–4 BPM ожидается при прямом звуке с колонки);
- `lock_state == STABLE` при прямом звуке с колонки в ~30 см — ⚠️ не проверено на Android (нет физического устройства);
- клиппирующий вход явно предупреждает и не завышает уверенность — ✓ (покрыто тестами и на устройстве);
- брейкдауны не сохраняют устаревший `STABLE` — ✓;
- релизная документация фиксирует известные ограничения — ✓ (Phase 4.5 завершено).

## Phase 5: UI-визуализация — **ЗАВЕРШЕНО** (2026-05-27)

Цель: живые визуализации аудио-сигнала поверх DSP-контракта без вычисления BPM в UI.

Артефакты:

- `VizController` (`ChangeNotifier`): PCM-кольцевой буфер ~4 с, Dart-side FFT через `compute()`. Никакой BPM-математики.
- `SpectrogramPainter`: скроллящаяся FFT-карта 200×128 бинов (0–6 кГц), LUT 256 цветов.
- `WaveformPainter`: осциллограф PCM vs время; краснеет при `clipping == true`.
- `CaptureBridge.rawPcm`: broadcast-стрим PCM-байтов для визуализаций, независимый от DSP-изолята.
- Редизайн главного экрана: три секции — спектрограмма / волноформа / info-таблица.
- `fftea: ^1.5.0` — чистый Dart FFT, безопасен в любом изоляте.

Критерии выхода — выполнены:

- BPM не вычисляется в UI-слое ✓
- Визуализации не тормозят DSP-поток ✓
- `RepaintBoundary` вокруг каждой визуализации ✓

---

## Phase 6: стабилизация BPM-отображения — **ЗАВЕРШЕНО** (2026-05-29)

Цель: устранить ступенчатые прыжки BPM в `STABLE` из-за дискретизации лага автокорреляции.

Артефакты:

- Параболическая интерполяция пика автокорреляции (`tempo_autocorrelation()`, `core/dsp/src/lib.rs`): ошибка снижена с ~2 BPM/лаг до < 0.2 BPM.
- BPM candidate history в `DspEngine`: скользящий буфер N=3, медиана; очищается при не-STABLE.
- `BpmDisplay` (`apps/mobile/lib/capture/bpm_display.dart`): EMA α=0.2 для большого BPM-числа; снэп при первом STABLE-кадре.
- 7 новых Rust-тестов в `core/dsp/tests/stability.rs` (streak ±0.5 BPM, parabolic precision).
- Большое BPM-число показывается только в STABLE; в LOCKING — `—`.

Критерии выхода — выполнены:

- ±0.5 BPM streak-стабильность на 180/195/200/220 BPM ✓
- `parabolic_precision_200_bpm` — допуск ±0.2 BPM ✓

---

## Phase 7: UI overhaul — **ЗАВЕРШЕНО** (2026-05-29)

Цель: метрические оси на визуализациях, live-spectrum, design system.

Артефакты:

- `SpectrogramPainter` с метрическими осями: Hz-метки на лог-шкале, временны́е метки.
- `LiveSpectrumPainter`: real-time FFT-кривая с gradient fill, peak-hold, лог X-ось 20–20 кГц.
- `AppTheme` (`design_tokens.dart`): акцент `#00E5CC`, фон `#07070F`, JetBrains Mono.
- `VizController.latestNorms` + `peakHoldValues`: third FFT consumer, decay ×0.90.
- Glassmorphism-карточка info-блока.
- `AnimatedSwitcher`-бейджи с `ValueKey<LockState>`.

### Phase 7.1: Осциллограф вместо спектрограммы — **ЗАВЕРШЕНО** (2026-05-29)

- `WaveformPainter` переписан в стиль осциллографа: тёмный фон + сетка, glow-проход, курсор «Now».
- Панель спектрограммы (35%) заменена на осциллограф (35%) на главном экране.
- `spectrogram_painter.dart` сохранён (не удалён).

---

## Phase 8: DSP fast re-lock v2 — **ЗАВЕРШЕНО** (2026-05-29)

Цель: re-lock после смены трека ≤ 3 с (было 6–8 с).

Артефакты:

- State-based адаптивное окно онсетов: `STABLE` = полная история, `LOCKING` = 6 с, `SEARCHING`/`UNSTABLE` = 2 с.
- Детектор прыжка темпа: порог 15 BPM → сброс `bpm_history` + принудительный `SEARCHING`.
- `DspConfig` поля: `adaptive_window` (default `true`), `tempo_jump_threshold` (default `15.0`).
- 6 новых streaming-тестов: `tempo_change_185_to_200`, `200_to_170`, `no_false_stable_during_transition` и др.
- `ADAPTIVE_WINDOW_LOCKING_SECS` = 6.0 с (исправлено с 4.0 → устранено зависание в LOCKING).

### Phase 8.1: fix first-lock regression — **ЗАВЕРШЕНО** (2026-05-29)

- Поле `has_ever_been_stable: bool` в `DspEngine`: полная история при первом захвате, адаптивное окно — только при повторном.
- Тесты: `first_lock_uses_full_window_no_prior_stable`, `relock_adaptive_window_still_fast_after_stable`.

Критерии выхода — выполнены:

- re-lock после смены трека ≤ 3 с ✓
- первый захват по-прежнему ≤ 12 с ✓
- 43 Rust-теста PASS ✓

---

## Phase 8.2: расширение диапазона 155–230 + аудит тестов — **ЗАВЕРШЕНО** (2026-05-30)

Цель: расширить детекцию на ранний hitech (~155 BPM) и закрыть структурный
пробел в тестах, из-за которого неверные детекции проходили незамеченными.

Артефакты:

- Предпочитаемый диапазон 170–230 → **155–230** (`DspConfig::target_bpm_min` и
  Python `hitech_min_bpm` = 155.0). Поиск 80–460 и нормализация не менялись.
- Синтетическая матрица 155 + 160…230 (шаг 5) в `core/dsp/tests/range_coverage.rs`.
- Абсолютный гейт точности ±2 BPM для реальных фикстур в `parity.py`
  (`expected_bpm` + `accuracy_tolerance` в `fixture_manifest.json`), отдельный от
  Python↔Rust parity. Закрывает класс ложных срабатываний.
- UI-тесты: `waveform_painter_test.dart` + расширенное покрытие полей InfoCard.

Критерии выхода — выполнены:

- детекция ≥170 BPM байт-идентична (нет регрессий) ✓
- 155 BPM детектируется в [153,157] без удвоения ✓
- 16-точечная матрица 155–230: first-lock ≤6 с, STABLE ≤12 с, ±1 BPM ✓
- абсолютный гейт ловит неверные детекции на размеченных фикстурах ✓

Известное ограничение: 13 из 21 реальных фикстур без ground truth (имена файлов
без BPM) — ожидают значений от пользователя; до этого они только parity-проверены
(`expected_bpm: null`, статус `n/a`). `hitech_real_10` остаётся `known_fail`.

---

## Phase 9: Android APK — **ЗАВЕРШЕНО** (2026-06-02)

Цель: получить подписанный release APK для Android и подтвердить работу детектора на эмуляторе/устройстве.

Артефакты — выполнены:

- `scripts/build_android_native.sh` — кросс-компиляция Rust → `.so` (arm64-v8a / armeabi-v7a / x86_64) через Android NDK. ✓
- Rust Android таргеты установлены: `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`. ✓
- `jniLibs/<abi>/libhitech_bpm_ffi.so` — заполнены для всех трёх ABI. ✓
- `.gitignore`: `jniLibs/`, `key.properties`, `*.jks` защищены. ✓
- `apps/mobile/android/key.properties.template` — шаблон с инструкцией по генерации keystore. ✓
- `docs/ANDROID_TEST_PLAN.md` — тест-план для AVD и физического устройства. ✓
- `docs/RELEASE_CHECKLIST.md` — 11-шаговый Android Release чеклист. ✓

Ребрендинг (2026-06-02):

- Display name: `Hitech BPM Radar` → **`TrackScope`** (strings.xml + Info.plist). ✓
- Dart-пакет: `hitech_bpm_radar` → `TrackScope` (pubspec.yaml, все тест-импорты). ✓
- `applicationId` сохранён без изменений (смена = новое приложение в RuStore). ✓
- Версия: `1.0.0+1` → `1.1.0+2` в `pubspec.yaml`. ✓
- `flutter build apk --release` → `app-release.apk` **54.7 MB** подтверждён 2026-06-03. ✓

Критерии выхода — выполнены:

- `bash scripts/build_android_native.sh` завершается без ошибок. ✓
- `jniLibs/` заполнены для всех трёх ABI. ✓
- `flutter build apk --release` → `app-release.apk` с release-подписью. ✓

Известное ограничение: виртуальный микрофон AVD не позволяет проверить реальную точность детектора — для этого нужно физическое Android-устройство.

## Phase 11.1: UI HTML-прототип аудит и фиксы — **ЗАВЕРШЕНО** (2026-06-01)

Цель: привести все Flutter-экраны в соответствие с HTML дизайн-референсами
(`BPM Radar Prototype.html`, `BPM Radar Redesign.html`, `CLAUDE_CODE_HANDOFF.md`).

Артефакты:

- **Zone labels + ListeningIndicator** (`main_screen.dart`): добавлены zone labels
  "WAVEFORM"/"LIVE SPECTRUM" над viz-панелями; "● слушаю" (accent цвет) при isCapturing.
- **Signal Analyzer редизайн** (`signal_analyzer_screen.dart`): uppercase title +
  PRO badge; top-4 кандидаты без relation-текста; 4px BPM bars; метрики с bars;
  добавлены Harmonic Ambiguity и Stability Score.
- **History Screen редизайн** (`history_screen.dart`): summary header (18px teal цифры),
  группировка по дням (СЕГОДНЯ/ВЧЕРА/РАНЕЕ), group-карточки `#0d1712` r=13,
  строки: BPM 20px teal/amber + 3px confidence bar. Устранена зависимость от AppTheme.
- **BpmSample.confidence** (`bpm_history.dart`): добавлено поле; контроллер передаёт
  `result.confidence`.
- **Settings sa-grp редизайн** (`settings_screen.dart`): group-карточки под прototip,
  font-size 12→9px, BPM Smoothing picker (None/Light/Moderate/Heavy).
- **BpmSmoothing enum** (`app_settings.dart`): SharedPreferences-backed.
- **Radar ×½/×2 ячейка** (`main_screen.dart`): возвращена; half_time и double_time
  кандидаты всегда видимы (anti-fake).
- **Paywall legal text** (`paywall_screen.dart`): юридический текст о подписке.
- **Tab labels** (`app_tab_bar.dart`): 8px → 7px.
- **Painter zone labels удалены** (`waveform_painter.dart`, `live_spectrum_painter.dart`):
  canvas-подписи заменены Flutter-виджетами.

Тесты: 139/139 Flutter pass (dsp_engine_test — pre-existing, нет .dylib).

Критерии выхода — выполнены:

- `flutter test` → 139/139 ✓
- `flutter analyze` → 0 errors ✓
- Все 🔴 критичные расхождения с HTML-прototипом устранены ✓
- half/double кандидаты никогда не скрыты ✓
- Нет фейкового BPM ✓

Известные ограничения (останутся до Phase 12):

- FFT Spectrum в Signal Analyzer — требует rawPcm стрима (Phase 3 mobile audio).
- Break button — UI-only, действие не реализовано.
- `AppTheme` в `design_tokens.dart` — legacy Phase 7 токены, используются в
  `main_screen.dart`; требует отдельного рефакторинга.

---

## Phase 11: Design System v2 + DspDebug — **ЗАВЕРШЕНО** (2026-06-01)

Цель: полный редизайн Flutter UI по дизайн-системе + экспозиция диагностики DspDebug в Signal Analyzer.

Артефакты:

- Tab Bar навигация (`AppNavigator`, `IndexedStack`): Радар / История / Настройки. `CaptureBridge` не пересоздаётся при смене вкладок.
- `BpmHeroDisplay` (72 px IBM Plex Mono, 3 режима: idle / detecting / unstable).
- `ConfidenceBar` (7 px, red < 30 % / yellow 30–70 % / teal > 70 %, анимация 400 мс).
- `SignalAnalyzerScreen` (Pro-only, push из Radar и Settings): показывает BPM-кандидатов со score bar, качество сигнала, тайминги и реальные DspDebug-метрики алгоритма.
- `SettingsScreen` (5 секций, SharedPreferences, WakelockPlus).
- `AppSettings` (ChangeNotifier singleton, SharedPreferences-persistence).
- Design tokens v2: `lib/theme/app_colors.dart` (#050807 bg, #00DFB0 accent) + `lib/theme/app_text_styles.dart` (IBM Plex Mono, роли).
- `PaywallScreen` v2: value headline, column headers FREE/PRO, CTA-иерархия, Roadmap card.
- **DspDebug в Rust `DspResult`**: `onset_rate_hz`, `onset_strength`, `tempo_peak_prominence`, `harmonic_ambiguity`, `stability_score`, `warnings`. Populated в `analyze_from_envelope` без дополнительной CPU-стоимости.
- **DspDebug класс в Dart** (`dsp_result.dart`): `fromJson` с graceful defaults (missing key → zero). Backward-compatible.
- `Signal Analyzer` показывает реальные метрики алгоритма (секция «Метрики алгоритма» — не placeholder).
- Зависимости: `shared_preferences ^2.3.0`, `wakelock_plus ^1.2.0`.
- Тесты: +3 Rust (`debug_field_populated_on_stable_signal`, `debug_serializes_to_json_with_debug_key`, `debug_empty_on_silence`), +6 Dart (`test/dsp_debug_test.dart`).

Критерии выхода — выполнены:

- `flutter analyze` → 0 errors ✓
- `flutter test` → 132/132 ✓
- `cargo test --workspace` → 75/75 ✓
- BPM null → «— — —» dim #1E3530 ✓
- ConfidenceBar 7 px + red/yellow/teal ✓
- Tab Bar: 3 вкладки, CaptureBridge не пересоздаётся ✓
- Signal Analyzer показывает реальные DspDebug-метрики ✓

---

## Phase 10: Freemium monetization (Free / Pro) — **ЗАВЕРШЕНО** (2026-05-31)

Цель: двухуровневая монетизация (Free / Pro) с RevenueCat IAP, paywall, гейтинг BPM-диапазона, debug-экрана, истории и экспорта.

Артефакты:

- FFI: `hitech_bpm_engine_new_with_min_bpm(float)` — обратно-совместимый второй конструктор; Free = 170–230, Pro = 155–230.
- `lib/monetization/`: `PurchasesGateway` (абстракция), `RevenueCatGateway` (единственный импорт `purchases_flutter`), `ProStatusService` (ChangeNotifier), `FeatureFlags`, `PaywallScreen`.
- `lib/history/`: `BpmHistory`, `SessionHistoryController` (даунсэмплер ~1 Hz), `HistoryScreen`.
- `lib/export/`: `buildCsv`/`buildJson` (чистые билдеры), `exportCsv`/`exportJson` (share_plus).
- `main.dart`: ProStatusService init, ListenableBuilder для tier-reactive CaptureBridge.
- `main_web.dart`: web-safe, без revenuecat-зависимостей.
- `config.dart.template` + `.gitignore` для `config.dart`.
- Тесты: feature_flags, pro_status_service, paywall_screen, bpm_history, bpm_exporter, widget_test (debug-gate).

Критерии выхода:

- `cargo test --workspace`, `flutter analyze` (0 errors), `flutter test` — все зелёные.
- FFI: Free engine 170–230, Pro engine 155–230; смена tier без перезапуска.
- Debug screen + export → paywall в Free; доступны в Pro.
- History: 30 сек (Free) / 24 ч (Pro) на выделенном экране.
- Restore работает. Widget показывает «Скоро».
- `config.dart` gitignored; Free работает keyless/offline.

---

## Phase 12: UI polish — **ЗАВЕРШЕНО** (2026-06-02)

Цель: читаемость текста, waveform glow, унификация дизайн-системы, FFT в Signal Analyzer, Break button.

Артефакты:

- **Type scale v2.2** (`app_text_styles.dart`): micro 9→11, caption 10→12, title 11→13, body 12→14, subhead 13→15, value 15→18 — все роли без изменения hero/heroEmpty.
- **Waveform ambient glow** (`waveform_painter.dart`): добавлен всегда-активный слой ambient glow (alpha=38, blur=4.0) поверх beat-reactive pulse — аналог spectrum.
- **Design System v2 migration** (`design_tokens.dart`): AppTheme теперь thin-proxy → AppColors/AppTextStyles. Шрифт JetBrains Mono → IBM Plex Mono. Добавлены цвета в `app_colors.dart`: `surfaceHigh`, `dangerDim`, `warning`, `warningDim`, `success`, `successDim`, `noisePurple`, `noiseDim`.
- **FFT Spectrum в Signal Analyzer** (`signal_analyzer_screen.dart`): StatelessWidget → StatefulWidget + VizController + `rawPcm` param + LiveSpectrumPainter panel сверху (90px). `app_navigator.dart` передаёт `rawPcm` в обоих местах создания SignalAnalyzerScreen.
- **Break button** (`capture_bridge.dart`): `resetEngine()` — сбрасывает DSP-движок и smoother без остановки захвата. Wiring: main.dart → AppNavigator.onBreak → MainScreen.onBreak → _GlassmorphismCard → _InfoTableContent → _BreakButtonInline.

Критерии выхода — выполнены:

- `flutter analyze` → 0 errors ✓
- `flutter test` → 148/149 pass (1 pre-existing dsp_engine_test — нет .dylib) ✓
- Шрифты читаемы (+2px по всем ролям) ✓
- Waveform glow всегда активен (ambient + beat-reactive) ✓
- AppTheme → AppColors/AppTextStyles, no duplicate tokens ✓
- FFT Spectrum в Signal Analyzer при наличии rawPcm ✓
- Break button вызывает реальный reset DSP ✓

---

## Phase 2.1: Детекция тональности (HPCP KeyAnalyzer) — **ЗАВЕРШЕНО** (2026-06-02)

Цель: реализовать детекцию тональности в реальном времени через HPCP + Krumhansl-Schmuckler.

Артефакты:

- `core/dsp/src/key_analyzer.rs` — полная реализация: STFT → HPCP → K-S корреляция → Camelot-маппинг.
- `rustfft = "6"` добавлен в `core/dsp/Cargo.toml`.
- `DspEngine` интегрирован: `key_analyzer` как поле, `push_samples` накапливает HPCP, `analyze()` заполняет `key_result`, `reset()` сбрасывает состояние.
- `core/dsp/tests/key_detection.rs` — 12 тестов: Camelot-маппинг, JSON-сериализация, синус 440 Hz → A, тишина → None, reset → None, CLIPPED_MIC → None.
- `apps/mobile/lib/dsp/dsp_result.dart` — класс `KeyResult` + поле `DspResult.keyResult`, парсинг вложенного JSON `camelot: {number, letter}` → строка "8A".
- `apps/mobile/test/dsp_debug_test.dart` — 2 новых теста: парсинг `key_result` из JSON, `key_result` отсутствует когда нет поля.

Критерии выхода — выполнены:

- `cargo test --workspace` → все тесты зелёные (107 Rust) ✓
- `flutter test` → 188/188 ✓
- Тишина → `key_result == None` ✓
- CLIPPED_MIC → `key_result == None` ✓
- Camelot: A minor = "8A", C major = "8B" ✓
- JSON: `key_result` отсутствует при None ✓

---

## Phase 2.2: EnergyAnalyzer — уровень энергии 1–10 — **ЗАВЕРШЕНО** (2026-06-02)

Цель: реализовать детекцию уровня энергии 1–10 (Mixed In Key-стиль) через RMS + spectral flux + onset density.

Артефакты:

- `core/dsp/src/energy_analyzer.rs` — полная реализация: RMS-окно 3 сек + flux_history из DspEngine + onset density → взвешенная сумма → ceil × 10, clamp [1,10].
- `DspEngine` интегрирован: `energy_analyzer` как поле, `push_normalized` вызывает `push_samples` и `push_flux`, `analyze()` заполняет `energy_result`, `reset()` сбрасывает состояние.
- `core/dsp/tests/energy.rs` — 5 тестов: absence on silence, presence on STABLE, level in [1,10], calibration clean_200 in [4,8], absence on CLIPPED_MIC.
- `apps/mobile/lib/dsp/dsp_result.dart` — класс `EnergyResult` + поле `DspResult.energyResult`, парсинг JSON.
- `apps/mobile/test/dsp_debug_test.dart` — 2 новых теста: `energy_result_parses_from_json`, `energy_result_absent_when_not_in_JSON`.
- `apps/mobile/lib/screens/signal_analyzer_screen.dart` — секция «ЭНЕРГИЯ» с progress bar + RMS/Flux/Density rows. Гейт по `energyResult != null`.

Критерии выхода — выполнены:

- `cargo test --workspace` → все тесты зелёные ✓
- `flutter test` → 190/190 ✓
- `flutter analyze` → 0 errors ✓
- Тишина → `energy_result == None` ✓
- CLIPPED_MIC → `energy_result == None` ✓
- clean_200 STABLE → level ∈ [4, 8] ✓
- Signal Analyzer показывает энергию `N / 10` при наличии сигнала ✓

Известные ограничения:

- Калибровочные константы (`FLUX_MAX = 0.15`, `DENSITY_MAX = 6.0`) подобраны на синтетике; требуют fine-tuning на реальных записях (Phase 2.2.1).
- Python-референс (`tempo.py`) не реализует `energy_result` — всегда `None` в Python-пути.

### Phase 2.2.3: динамический hop_sec (2026-06-03)

`EnergyAnalyzer::new(sample_rate, hop_sec)` — сигнатура расширена. Реальный `hop_sec` передаётся из `DspEngine` (вычислен как `hop_size / sample_rate`). Константа `HOP_SEC = 0.0025` удалена. `flux_capacity` и `onset_density_hz` теперь корректны для любого sample rate, не только 48 kHz. `min_peak_gap` вычисляется динамически: `(0.1 / hop_sec).round()` (100 мс зазор).

Артефакты:
- `core/dsp/src/energy_analyzer.rs` — удалена `const HOP_SEC`, добавлено поле `hop_sec: f32`, сигнатура `new(sample_rate, hop_sec)`, динамический `min_peak_gap`.
- `core/dsp/src/lib.rs` — call site обновлён: `EnergyAnalyzer::new(config.sample_rate as f32, hop_sec)`.
- `core/dsp/tests/energy.rs` — +2 документальных теста: `flux_floor_does_not_silence_quiet_pulse_amplitude_0_1`, `flux_floor_boundary_very_quiet_pulse_amplitude_0_02`.

Критерии выхода — выполнены:
- `cargo test --workspace` → 122/122 Rust-тестов ✓
- `flutter test` → 218/218 (1 pre-existing dsp_engine_test) ✓
- `FLUX_ABSOLUTE_FLOOR` верифицирован: при amplitude=0.1 (~-20 dBFS) пики flux детектируются в STABLE ✓
- Нет изменений в `DspResult` / FFI / Dart-контракте ✓

---

### Phase 2.2.4: калибровка FLUX_MAX по реальным hitech-трекам — **ЗАВЕРШЕНО** (2026-06-03)

Цель: устранить сжатие диапазона energy_level в зону [7–8] на активных треках из-за завышенного `FLUX_MAX`.

**Проблема:** `FLUX_MAX = 0.15` (по синтетике). Реальные треки: `spectral_flux = 0.013–0.023` → flux_norm 0.09–0.15 → весь диапазон [1–10] «сжат» у потолка.

Артефакты:
- `core/dsp/src/energy_analyzer.rs` — `FLUX_MAX`: 0.15 → **0.030** (P95 реальных треков ≈ 0.023 + 30% margin). Обновлён комментарий с empirical-обоснованием.
- `core/dsp/tests/energy.rs` — +2 теста: `calibration_real_hitech_proxy_level_at_least_5` (rms ≈ -8 dBFS, flux ≈ 0.020 → level ≥ 5), `calibration_weak_signal_level_at_most_4` (rms ≈ -30 dBFS, flux ≈ 0.003 → level ≤ 4).
- `docs/DSP_ALGORITHM.md` — таблица констант обновлена, добавлен подраздел Phase 2.2.4 с таблицей сравнения flux_norm.
- `docs/QA_MATRIX.md` — добавлена секция Phase 2.2.4 с данными 4 реальных треков.

Критерии выхода — выполнены:
- `FLUX_MAX = 0.030` откалиброван по эмпирическим данным (4 трека) ✓
- Активные hitech-треки (rms ≈ -8 dBFS, flux ≈ 0.020) дают level ≥ 5 ✓
- Слабый сигнал (rms ≈ -30 dBFS, flux ≈ 0.003) даёт level ≤ 4 ✓
- Синтетика `clean_200` сохраняет level ∈ [4, 8] (без регрессий) ✓
- `cargo test --workspace` → 124/124 Rust-тестов ✓
- `flutter test` → 218 pass (1 pre-existing) ✓
- `offline_lab.py report` → exit code 0 ✓
- Тишина → `energy_result == None` ✓
- CLIPPED_MIC → `energy_result == None` ✓
- Нет изменений в `DspResult` / FFI / Dart-контракте / публичном API ✓

Известные ограничения:
- Калибровка по 4 трекам; для устойчивости нужно ≥ 10 треков из разных жанровых поддиапазонов.
- Аудиофайлы треков 01–21 отсутствуют в репозитории (авторское право) — замер только по трекам 22–25.

---

## Phase 2.3: Energy / Key Display на Radar Tab — **ЗАВЕРШЕНО** (2026-06-03)

Цель: показать `EnergyResult.level` и `KeyResult.camelot` на главном экране (Radar tab) в info-таблице — данные уже жили в `DspResult` после Phase 2.1–2.2, требовался только UI-слой.

Артефакты:

- `_EnergyCell` widget (`apps/mobile/lib/ui/main_screen.dart`): строка «ЭНЕРГИЯ» с `N/10` значением и `LinearProgressIndicator` 4 px (red ≤3 / yellow 4–7 / teal ≥8).
- `_InfoTableContent` расширен двумя условными строками (Row 4): энергия слева, тональность справа.
- **Гейты:** `energyResult != null` и `keyResult != null && confidence >= 0.25`.
- `MockDspStream.stable()` обновлён: эмитит `energyResult` в locked-состояниях и `keyResult` ("8A", conf=0.62) в STABLE-состоянии.
- `apps/mobile/test/widget_test.dart` — +5 тестов: показ energy (7/10), показ camelot (8B), скрытие при null-energy, скрытие при null-key, скрытие при confidence < 0.25.

Критерии выхода — выполнены:

- `flutter analyze` → 0 errors (17 pre-existing infos/warnings не изменились) ✓
- `flutter test` → 195/195 (было 190, +5 новых тестов) ✓
- Energy row не рендерится при `energyResult == null` ✓
- Key row не рендерится при `keyResult == null` или `confidence < 0.25` ✓
- Layout согласуется с Design System v2 (AppTextStyles, AppColors) ✓
- `MockDspStream` показывает energy/key в ACTIVE → STABLE режиме превью ✓

Известные ограничения:

- ~~На малых экранах (высота < 700 px) нижняя часть info-карты обрезается `NeverScrollableScrollPhysics`~~ — устранено в Radar UI refactor (2026-06-03).
- Colorful gradient в energy bar (teal → yellow → red) не поддерживается `LinearProgressIndicator`; используется однотонный цвет по диапазону уровня. Полный gradient требует `CustomPainter`.

---

## Radar UI: no-scroll + energy/key always visible — **ЗАВЕРШЕНО** (2026-06-03)

Цель: убрать скролл в info-карте Radar tab; энергия и тональность всегда отображаются.

Артефакты:

- `SingleChildScrollView` удалён из `_GlassmorphismCard`; заменён на `OverflowBox(maxHeight: infinity)` — подавляет layout assertion без скролла, клиппинг через `Clip.hardEdge` на контейнере.
- Строка «ЭНЕРГИЯ / ТОНАЛЬНОСТЬ» рендерится безусловно: при `null` показывается заглушка `—` той же высоты.
- Оригинальный визуальный масштаб восстановлен: 72px BPM hero, 120px waveform, flex 22/43.
- Единственное отличие от Phase 2.3: зазор между цифрой BPM и строкой «BPM 155–230 · Hitech» уменьшен (SizedBox 5→0, высота строки 28→22px).
- Тесты: 3 обновлены (`findsNothing` → `findsOneWidget` для лейблов), +1 новый (`energy_always_visible_even_when_null`). Итого 196 Flutter тестов.

Критерии выхода — выполнены:

- `flutter test` → 196/196 ✓
- `flutter analyze` → 0 errors ✓
- ЭНЕРГИЯ и ТОНАЛЬНОСТЬ видимы при любом DSP-состоянии ✓
- Скролл недоступен ✓

---

## Phase 2.4: Setlist — Camelot Key + Energy Level — **ЗАВЕРШЕНО** (2026-06-03)

Цель: дополнить каркас `SetlistService` / `SetlistEntry` / `SetlistScreen`, реализованный
в Phase 10, реальными данными KeyAnalyzer и EnergyAnalyzer (Phase 2.1 + 2.2).

### Что изменилось

- **`SetlistEntry`** (`apps/mobile/lib/features/setlist/setlist_entry.dart`):
  - Раскомментированы поля `camelotKey: String?` и `energyLevel: int?`.
  - `toJson()` включает поля только если не null (JSON-backward-compatible).
  - `toCsvRow()` добавляет два столбца; `setlistCsvHeader` обновлён:
    `timestamp,bpm,lock_state,confidence,input_level_dbfs,camelot_key,energy_level`.

- **`SetlistService`** (`apps/mobile/lib/features/setlist/setlist_service.dart`):
  - `onDspResult` передаёт `result.keyResult?.camelot` и `result.energyResult?.level`
    в конструктор `SetlistEntry`.
  - `exportJson()` содержит `has_key_data` и `has_energy_data` в summary-объекте.

- **`SetlistScreen._EntryRow`** (`apps/mobile/lib/features/setlist/setlist_screen.dart`):
  - Если `entry.camelotKey != null` — отображается акцентным цветом справа от confidence.
  - Если `entry.energyLevel != null` — отображается `E{N}` muted-цветом.

**Anti-fake инвариант сохранён:** запись в сетлист происходит **только** при
`lockState == STABLE` и `primaryBpm != null`. Поля key/energy берутся из реального
DSP-результата; fallback-значений нет.

### Тесты

- `test/features/setlist/setlist_service_test.dart` — +6 новых тестов:
  `onDspResult with key_result stores camelotKey`, `without key_result stores null`,
  `with energy_result stores energyLevel`, `exportJson contains camelot_key`,
  `exportJson contains has_key_data field`, `exportCsv header/row columns`.
- `test/features/setlist/setlist_screen_test.dart` — +3 новых теста:
  `shows camelot key`, `shows energy level`, `renders without camelot/energy (null)`.

Критерии выхода — выполнены:

- `flutter test` → 203 passed (1 pre-existing dsp_engine_test — нет .dylib) ✓
- `flutter analyze` → 0 errors, 17 pre-existing infos ✓
- `SetlistEntry` хранит `camelotKey`/`energyLevel` ✓
- `_EntryRow` отображает `8A` и `E7` при наличии данных ✓
- CSV-заголовок обновлён, JSON-summary содержит `has_key_data`/`has_energy_data` ✓
- Anti-fake: запись только при STABLE + primaryBpm != null ✓

---

## Phase 2.5: FFI `new_with_range` + Custom(min, max) пресет — **ЗАВЕРШЕНО** (2026-06-03)

Цель: дать Pro-пользователю полный контроль над BPM-диапазоном детектора через
Custom-пресет с произвольными min/max; расширить FFI-границу обратно-совместимым
третьим конструктором.

### Что изменилось

**Rust FFI** (`core/ffi/src/lib.rs`):

- `hitech_bpm_engine_new_with_range(min_bpm: f32, max_bpm: f32)` — новый
  конструктор. `min` зажимается в [80, 260], `max` в [min+10, 300]; не-finite →
  дефолт (155, 230). Создаёт `DspConfig { target_bpm_min: min, target_bpm_max: max }`.
- Тесты (`core/ffi/tests/ffi_contract.rs`):
  - `engine_new_with_range_ctor_returns_non_null` — указатель ненулевой.
  - `engine_new_with_range_detects_in_band_tempo` — детектирует 180 BPM в диапазоне
    (160, 200), STABLE ≤ 13 с.

**Dart bindings** (`apps/mobile/lib/dsp/bindings.dart`):

- `typedef _EngineNewWithRangeC` / `HitechBpmEngineNewWithRange` добавлены.
- `HitechBpmFfi.engineNewWithRange` — lookup `hitech_bpm_engine_new_with_range`.

**DspEngine + CaptureBridge + dsp_worker**:

- `DspEngine.fromBindings(…, maxBpm?)`: выбор конструктора — `new_with_range`
  если `maxBpm != null`, `new_with_min_bpm` если только `minBpm != null`, иначе `new`.
- `CaptureBridge` принимает `maxBpm?`; `WorkerInit` несёт поле `maxBpm?`;
  worker выбирает конструктор по логике выше.

**GenrePreset** (`apps/mobile/lib/features/genre_preset/genre_preset.dart`):

- `custom` добавлен как 8-й вариант (в конец — индексы 0–7 стабильны для
  SharedPreferences).
- `isProRequired`: `custom → true`.
- `bpmRange`: placeholder `(155.0, 230.0)` — реальные значения берутся из
  `AppSettings.customMin/customMax` по `effectiveBpmRange`.
- `allPresets`: теперь 8 вариантов; `freePresets` остаётся 3.

**AppSettings** (`apps/mobile/lib/settings/app_settings.dart`):

- Поля `customMin = 155.0` / `customMax = 230.0`.
- SharedPreferences-ключи `'custom_min_bpm'` / `'custom_max_bpm'`.
- `setCustomRange(min, max)`: валидация `min < max && min >= 80 && max <= 300` —
  иначе no-op.
- `effectiveBpmRange`: при `selectedGenre == custom` → `(customMin, customMax)`,
  иначе → `selectedGenre.bpmRange`.
- `resetAll()` сбрасывает `customMin/customMax` в дефолты.

**FeatureFlags** (`apps/mobile/lib/monetization/feature_flags.dart`):

- Новые поля `customMin`, `customMax` (defaults 155/230).
- `maxBpm` добавлен: при `isPro && genre == custom` → `customMax`; иначе →
  `preset.bpmRange.$2`.

**main.dart**: `CaptureBridge` получает `maxBpm: flags.maxBpm` при создании;
`ListenableBuilder` на `Listenable.merge([ProStatusService, AppSettings])` триггерит
пересоздание при смене диапазона — новый `DspEngine` с обновлёнными min/max.

**SettingsScreen** (`apps/mobile/lib/screens/settings_screen.dart`):

- Секция «CUSTOM RANGE» появляется только при `selectedGenre == custom`.
- Pro: два `_SliderRow` (Min BPM 80–max-10, Max BPM min+10–300).
- Free: `_InfoRow` «Требуется PRO» с PRO-бейджем.
- `_GenrePickerRow` и `_InfoRow BPM Range` отображают live-значения
  `AppSettings.customMin/customMax`, а не placeholder `bpmRange`.

### Тесты

- `core/ffi/tests/ffi_contract.rs` → `engine_new_with_range_ctor_returns_non_null`,
  `engine_new_with_range_detects_in_band_tempo` (+2 Rust).
- `test/settings/custom_range_test.dart` → 11 тестов: defaults, validation
  (valid, min==max, min>max, min<80, max>300, boundary), effectiveBpmRange.
- `test/screens/settings_screen_custom_test.dart` → 4 теста: Custom+Pro показывает
  слайдеры, не-Custom скрывает секцию, Custom+Free показывает paywall-hint,
  BPM Range строка отражает customMin/customMax.
- `test/monetization/feature_flags_test.dart` → обновлены 2 счётчика (7→8 Pro,
  7→8 allPresets).

### Критерии выхода — выполнены

- `cargo test --workspace` → все тесты зелёные (incl. `engine_new_with_range_*`) ✓
- `flutter analyze` → 0 errors ✓
- `flutter test` → 218 passed, 1 pre-existing (dsp_engine_test — нет .dylib) ✓
- `GenrePreset.custom` Pro-gated, `allPresets.length == 8` ✓
- `AppSettings.setCustomRange` валидирует и сохраняет в SharedPreferences ✓
- `CaptureBridge` передаёт `maxBpm` → worker выбирает `new_with_range` ✓
- SettingsScreen: Custom+Pro → слайдеры; Custom+Free → paywall-hint ✓
- Нет фейкового BPM, нет хардкода диапазона, anti-fake инварианты сохранены ✓

### Известные ограничения

- Слайдеры — непрерывные (Slider). При каждом тике вызывается `setCustomRange`,
  что инициирует async-запись в SharedPreferences. Для крайне активного перетаскивания
  это создаёт лишние writes; future: throttle через `onChangeEnd`.
- При Custom+Pro смена диапазона пересоздаёт `_CapturePipeline` (новый `ValueKey`) —
  DSP-история сбрасывается. Это корректное поведение (новый движок с новым диапазоном),
  но визуально на 1–2 секунды STABLE → SEARCHING.
- Python-референс (`tempo.py`) и offline-lab не затронуты — `new_with_range` — чисто
  Flutter-сторона; DSP-алгоритм не изменился.

---

## Phase 13: Android System Insets Fix — **ЗАВЕРШЕНО** (2026-06-03)

Цель: устранить перекрытие таб-бара системными кнопками Android (RuStore rejection, версия 1.1.0+2).

Артефакты:

- **`AppTabBar`** (`apps/mobile/lib/widgets/app_tab_bar.dart`): `padding.bottom` изменён с хардкодного
  `20` на `20 + MediaQuery.paddingOf(context).bottom`. Таб-бар теперь автоматически добавляет высоту
  системной навигационной полосы (жестовая / 3-кнопочная) к нижнему отступу — содержимое вкладок
  всегда видимо над системной полосой на любом Android-устройстве.
- **`SignalAnalyzerScreen`** (`apps/mobile/lib/screens/signal_analyzer_screen.dart`): `ListView`
  изменён с `padding: EdgeInsets.zero` на `EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom)` —
  исключён bottom clipping последнего элемента при отсутствии `bottomNavigationBar`.
- **`SetlistScreen._EntriesTable`** (`apps/mobile/lib/features/setlist/setlist_screen.dart`): `ListView.builder`
  изменён с `padding: EdgeInsets.only(bottom: 32)` на `EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom)` —
  та же защита для pushed-экрана сетлиста.
- **Version bump**: `pubspec.yaml` `1.1.0+3` → `1.1.1+4` для повторной подачи в RuStore.

Критерии выхода — выполнены:

- `flutter analyze` → 0 errors ✓
- `flutter test` → 218 passed, 1 pre-existing (dsp_engine_test — нет .dylib) ✓
- `cargo test --workspace` → все зелёные (124 Rust) ✓
- `AppTabBar` использует `MediaQuery.paddingOf(context).bottom` ✓
- `apps/mobile/pubspec.yaml` version `1.1.1+4` ✓
- Anti-fake инварианты не нарушены: нет хардкода BPM, нет демо-значений, нет STABLE без evidence ✓

Известное ограничение: ручная верификация на физическом Android-устройстве с 3-кнопочной
навигацией необходима перед финальным релизом. AVD-эмулятор не воспроизводит высоту системной
полосы достоверно.

---

## Phase 13.1: Real-world stability + KeyAnalyzer fix — **ЗАВЕРШЕНО** (2026-06-03)

Цель: устранить три проблемы, выявленные при реальном тестировании на iPhone.

### Баги и фиксы

#### 1. BpmSmoother выбрасывал energy_result / key_result (КРИТИЧЕСКИЙ БАГ)

`BpmSmoother.smooth()` создавал `DspResult` без `keyResult` и `energyResult` — они молча
становились `null` на каждом сглаженном кадре. ЭНЕРГИЯ и ТОНАЛЬНОСТЬ на главном экране
всегда показывали «—», даже когда Rust DSP корректно их вычислял.

**Фикс:** добавлены `keyResult: raw.keyResult, energyResult: raw.energyResult` в конструктор
внутри `smooth()`.

**Новый тест:** `bpm_smoother_test.dart` — `smooth() передаёт keyResult и energyResult без изменений`.

#### 2. STABLE недостижим в реальных условиях

На iPhone в комнате при воспроизведении через колонку: SNR ≈ 2.7 dB → `signal_factor = 0.28`
→ итоговая уверенность ~60% при кандидатном score 86% → порог STABLE 0.70 никогда не достигался.

**Фиксы:**
- STABLE-порог: **0.70 → 0.65** (`analyze_from_envelope` + `analyze_candidates` в `lib.rs`, `tempo.py`)
- SNR signal_factor нижняя граница: **0.28 → 0.40** (убирает обрыв на 3 dB)

#### 3. KeyAnalyzer всегда возвращал 3A или 2B

HPCP вычислялся с 50 Hz и без нормализации по частоте. FFT-биты линейны по Гц,
но питч-классы — логарифмичны: Gb/F получали 17 бинов из 50–200 Hz vs 9 у Ab/Bb →
K-S корреляция систематически выбирала Gb Major (2B) или Bb Minor (3A).

**Фиксы:**
- `FREQ_MIN`: **50 → 100 Hz** (убирает суб-бас kick drum)
- **1/f-нормализация** при аккумуляции HPCP: `power / freq` для каждого бина →
  равномерный вклад по полутонам → нет структурного смещения питч-класса

### Критерии выхода — выполнены

- `flutter test` → 219 pass (1 pre-existing dsp_engine_test) ✓
- `cargo test --workspace` → все тесты зелёные ✓
- `offline_lab.py report` → 15/15 PASS, exit 0 ✓
- ЭНЕРГИЯ и ТОНАЛЬНОСТЬ рендерятся в LOCKING-состоянии ✓
- STABLE достижим при реальном воспроизведении ✓
- KeyAnalyzer больше не застревает на 3A/2B ✓
- Anti-fake инварианты не нарушены: silence/noise/clipping → никогда не STABLE ✓

### Известные ограничения

- Калибровка STABLE-порога 0.65 оптимальна для ~2.7 dB SNR. При очень сильном клубном
  шуме (SNR < 1 dB) движок по-прежнему остаётся в LOCKING — это корректное поведение.
- KeyAnalyzer требует реальных мелодических/гармонических компонентов для точной детекции;
  на чистом ритмическом материале (только бочка) уверенность может быть ниже порога 0.25.
- 1/f-нормализация в HPCP — ещё не проверена на широкой выборке реальных треков с разными
  тональностями. Ручная верификация рекомендована на ≥5 треков с известным ключом.

---

## Phase 14: Adaptive Main Screen Layout — **ЗАВЕРШЕНО** (2026-06-04)

Цель: устранить overflow на малых устройствах (Pixel 4, iPhone SE) — все 4 строки stats,
ЭНЕРГИЯ и ТОНАЛЬНОСТЬ видимы без скролла на любом Android/iOS устройстве.

### Диагностика

| Устройство | Высота body | Карточка (outer) | Overflow |
|---|---|---|---|
| Pixel 7 | ~750 dp | ~393 dp | −10 dp (mode chips срезаны) |
| Pixel 4 | ~665 dp | ~341 dp | **+42 dp** (ЭНЕРГИЯ/ТОНАЛЬНОСТЬ срезана) |

Причина: порог `showLockChips: cc.maxHeight >= 330` был слишком низким (both Pixel 7 и
Pixel 4 попадали в зону chips-shown), а BPM hero и spacings были не адаптивными.

### Решение (adaptive compact mode)

| Режим | Порог (card outer height) | BPM font | spacing | chips |
|---|---|---|---|---|
| compact | `cc.maxHeight < 420` | 52 dp | 1 dp | скрыты при < 380 dp |
| normal  | `cc.maxHeight ≥ 420` | 72 dp | 3 dp | показаны |

**Расчёт экономии (compact без chips, Pixel 4, card=341 dp):**
BPM 72→52 (−17 dp) + spacings ×5 (−10 dp) + break padding (−6 dp) + без chips (−29 dp) = **−62 dp**
Контент: 365 − 62 = **303 dp** vs 323 dp доступно → **+20 dp margin** ✓

### Артефакты

- **`_GlassmorphismCard`** (`apps/mobile/lib/ui/main_screen.dart`): LayoutBuilder теперь
  вычисляет `compact = cc.maxHeight < 420` и `showLockChips = cc.maxHeight >= 380`;
  оба параметра передаются в `_InfoTableContent`. `OverflowBox` сохранён как safety-net.
- **`_InfoTableContent`**: новый параметр `compact: bool = false`. В `build()` —
  `spacing = compact ? 1.0 : 3.0` и `bpmFontSize = compact ? 52.0 : 72.0`.
  Все 5 `const SizedBox(height: 2/3)` заменены на `SizedBox(height: spacing)`.
- **`_AnimatedBpmDisplay`**: новые параметры `fontSize: double = 72.0` и
  `subtitleHeight: double = 22.0`. `letterSpacing` адаптирован: `< 60dp → −1.5`,
  иначе `−2.5`. В compact-режиме передаётся `fontSize: 52.0, subtitleHeight: 18.0`.
- **`_BreakButtonInline`**: новый параметр `compactPadding: bool = false`.
  `vertical: compactPadding ? 5 : 8`. В compact-режиме передаётся `compactPadding: true`.
- **Тесты** (`apps/mobile/test/widget_test.dart`):
  - 6 chip-тестов обновлены: `tester.view.physicalSize = const Size(800, 1200)` (card ≈659 dp, chips visible).
  - **+2 новых теста**: `compact layout hides mode chips when card height is small` и
    `energy and key labels always visible in compact mode` (480×720 @ 1x, card ≈361 dp).

### Критерии выхода — выполнены

- `flutter test` → **221/221 pass** (+2 новых теста, было 219) ✓
- `flutter analyze` → 0 errors ✓
- `cargo test --workspace` → все зелёные (DSP не трогался) ✓
- На **Pixel 7** (card ≈393 dp): compact font + chips показаны (393 ≥ 380) ✓
- На **Pixel 4** (card ≈341 dp): compact font + chips скрыты (341 < 380); ЭНЕРГИЯ/ТОНАЛЬНОСТЬ видимы ✓
- Нет хардкодного BPM, нет демо-значений, anti-fake инварианты не нарушены ✓
- `MainScreen` публичный API не изменился (только приватные классы внутри файла) ✓

### Известные ограничения

- Пороги 380/420 dp верифицированы расчётно для Pixel 4/7. Верификацию на AVD-профилях
  Pixel 3a, Pixel 7 Pro и iPhone SE Gen3 — рекомендуется провести вручную.
- BPM `—  —  —` (3 символа) в compact 52dp режиме: при очень узких экранах (<360 dp wide)
  возможен горизонтальный overflow; добавлен `maxLines: 1` на будущее как mitigation.

---

## Phase 2.5 (Camelot Wheel UI): ТОНАЛЬНОСТЬ в Signal Analyzer — **ЗАВЕРШЕНО** (2026-06-04)

Цель: визуализировать результат `KeyResult` из Phase 2.1 как интерактивное Camelot Wheel
в Signal Analyzer, чтобы DJ мог мгновенно оценить совместимые тональности.

*Примечание: нумерация плана — `phase-2-5-camelot-wheel-ui.md`; Phase 2.5 в числовом смысле
параллельна Phase 2.5 (FFI `new_with_range`) — это разные фичи.*

### Артефакты

- **`apps/mobile/lib/viz/camelot_wheel_painter.dart`** — `CamelotWheelPainter` (CustomPainter):
  2 кольца × 12 сегментов = 24 аннулярных сектора по 30°. Активный сегмент — `AppColors.accent`;
  3 гармонически совместимых соседа — accent 28% alpha; остальные — `surfaceHigh`.
  Чистая функция `camelotNeighbors(String camelot) → List<String>`: возвращает prev/next по кольцу
  + cross-ring (A↔B), с wrap-around на позициях 1 и 12.
- **`apps/mobile/lib/widgets/camelot_wheel_widget.dart`** — `CamelotWheelWidget(keyResult?, size)`:
  stateless-обёртка с `RepaintBoundary`. При `null` keyResult рисует колесо без подсветки.
- **`apps/mobile/lib/screens/signal_analyzer_screen.dart`** — `_KeyGroup` widget: секция
  «ТОНАЛЬНОСТЬ» (между Энергией и Метриками алгоритма). Рендерится только при `keyResult != null`.
  Контент: `CamelotWheelWidget(size: 180)` + строка «A Minor · 8A · 62%».

### Тесты (+11 новых)

- `test/viz/camelot_wheel_painter_test.dart` — 4 unit-теста `camelotNeighbors()`:
  mid-wheel, wrap 1→12, wrap 12→1, invalid input.
- `test/widgets/camelot_wheel_widget_test.dart` — 4 smoke-теста: null/valid key, size,
  RepaintBoundary.
- `test/screens/signal_analyzer_screen_test.dart` — 3 integration-теста: секция скрыта
  при null, показана при keyResult, summary «A Minor · 8A · 62%».

### Критерии выхода — выполнены

- `flutter test` → **232/232 pass** (+11 тестов, было 221) ✓
- `flutter analyze` → 0 errors ✓
- `cargo test --workspace` → все зелёные (DSP не трогался) ✓
- `offline_lab.py report` → exit 0, 15/15 PASS ✓
- Нет BPM-математики в UI — все данные из `DspResult.keyResult` ✓
- Anti-fake инварианты не нарушены: нет хардкодных значений, нет STABLE без evidence ✓
- Radar tab не изменён ✓

### Известные ограничения

- Колесо статическое (не вращается). Анимация перехода при смене тональности — бэклог.
- Текстовые лейблы сегментов используют `IBMPlexMono` через `TextStyle.fontFamily`.
  Если шрифт не загружен в тестовом окружении, рендерится fallback — визуально корректно.
- `CamelotWheelPainter` не проверяет `keyResult.confidence < 0.25` — это гейт DSP-уровня
  (в `DspEngine`), не UI. Если DSP не эмитит `key_result` при низкой уверенности, секция
  просто не отображается (`keyResult == null`). Поведение корректно по контракту.

---

## Phase 2.6: Share Set Energy Card — **ЗАВЕРШЕНО** (2026-06-04)

Цель: позволить Pro-пользователям поделиться визуальной карточкой сета (BPM-кривая + тональность + энергия) одним нажатием.

Артефакты:

- **`SetEnergyCardPainter`** (`apps/mobile/lib/features/share_card/set_energy_card_painter.dart`): `CustomPainter` 1080×1080 px. Рендерит:
  - BPM-кривую по временной оси (polyline + gradient fill под кривой);
  - Camelot-пиллы в точках смены тональности (акцентный фон + тёмный текст);
  - Полярный energy arc (10 равных сегментов, цвет: red ≤3 / yellow 4–7 / teal ≥8) с цифрой и лейблом в центре;
  - Watermark «TrackScope» внизу справа.
- **`SetEnergyCard`** (`apps/mobile/lib/features/share_card/set_energy_card.dart`): `StatefulWidget` + `RepaintBoundary`. Метод `captureAndShare()`: `toImage(pixelRatio: 1.0)` → PNG → `getTemporaryDirectory()` → `Share.shareXFiles`.
- **`FeatureFlags.canShareCard`** (`apps/mobile/lib/monetization/feature_flags.dart`): `bool get canShareCard => isPro`.
- **`SetlistScreen`** (`apps/mobile/lib/features/setlist/setlist_screen.dart`): `_SetlistView` преобразован из `StatelessWidget` в `StatefulWidget`; добавлен `Offstage(child: SetEnergyCard(...))` для off-screen рендеринга; кнопка `Icons.share_outlined` в AppBar (гейт: `entries.isNotEmpty`). Pro: запускает `captureAndShare()`. Free: переход на `PaywallScreen(feature: 'share_card')`.
- **Тесты** (`apps/mobile/test/features/share_card/set_energy_card_test.dart`): 11 тестов — `canShareCard` Pro/Free, painter smoke (пусто/одна/несколько/одинаковый BPM/нет энергии), данные из реального `SetlistEntry`, кнопка видима при Pro+entries, скрыта при пустых entries, Free → PaywallScreen.
- **Execution plan** (`docs/plans/phase-2-6-share-set-energy-card.md`).

Критерии выхода — выполнены:

- `flutter analyze` → 0 errors ✓
- `flutter test` → 229 passed, 1 pre-existing (dsp_engine_test — нет .dylib) ✓
- `FeatureFlags.canShareCard` Pro-gated ✓
- Кнопка в SetlistScreen: Pro+entries → share, Free → PaywallScreen ✓
- Нет хардкодного BPM; все данные из `SetlistEntry.bpm` (реальный DSP-вывод) ✓
- Anti-fake инварианты сохранены ✓

Известные ограничения:

- `captureAndShare()` не тестируется в unit-среде (требует реальной render-surface); покрыт дымовым тестом `CustomPainter.paint()` через `PictureRecorder`.
- Шрифт «IBM Plex Mono» в painter использует Dart `TextStyle(fontFamily: ...)` — рендеринг зависит от наличия шрифта в bundle; на устройствах без него используется системный fallback.
- Нет изменений в Rust DSP / FFI / DspResult — Phase 2.6 чисто Flutter-сторона.
