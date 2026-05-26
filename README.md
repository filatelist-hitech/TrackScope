# hitech-bpm-radar

DSP-first определение BPM для hitech / psytrance — автоматический темп с микрофона в диапазоне 170–230 BPM.

Это не tap-tempo и не UI-демо. Первая продакшен-веха — детерминированное DSP-ядро с синтетическими тестами и офлайн-анализатором. Захват микрофона и UI на мобильном устройстве подключаются только после стабилизации DSP-контракта.

## Продуктовый контракт

Продукт обязан сообщать:

- определённый BPM, либо `null`, если сигналу нельзя доверять;
- уверенность от `0.0` до `1.0`;
- состояние захвата (`lock state`);
- BPM-кандидаты со score;
- связи half-time и double-time;
- предупреждения о качестве сигнала;
- историю сессий — после интеграции с мобильным приложением.

Продакшен-логика никогда не хардкодит демо-значения BPM и не выдумывает темп для тишины, шума-без-сигнала, перегруженного микрофона или брейкдаунов.

## Структура репозитория

```text
apps/mobile/       Flutter-оболочка, сценарий выдачи разрешений микрофона, аудио-мост и рендер результата.
core/dsp/          Rust DSP-ядро + текущий Python/Node-прототип офлайн-анализатора, используемый тестами Phase 1.
core/ffi/          Граница нативного моста для интеграции с Flutter / мобильным шеллом.
core/tests/        Синтетические фикстуры, регрессионные тесты, приёмочные DSP-тесты.
tools/offline-lab/ Python-офлайн-анализатор, генератор фикстур, отчёты сравнения алгоритмов.
datasets/          Хранилище синтетических и реальных аудио-фикстур.
docs/              Архитектура, DSP-алгоритм, QA-матрица, roadmap, заметки по мобильному аудио, релизный чеклист.
.codex/            Конфиг Codex, role-агенты, шаблон планов.
.agents/skills/    Переиспользуемые навыки проекта для локальных воркфлоу с агентами.
```

## Текущая фаза

Phase 3, шаг 2 (мобильный мост в эфире): Flutter-приложение захватывает звук с микрофона через `package:record`, отправляет PCM в отдельный изолят DSP-воркера, который владеет Rust-FFI-хэндлом, и рендерит скользящие снэпшоты `DspResult` через `StreamBuilder` на живом BPM-экране + отладочном экране.

Rust-крейт в `core/dsp/` — продакшен-источник истины: он содержит извлечение онсетов, оценку темпа автокорреляцией, hitech-нормализацию кандидатов, скоринг уверенности и классификацию состояния захвата на нативном Rust. `core/dsp/tempo.py` и `core/dsp/synthetic.py` остаются как читаемая алгоритмическая референс-реализация и продолжают обслуживать офлайн-отчёт Python.

### Запуск мобильного приложения

```sh
# 1. Собрать Rust FFI dylib (один раз на машину, дальше кэшируется cargo)
/opt/homebrew/opt/rust/bin/cargo build --release -p hitech-bpm-ffi

# 2. Подтянуть Flutter-зависимости
cd apps/mobile
/opt/homebrew/bin/flutter pub get

# 3. Статика + юнит-тесты
/opt/homebrew/bin/flutter analyze
/opt/homebrew/bin/flutter test

# 4. Запуск на подключённом устройстве или работающем симуляторе/эмуляторе
/opt/homebrew/bin/flutter run
```

Rust dylib подтягивается в Android/iOS-приложение через пайплайн плагинов платформы (`record_darwin`, `permission_handler_apple` подхватываются Flutter автоматически). Для тестового раннера `apps/mobile/test/helpers/native_library.dart` сам вызывает `cargo build`, если dylib отсутствует.

Перед мерджем мобильного моста в `stage` пройдите чеклист устройств в [docs/MANUAL_TEST_CHECKLIST.md](docs/MANUAL_TEST_CHECKLIST.md).

### Воркфлоу тестов

