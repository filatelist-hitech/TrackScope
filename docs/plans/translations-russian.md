# План — перевод проектной прозы на русский язык

## 1. Классификация задачи

- сложность: medium-high
- домены: docs, mobile (UI strings), dsp (комментарии), qa (комментарии), .claude (тела)
- характер: behavior-preserving translation, без рефакторинга

## 2. Агенты

- `@docman` — переводит `README.md`, `AGENTS.md`, `CLAUDE.md`, `CHANGELOG.md`, всё в `docs/`, per-module README, тела в `.claude/agents/*.md`, `.claude/skills/*/SKILL.md`, `.claude/commands/*.md`.
- `@mobileman` — переводит пользовательские строки в `apps/mobile/lib/**/*.dart`, комментарии в Dart-файлах, `NSMicrophoneUsageDescription` в `apps/mobile/ios/Runner/Info.plist`.
- `@reviewman` — финальный аудит: identifier audit, отсутствие переводов wire-format ключей, лейблов lock-states маппятся, логи остались английскими.

## 3. Файлы (инвентарь)

### Документация (15)
- `README.md`, `AGENTS.md`, `CLAUDE.md`, `CHANGELOG.md`
- `apps/mobile/README.md`, `core/dsp/README.md`, `core/ffi/README.md`, `core/tests/README.md`, `datasets/README.md`, `tools/offline-lab/README.md`
- `docs/ARCHITECTURE.md`, `docs/DSP_ALGORITHM.md`, `docs/MANUAL_TEST_CHECKLIST.md`, `docs/MOBILE_AUDIO.md`, `docs/QA_MATRIX.md`, `docs/RELEASE_CHECKLIST.md`, `docs/ROADMAP.md`
- `docs/plans/rust-native-and-authoritative-parity.md`
- `docs/GLOSSARY.md` (уже на русском — оставить как авторитативный источник терминов)
- НЕ трогать: `apps/mobile/ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md` (Apple-generated)

### `.claude/` (17)
- `.claude/agents/{archman,docman,dspman,mobileman,perfman,qaman,reviewman}.md` (frontmatter `name` английский, `description` переводится, тело переводится)
- `.claude/skills/*/SKILL.md` (5 файлов)
- `.claude/commands/*.md` (5 файлов)
- НЕ трогать: `.claude/settings.json`, `.claude/settings.local.json`

### Rust код (8)
- `core/dsp/src/lib.rs`, `core/dsp/src/bin/analyze_wav.rs`
- `core/dsp/tests/common/mod.rs`, `core/dsp/tests/offline_contract.rs`, `core/dsp/tests/streaming.rs`, `core/dsp/tests/streaming_perf.rs`
- `core/ffi/src/lib.rs`, `core/ffi/tests/ffi_contract.rs`

### Python код (8)
- `core/dsp/__init__.py`, `core/dsp/synthetic.py`, `core/dsp/tempo.py`
- `core/tests/helpers/__init__.py`, `core/tests/helpers/dsp_lab_runner.py`, `core/tests/helpers/synthetic_fixtures.py`
- `core/tests/test_offline_dsp_contract.py`, `core/tests/test_offline_dsp_lab.py`, `core/tests/test_synthetic_fixtures.py`
- `tools/offline-lab/analyze.py`, `tools/offline-lab/offline_lab.py`, `tools/offline-lab/parity.py`

### Node / JS код (3)
- `core/dsp/index.js`, `core/dsp/index.test.js`
- `tools/offline-lab/analyze.js`, `tools/offline-lab/generate-fixture.js`

### Dart (12)
- `apps/mobile/lib/main.dart`
- `apps/mobile/lib/capture/{capture_bridge,capture_messages,dsp_worker,microphone_source}.dart`
- `apps/mobile/lib/dsp/{bindings,dsp_result,engine}.dart`
- `apps/mobile/lib/permissions/permission_gate.dart`
- `apps/mobile/lib/ui/{debug_screen,main_screen,permission_denied_screen}.dart`

### Платформенные файлы (1)
- `apps/mobile/ios/Runner/Info.plist` — только значение `NSMicrophoneUsageDescription`

## 4. Текущее поведение

Вся проектная проза, комментарии и UI-строки — на английском (наследие Codex-этапа). Команда работает на русском, поэтому хочет переключить человекочитаемые поверхности.

## 5. Целевое поведение

Russian throughout всю прозу. Идентификаторы кода, имена JSON-полей контракта, значения enum `LockState`, имена фикстур, лог-сообщения, slash-команды, имена subagent — остаются английскими.

