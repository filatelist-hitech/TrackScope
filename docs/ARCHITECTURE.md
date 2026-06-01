# Архитектура

## Намерение

hitech-bpm-radar — DSP-first мобильный BPM-детектор для hitech / psytrance в диапазоне 155–230 BPM. Репозиторий устроен так, чтобы темповая логика была реализована один раз в `core/dsp` и переиспользовалась и офлайн-лабом, и будущим мобильным приложением.

## Направление зависимостей

```text
datasets/ -> tools/offline-lab/ -> core/dsp/
apps/mobile/ ---------------------> core/dsp/
core/tests/ ----------------------> core/dsp/
docs/ ----------------------------> контракты репозитория
```

`core/dsp` не должен зависеть ни от мобильного UI-кода, ни от загрузки фикстур с файловой системы, ни от платформенных микрофонных API, ни от демо-данных. Адаптеры могут подавать аудио в DSP-ядро, но не должны сами считать BPM.

Продакшен-источник истины — Rust-крейт в `core/dsp`. Текущий Python/Node-офлайн-анализатор остаётся как детерминированная лаборатория Phase 1 и регрессионный референс до тех пор, пока Rust streaming-движок не достигнет parity.

## Границы модулей

### `core/dsp`

Владеет:

- контрактом Rust-`DspEngine`;
- нормализацией формата сэмплов;
- кольцевым буфером и потоковым состоянием;
- препроцессингом;
- многополосной детекцией онсетов;
- историей онсетов;
- оценкой BPM-кандидатов;
- hitech-нормализацией half-time / double-time;
- скорингом уверенности;
- автоматом состояния захвата;
- публичным контрактом DSP-результата.

Не владеет:

- мобильными разрешениями;
- состоянием UI;
- платформенными аудио-callback'ами;
- декодированием файлов;
- генерацией датасетов;
- фейковыми / демо-значениями BPM.

### `core/tests`

Владеет детерминированными DSP-регрессионными тестами и фикстурами ожидаемых результатов. Любое изменение DSP-алгоритма обязано добавлять или обновлять синтетическое покрытие.

### `tools/offline-lab`

Владеет Python-офлайн-анализатором, генератором синтетических фикстур и раннером отчётов. В Phase 1 может вызывать Python-прототип под `core/dsp`; после Rust-parity обязан вызывать Rust DSP API через ту же границу, что и mobile.

### `core/ffi`

Владеет границей нативных C ABI хэндлов, используемой Flutter / нативным кодом. Управляет временем жизни движка и прокидывает PCM-кадры в Rust DSP, но не должен сам скорить или ранжировать BPM.

### `datasets`

Хранит сгенерированные и курируемые аудио-фикстуры:

- `synthetic/`
- `hitech/`
- `noisy_club/`
- `clipped_mic/`
- `breakdowns/`

Большие лицензированные аудиофайлы не должны коммититься без явной политики работы с датасетами.

### `apps/mobile`

Граница живого Flutter-приложения. Владеет разрешениями микрофона, поведением нативного аудио-моста, рендером результата, отладочным экраном и историей сессий. Не должен содержать независимую BPM-логику.

Слои (Phase 3 шаг 2 — в эфире):

- `lib/dsp/` — типизированная Dart-обёртка над Rust FFI: `bindings.dart` (сырой C ABI), `dsp_result.dart` (типизированный взгляд на JSON-контракт), `engine.dart` (хэндл + stream/poll). Никакой BPM-математики на этой стороне.
- `lib/capture/` — `MicrophoneSource` (тонкая обёртка над `package:record`), `CaptureBridge` (запускает изолят DSP-воркера, прокидывает байтовые PCM-чанки через `SendPort`, переэмитит распарсенный `DspResult` и `CaptureError` в broadcast-стримах), `dsp_worker.dart` (точка входа изолята, владеет FFI-хэндлом, делает конверсию PCM16 → f32, поллит `analyzeJson` на UI-частоте).
- `lib/permissions/` — `PermissionGate` оборачивает `package:permission_handler`, перепроверяет на resume.
- `lib/ui/` — `MainScreen`, `DebugScreen`, `PermissionDeniedScreen`. Оба экрана с данными принимают `Stream<DspResult>` напрямую, поэтому тестируемы изолированно; продакшен-проводка живёт в `main.dart`.
- `lib/monetization/` — фримиум-монетизация (Free / Pro): `PurchasesGateway` (абстракция), `RevenueCatGateway` (единственный импорт `purchases_flutter`), `ProStatusService` (ChangeNotifier singleton), `FeatureFlags` (BPM-диапазон, доступ к debug/history/export), `PaywallScreen`. `config.dart` gitignored; ключи передаются через `--dart-define`.
- `lib/history/` — BPM-история сессии: `BpmHistory` ( capped по длительности/количеству), `SessionHistoryController` (ChangeNotifier, даунсэмплер ~1 Hz), `HistoryScreen`.
- `lib/export/` — экспорт CSV/JSON: чистые билдеры `buildCsv`/`buildJson` + IO `exportCsv`/`exportJson` через `share_plus`.