- `cargo test --workspace` — **герметичный**: не вызывает `python3`. Регрессионное покрытие на Rust лежит в `core/dsp/tests/offline_contract.rs` и использует общий модуль фикстур `core/dsp/tests/common/mod.rs`.
- `python3 -m unittest discover core/tests` — Python-референс-сьют.
- `node --test core/dsp/index.test.js` — Node-офлайн-анализатор.
- `python3 tools/offline-lab/offline_lab.py report` — детерминированный офлайн-QA-отчёт.
- `python3 tools/offline-lab/parity.py` — опциональная сверка дрифта Python ↔ Rust (вызывает Rust-бинарь `analyze_wav`; не входит в `cargo test`).

## Критерии приёмки

- Чистые синтетические фикстуры: ±1 BPM на 170, 180, 190, 200 и 220 BPM.
- Шумный микрофонный вход: ±2–4 BPM при адекватном качестве сигнала.
- Первый рабочий захват: до 6 секунд.
- Стабильный захват: до 12 секунд.
- Тишина и шум-без-сигнала не должны достигать `STABLE`.
- В hitech-режиме half-time-кандидат 100 BPM не должен побеждать более сильного нормализованного кандидата 200 BPM.

## Документация

- [Архитектура](docs/ARCHITECTURE.md)
- [DSP-алгоритм](docs/DSP_ALGORITHM.md)
- [QA-матрица](docs/QA_MATRIX.md)
- [Roadmap](docs/ROADMAP.md)
- [Заметки по мобильному аудио](docs/MOBILE_AUDIO.md)
- [Ручной тест-чеклист (mobile)](docs/MANUAL_TEST_CHECKLIST.md)
- [Релизный чеклист](docs/RELEASE_CHECKLIST.md)
- [Глоссарий терминов](docs/GLOSSARY.md)

## Работа с Claude Code

Репозиторий настроен под нативный Claude Code параллельно с легаси-окружением Codex.

Где смотреть:

- `CLAUDE.md` — память проекта: DSP-контракт, правила hitech-нормализации, anti-fake правила, воркфлоу, команды сборки и тестов.
- `.claude/agents/` — 7 субагентов (`archman`, `dspman`, `mobileman`, `qaman`, `perfman`, `reviewman`, `docman`), зеркалирующие роли Codex `.codex/agents/*.toml`.
- `.claude/skills/` — 5 навыков (`project-bootstrap`, `dsp-tempo-analysis`, `mobile-audio-input`, `qa-audio-dataset`, `review-gate`), зеркалирующие `.agents/skills/*/SKILL.md`.
- `.claude/commands/` — slash-команды: `/plan`, `/qa-report`, `/parity`, `/review-gate`, `/bootstrap-task`.
- `.claude/settings.json` — разрешения и хуки проекта. Личные оверрайды — в `.claude/settings.local.json` (gitignore).

Типичные воркфлоу:

- Любую нетривиальную задачу начинаем с `/bootstrap-task <описание>` — она читает `AGENTS.md` + `CLAUDE.md`, классифицирует сложность, подбирает релевантных субагентов и навыки и скаффолдит план для medium/high-задач.
- `/plan <название>` генерирует полный execution-plan по шаблону `.codex/plans/PLANS.md`.
- `/qa-report` запускает `python3 tools/offline-lab/offline_lab.py report` и суммирует регрессии и нарушения состояний захвата.
- `/parity` гоняет parity-тесты Rust + Python и репортит дрифт `primary_bpm` / `confidence`.
- `/review-gate` запускает субагент `reviewman` по staged + unstaged-диффу перед мерджем.

Субагенты и навыки сопоставляются по `description` и активируются автоматически по триггерам; их также можно вызвать явно через `@agent-name` или сослаться на навык по имени.

> `.codex/` и `.agents/` сохранены как легаси-референс из исходного окружения OpenAI Codex. Не удаляйте и не модифицируйте их. Маппинг агентов Codex → субагентов Claude Code описан внизу `CLAUDE.md`.