## 6. Контракты данных

См. CONSTRAINTS в задании. Inviolable:
- JSON-поля: `primary_bpm`, `confidence`, `lock_state`, `signal_quality`, `candidates`, `relation`, `score`, `source_bpm`, `bpm`, `input_level_dbfs`, `clipping`, `noise_level`, `snr_estimate_db`, `clipped_frame_ratio`, и т.д.
- enum значения: `SEARCHING`, `LOCKING`, `STABLE`, `UNSTABLE`, `BREAKDOWN`, `CLIPPED_MIC`, `NOISE_ONLY`
- relation значения: `main`, `raw`, `half_time`, `double_time`, `normalized_from_half`, `normalized_from_double`
- Имена фикстур: `clean_170`, `half_time_trap_100`, и т.д.

## 7. Шаги реализации

1. Зафиксировать baseline всех тестов (cargo, pytest, node, offline-lab, flutter analyze).
2. Перевод docs (`@docman`).
3. Перевод `.claude/` тел (`@docman`).
4. Перевод комментариев в Rust/Python/JS (`@docman` + ручная сверка).
5. Перевод Dart UI + комментариев (`@mobileman`).
6. Перевод `Info.plist` mic rationale (`@mobileman`).
7. Перевод `CHANGELOG.md` + новая `[Unreleased]` запись.
8. Identifier audit grep (до/после).
9. Прогон всех тестов — сравнение с baseline.
10. `@reviewman` review gate.

## 8. Тесты (acceptance)

Baseline и финальный прогон должны совпадать:
- `/opt/homebrew/opt/rust/bin/cargo test --workspace`
- `python3 -m unittest discover core/tests`
- `/opt/homebrew/opt/nodejs/bin/node --test core/dsp/index.test.js`
- `python3 tools/offline-lab/offline_lab.py report`
- `cd apps/mobile && flutter analyze && flutter test`

## 9. Риски

- Случайный перевод идентификатора → break tests. Митигация: identifier audit grep до/после.
- Тест ассертит литерал переведённой строки. Митигация: при обнаружении — оставить исходную строку английской или обновить тест (документировать каждый случай).
- Несоответствие терминов между файлами. Митигация: `docs/GLOSSARY.md` как single source of truth.
- Грамматический сдвиг markdown структуры (заголовки, таблицы). Митигация: переводить только текст, оставлять разметку как есть.

## 10. Done when

- Все markdown в репо (кроме `.codex/`, `.agents/`, `target/`, `node_modules/`, Apple-generated) на русском.
- Тела `.claude/agents/*.md`, `.claude/skills/*/SKILL.md`, `.claude/commands/*.md` на русском; `name` во frontmatter — английский, `description` переведён.
- Все комментарии в `core/`, `tools/`, `apps/mobile/lib/` на русском. Логи английские.
- Все user-visible Dart строки на русском. `Info.plist` mic rationale на русском.
- `CHANGELOG.md` на русском, добавлена `[Unreleased]` запись.
- Identifier audit greps дают идентичный результат до/после.
- Все тесты дают идентичные результаты до/после.

## Глоссарий

Авторитативный источник — [docs/GLOSSARY.md](../GLOSSARY.md). Сокращённая выжимка ключевых терминов для дисциплины:

| English | Русский |
|---|---|
| onset | онсет |
| onset envelope | огибающая онсетов |
| tempo | темп |
| BPM | BPM (не переводится) |
| confidence | уверенность |
| signal quality | качество сигнала |
| clipping | клиппинг |
| breakdown | брейкдаун |
| half-time / double-time | половинный темп / удвоенный темп |
| lock | захват |
| lock state | состояние захвата |
| streaming | потоковый (прилаг.) / `streaming` в backticks (сущ.) |
| frame | кадр |
| hop / hop size | шаг / размер шага |
| ring buffer | кольцевой буфер |
| sample rate | частота дискретизации |
| FFI | FFI (не переводится) |
| isolate (Dart) | изолят |
| fixture | фикстура |
| dataset | датасет |
| pipeline | пайплайн |
| latency | задержка |
| hot path | горячий путь |

UI labels для lock states (только в UI; enum value в данных остаётся английским):
- `SEARCHING` → «поиск»
- `LOCKING` → «захват»
- `STABLE` → «стабильно»
- `UNSTABLE` → «нестабильно»
- `BREAKDOWN` → «брейк»
- `CLIPPED_MIC` → «перегруз микрофона»
- `NOISE_ONLY` → «только шум»