Пайплайн захвата задокументирован в `docs/MOBILE_AUDIO.md`. UI подписан только на `CaptureBridge.results` — параллельного состояния нет.

### FFI `min_bpm` knob

FFI-слой предоставляет `hitech_bpm_engine_new_with_min_bpm(float min_bpm)` —
обратно-совместимый второй конструктор. Free tier = 170, Pro tier = 155.
`DspConfig.target_bpm_min` уже поддерживается DSP-ядром; изменений в
алгоритме нет. `CaptureBridge` пересоздаётся при смене tier (новый minBpm)
через `ListenableBuilder` на `ProStatusService.instance`.

### v2 компоненты (Phase 1 scaffolding, 2026-06-01)

- `core/dsp/src/genre_preset.rs` — `GenrePreset` enum: 7 жанровых пресетов с BPM-диапазонами и нормализационными порогами. Free: HitechPsy + Psytrance + Darkpsy; Pro: всё + Custom.
- `core/dsp/src/key_analyzer.rs` — `KeyAnalyzer` skeleton: HPCP + Krumhansl-Schmuckler (Phase 2). `KeyResult { key, camelot, confidence }`.
- `core/dsp/src/energy_analyzer.rs` — `EnergyAnalyzer` skeleton: RMS + flux + onset density → уровень 1–10 (Phase 2).
- `DspResult` расширен: `genre_preset`, `key_result: Option<KeyResult>`, `energy_result: Option<EnergyResult>` (все None в Phase 1).
- `lib/features/tap_tempo/` — `TapTempoController`: вспомогательный tap-tempo (Free).
- `lib/features/setlist/` — `SetlistService` + `SetlistEntry`: запись сета с экспортом (Pro).
- ADR-документы: `docs/adr/001-004` — архитектурные решения для v2 компонентов.

## Форма публичного DSP API

Rust DSP-крейт раскрывает стабильное концептуальное API:

```text
DspEngine(config)
DspEngine.push_samples(samples, sample_rate, timestamp_ms)
DspEngine.analyze() -> DspResult
DspEngine.reset()
```

Конфигурация обязана содержать hitech-дефолты:

```text
mode: hitech
target_bpm_min: 170
target_bpm_max: 230
analysis_window_seconds
hop_seconds
sample_rate
lock_min_seconds
stable_min_seconds
```

## Продакшен-правила

- Не строить финальный UI раньше, чем существуют DSP-контракт и синтетические тесты.
- Не фейкать BPM.
- Не хардкодить демо-значения BPM в продакшен-код.
- Сохранять raw- и нормализованных кандидатов.
- Показывать уверенность и список кандидатов в debug-выводе.
- Относиться к мобильному аудио как к входному адаптеру, а не ко второй DSP-реализации.

## Codex-инфраструктура

- `.codex/config.toml` задаёт проектную модель, sandbox и максимум параллельных агентов.
- `.codex/agents/*.toml` определяет ARCHMAN, DSPMAN, MOBILEMAN, QAMAN, PERFMAN, REVIEWMAN и DOCMAN.
- `.codex/plans/PLANS.md` — обязательный шаблон планирования для нетривиальной работы.
- `.agents/skills/*/SKILL.md` хранит переиспользуемые локальные навыки для bootstrap, DSP, мобильного аудио, QA-датасетов и review-гейтов.

## Основные риски

- UI-first работа может создать фейковую уверенность ещё до того, как существует детектор.
- Плотный hitech-материал может породить half-time / double-time неоднозначность.
- Клиппинг микрофона и AGC могут исказить силу онсетов.
- Шум-без-сигнала и брейкдауны могут создать ложную периодичность, если уверенность не консервативна.
- Дрифт частоты дискретизации мобильного и задержка callback'ов могут повлиять на тайминг захвата.
