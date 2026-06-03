# CLAUDE.md — TrackScope

DSP-first мобильный детектор BPM для hitech / psytrance (целевой диапазон 155–230 BPM). Вход — микрофон, без tap-tempo.

## Стек и раскладка

- `core/dsp/`         — Rust DSP-крейт (источник истины) + Python-референс (`tempo.py`, `synthetic.py`), используется в тестах Phase 1.
- `core/ffi/`         — Нативный C ABI для моста Flutter ↔ Rust DSP.
- `core/tests/`       — Python-регрессия, parity-тесты, синтетические фикстуры.
- `tools/offline-lab/` — Python-CLI-анализатор, генератор фикстур, QA-отчёт.
- `apps/mobile/`      — Flutter-оболочка (микрофон, отладочный экран, история). Никакой BPM-математики здесь.
- `datasets/`         — фикстуры synthetic / hitech / noisy_club / clipped_mic / breakdowns.
- `docs/`             — архитектура, DSP-алгоритм, QA-матрица, roadmap, заметки по мобильному аудио.

## Контракт DspResult (не ломать)

```ts
type LockState = "SEARCHING" | "LOCKING" | "STABLE" | "UNSTABLE" | "BREAKDOWN" | "CLIPPED_MIC" | "NOISE_ONLY";
type TempoRelation = "raw" | "main" | "half_time" | "double_time" | "normalized_from_half" | "normalized_from_double";

interface DspResult {
  primary_bpm: number | null;   // null, если сигнал — тишина/шум/клиппинг/недостоверен
  confidence: number;            // 0.0..1.0
  lock_state: LockState;
  signal_quality: SignalQuality; // input_level_dbfs, clipping, clipped_frame_ratio, noise_level, snr_estimate_db, silence, breakdown_likely
  candidates: TempoCandidate[];  // raw + нормализованные, со score, raw_score, stability_score, range_score, relation, source_bpm
  timing: DspTiming;
  debug?: DspDebug;
}
```

Правила:
- `primary_bpm` остаётся `null`, пока уверенность не превысит порог захвата.
- Тишина и шум-без-сигнала НИКОГДА не должны достигать `STABLE`.
- Вход с клиппингом обязан выставить `clipping: true`; при сильном клиппинге — подавить `primary_bpm` и предпочесть `CLIPPED_MIC`.
- Брейкдауны проседают уверенность; не сохраняйте устаревший `STABLE`.

Полная спецификация: @docs/DSP_ALGORITHM.md

## Hitech-нормализация кандидатов

- Внутренний поисковый диапазон ~80–460 BPM, чтобы half/double-ловушки были видны до нормализации.
- Если raw-кандидат < 130 BPM — также эмитим `bpm * 2` с relation `normalized_from_half`.
- Если raw-кандидат > 260 BPM — также эмитим `bpm / 2` с relation `normalized_from_double`.
- Сохраняем raw, half-time, double-time и нормализованные кандидаты в списке.
- Основной кандидат выбирается по совокупному score (evidence + range fit + stability + signal quality), а не только по диапазону.
- В hitech-режиме raw 100 BPM не должен финализироваться, если нормализованный 200 BPM имеет более сильное evidence.

## Anti-fake правила (не подлежат обсуждению)

- НЕТ хардкодных продакшен-значений BPM.
- НЕТ случайных BPM, НЕТ фейкового пульса по таймеру, НЕТ демо-BPM в продакшен-путях.
- НЕТ `STABLE` без онсет/темпо-доказательств и гейта качества сигнала.
- НИКОГДА не скрывать half-time / double-time кандидатов — они всегда видимы.
- НИКОГДА не возвращать одно BPM без сопровождающей уверенности.
- Уверенность вычисляется из evidence (чёткость онсетов, prominence пика, гармоническая поддержка, стабильность, попадание в диапазон, качество сигнала, штраф за неоднозначность).
- Mobile/UI никогда не считает BPM — только рендерит DSP-контракт.

## Воркфлоу любой задачи

1. Прочитайте @AGENTS.md и этот файл перед началом.
2. Классифицируйте сложность (low / medium / high) и домены (dsp / mobile / ui / qa / docs / performance / security).
3. Для medium/high — сначала план по шаблону @.codex/plans/PLANS.md. Команда `/plan` скаффолдит его.
4. Выбирайте субагентов и навыки явно по релевантности:
   - DSP-работа → `@dspman`, навык `dsp-tempo-analysis`.
   - Mobile/Flutter/FFI → `@mobileman`, навык `mobile-audio-input`.
   - Test/QA/датасеты → `@qaman`, навык `qa-audio-dataset`.
   - Архитектура и контракты → `@archman`.
   - Perf/задержка/CPU → `@perfman`.
   - Документация / релиз-ноты → `@docman`.
   - Перед мерджем → `@reviewman` + навык `review-gate`.
5. Имплементируйте минимально; тесты добавляются/обновляются рядом с изменением. DSP-изменения требуют синтетического покрытия.
6. Прогоните релевантные валидационные команды до отчёта о готовности.
7. Финальный отчёт: изменённые файлы, что реализовано, как тестировалось, известные ограничения, рекомендуемый следующий патч.

## Тулчейн

Используйте явные бинарники (см. @AGENTS.md):

- `/opt/homebrew/opt/nodejs/bin/node`
- `/opt/homebrew/opt/rust/bin/cargo`

## Команды сборки и тестов

```sh
# Python-юнит + parity + офлайн-DSP-регрессия
python3 -m unittest discover core/tests

# Rust-воркспейс (DSP + FFI + python parity)
/opt/homebrew/opt/rust/bin/cargo test --workspace

# Node-офлайн-анализатор parity
/opt/homebrew/opt/nodejs/bin/node --test core/dsp/index.test.js

# Детерминированный офлайн-QA-отчёт (выход с не-нулевым кодом при регрессии)
python3 tools/offline-lab/offline_lab.py report

# Flutter (становится обязательным после интеграции мобильного моста)
flutter test
flutter analyze
```

## Ссылки

- @AGENTS.md
- @docs/ARCHITECTURE.md
- @docs/DSP_ALGORITHM.md
- @docs/QA_MATRIX.md
- @docs/ROADMAP.md
- @docs/GLOSSARY.md
- @.codex/plans/PLANS.md

## Маппинг Codex ↔ Claude Code

Легаси Codex-агенты в `.codex/agents/*.toml` маппятся 1:1 на субагентов Claude Code в `.claude/agents/*.md`:

| Codex (TOML)  | Claude Code (md) | Фокус                                            |
| ------------- | ---------------- | ------------------------------------------------ |
| ARCHMAN       | archman          | архитектура, границы модулей, контракты          |
| DSPMAN        | dspman           | DSP-алгоритмы, parity Rust ↔ Python              |
| MOBILEMAN     | mobileman        | Flutter-оболочка, FFI, захват микрофона          |
| QAMAN         | qaman            | offline-lab, матрица датасетов, регрессионные    |
| PERFMAN       | perfman          | задержка, CPU, аллокации, батарея на мобильном   |
| REVIEWMAN     | reviewman        | review-гейт перед мерджем                        |
| DOCMAN        | docman           | документация, changelog, релиз-ноты              |

`.codex/` и `.agents/` сохранены как легаси-референс из исходного окружения OpenAI Codex — не удаляйте и не модифицируйте.
