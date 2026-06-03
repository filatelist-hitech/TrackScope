# Execution Plan: Claude Code Infrastructure Setup

## 1. Task classification

- **complexity:** medium
- **domains:** docs, (читаемость для dsp / mobile / qa — только в documentation-файлах)

DSP-логика, BPM-математика, FFI-контракт не затрагиваются. Anti-fake-правила
неприменимы напрямую, но project-map и агенты обязаны корректно
отражать анти-фейковые инварианты проекта.

---

## 2. Agents

| Агент | Зачем |
|---|---|
| (никаких субагентов) | Задача — создание инфраструктурных файлов; это docs-работа одного слоя, без DSP-изменений и без мерджа |

`@reviewman` рекомендован перед мерджем, но не требуется для написания плана.

---

## 3. Files to inspect

**Уже прочитано (картирование проекта):**

```
.claude/                          — существует; agents/, skills/, commands/, settings.json, settings.local.json
.claude/agents/                   — archman, docman, dspman, mobileman, perfman, qaman, reviewman (7 агентов)
.claude/skills/                   — dsp-tempo-analysis, mobile-audio-input, project-bootstrap,
                                    qa-audio-dataset, review-gate, ui-preview (6 навыков)
.claude/commands/                 — bootstrap-task, parity, plan, preview, qa-report, review-gate (6 команд)
CLAUDE.md                         — корневой (главный источник знаний; 128 строк)
AGENTS.md                         — (193 строки; полные правила агентов)
docs/ARCHITECTURE.md              — границы модулей
docs/DSP_ALGORITHM.md             — полная спецификация алгоритма
docs/ROADMAP.md                   — статус фаз 1–12
docs/QA_MATRIX.md                 — QA-матрица
core/dsp/src/lib.rs               — Rust DSP-ядро
core/dsp/src/bin, energy_analyzer.rs, genre_preset.rs, key_analyzer.rs
core/ffi/src/, core/ffi/include/  — C ABI мост
apps/mobile/lib/                  — Flutter (capture, dsp, export, features, history,
                                    monetization, navigation, permissions, screens,
                                    settings, theme, ui, viz, widgets)
scripts/build_ios_native.sh       — iOS Rust сборка
scripts/build_android_native.sh   — Android Rust сборка (arm64/armeabi/x86_64)
apps/mobile/android/              — Gradle сборка
apps/mobile/ios/                  — Podfile / Xcode
/Users/filatelist/.claude/projects/.../memory/  — персистентная память (уже наполнена)
```

**Нужно прочитать перед имплементацией:**

```
.claude/settings.json             — текущие permissions / hooks
.claude/agents/dspman.md          — эталон формата агентов
.claude/skills/dsp-tempo-analysis/SKILL.md  — эталон формата навыков
```

---

## 4. Current behavior

**Что уже есть:**
- 7 специализированных агентов в `.claude/agents/` — роли строго разделены (dspman, mobileman и т.д.)
- 6 навыков в `.claude/skills/`; 6 команд в `.claude/commands/`
- Корневые `CLAUDE.md` и `AGENTS.md` — исчерпывающая документация проекта
- Авто-память работает через `/Users/filatelist/.claude/projects/.../memory/`
- `settings.json` существует (содержимое недоступно сейчас из-за classifier-блока)
- `.claude/docs/` — **не существует**
- `.claude/hooks/` — **не существует**
- Агентов `codebase-guide`, `flutter-reviewer`, `rust-dsp-reviewer`, `fresh-eyes` — **нет**
- Навыка `full-audit` — **нет**
- `docs/plans/` — **создана только что** (пустая)

**Что отсутствует:**
- Сводная карта проекта для быстрой ориентации (`.claude/docs/project-map.md`)
- Агент-гид по кодовой базе с широким охватом (vs. узкоспециализированные агенты)
- Flutter-ревьюер, Rust-DSP-ревьюер, fresh-eyes агенты
- Навык полного аудита
- Session-start hook с контекстом ветки и версий
- Pre-tool-use hook блокировки деструктивных команд

---

## 5. Target behavior

После имплементации:
1. **`.claude/agents/codebase-guide.md`** — широкий гид по всей кодовой базе (дополняет, не заменяет специализированных агентов)
2. **`.claude/agents/flutter-reviewer.md`** — Flutter-качество: widget tree, rebuild, State management, performance
3. **`.claude/agents/rust-dsp-reviewer.md`** — Rust DSP: FFT, BPM detection, FFI safety, allocations, SIMD
4. **`.claude/agents/fresh-eyes.md`** — независимый архитектурный взгляд без предвзятости текущих соглашений
5. **`.claude/skills/full-audit/SKILL.md`** — навык запуска `flutter analyze` + `cargo clippy` + security grep + отчёт
6. **`.claude/hooks/session-context.sh`** + запись в `settings.json` — при старте сессии выводит ветку, Flutter/Rust версии, счётчик изменённых файлов
7. **`.claude/hooks/block-dangerous.sh`** + запись в `settings.json` — PreToolUse-хук, блокирует `rm -rf`, `git push --force`, `git reset --hard`, `sudo rm`, `chmod 777`
8. **`.claude/docs/project-map.md`** — MAGIC DOC с картой проекта (автоматически заполнен по результатам анализа)
9. **`.claude/settings.json`** — расширен правильными `hooks` entries (SessionStart, PreToolUse); НЕ содержит несуществующих полей

---

## 6. Data contracts

**Критически важно: нет изменений в DSP-контракте (`DspResult`), FFI API, Flutter-слоях.**

Claude Code agent frontmatter (реальные поля):
```yaml
---
name: <kebab-case>
description: <одна строка для auto-select>
tools: [Read, Grep, Glob, Bash, ...]
color: green | blue | red | purple | ...
model: opus | sonnet | haiku          # опционально
---
```

Поля `memory: project`, `effort: high`, `omitClaudeMd: true` — **не поддерживаются** Claude Code agent frontmatter. Их нужно адаптировать:
- `omitClaudeMd: true` → реализуется через инструкцию в теле агента: "Do not load project CLAUDE.md files"
- `effort: max` → нет эквивалента; можно задать `model: opus` для максимальной мощи
- `memory: project` → Claude Code агенты используют ту же память сессии; нет специального поля

Claude Code settings.json hooks format (реальный):
```json
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "..."}]}],
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "..."}]}]
  }
}
```

**НЕ существуют:**
- `autoMemoryEnabled`, `autoDreamEnabled` — не реальные поля settings.json
- `asyncRewake` — не реальный API
- Хук, возвращающий `permissionDecision=allow` из bash-скрипта — **является попыткой обхода permission системы** и блокируется auto-mode classifier'ом. Вместо этого read-only инструменты разрешаются через `permissions.allow` массив в settings.json.

---

## 7. Implementation steps

### Шаг 1 — Прочитать эталонные файлы (before writing)
- `.claude/settings.json` — понять текущую структуру
- `.claude/agents/dspman.md` — эталон формата
- `.claude/skills/dsp-tempo-analysis/SKILL.md` — эталон формата навыка

### Шаг 2 — Создать `.claude/docs/` и `project-map.md`
Заполнить MAGIC DOC с реальной картой: Flutter lib layout, Rust src, FFI, build scripts, Android/iOS пути.

### Шаг 3 — Создать агента `codebase-guide.md`
Широкий кросс-слойный гид. Tools: Read, Grep, Glob, Bash. Инструкции: ориентация по всем модулям, не вычисляет BPM.

### Шаг 4 — Создать агента `flutter-reviewer.md`
Flutter quality reviewer. Tools: Read, Grep, Glob, Bash. Фокус: widget tree, State management (Provider/ChangeNotifier), rebuild, memory leaks, performance.

### Шаг 5 — Создать агента `rust-dsp-reviewer.md`
Rust DSP reviewer. Tools: Read, Grep, Glob, Bash. model: opus. Фокус: FFT корректность, BPM detection logic, FFI safety (`unsafe`, `unwrap`, lifetime), allocations.

### Шаг 6 — Создать агента `fresh-eyes.md`
Independent reviewer. Tools: Read, Grep, Glob. Тело: "Do not load project CLAUDE.md context. Evaluate architecture independently." Фокус: scalability, maintainability, future feature support.

### Шаг 7 — Создать навык `full-audit/SKILL.md`
Запускает: `flutter analyze`, `/opt/homebrew/opt/rust/bin/cargo clippy --workspace`, grep на `TODO|FIXME|unwrap()|expect()|panic!|unsafe`, проверку Gradle и Podfile. Формирует `.claude/docs/audit-report.md`.

### Шаг 8 — Создать хук-скрипт `session-context.sh`
Выводит: ветку git, количество modified файлов, версию Flutter, версию Rust, наличие изменений в `pubspec.yaml`, `Cargo.toml`, `build.gradle`, `Podfile`. Chmod +x.

### Шаг 9 — Создать хук-скрипт `block-dangerous.sh`
PreToolUse hook для Bash: проверяет stdin JSON на наличие паттернов `rm -rf`, `sudo rm`, `chmod 777`, `git push --force`, `git reset --hard`. При совпадении выходит с кодом 2 (блокирует) и пишет причину в stderr.

### Шаг 10 — Обновить `settings.json`
Добавить в существующий settings.json:
- `hooks.SessionStart` → `session-context.sh`
- `hooks.PreToolUse` (matcher Bash) → `block-dangerous.sh`
- `permissions.allow` расширить безопасными read-only командами

**Не добавлять:** `autoMemoryEnabled`, `autoDreamEnabled`, `autoMode` — несуществующие поля или уже управляемые через системный авто-режим.

### Шаг 11 — Верификация
```sh
# Проверить что новые агенты валидны (нет синтаксических ошибок frontmatter)
head -10 .claude/agents/codebase-guide.md
head -10 .claude/agents/flutter-reviewer.md
# Проверить что хуки исполняемы
bash .claude/hooks/session-context.sh
bash .claude/hooks/block-dangerous.sh  # должен упасть без stdin
# Прогнать существующие тесты (убедиться, что ничего не сломано)
python3 -m unittest discover core/tests 2>&1 | tail -5
```

---

## 8. Tests

Инфраструктурные файлы (агенты, навыки, хуки) не требуют специальных тестовых фреймворков. Верификация — инструментальная:

```sh
# 1. Frontmatter agents — проверить синтаксис
for f in .claude/agents/*.md; do head -10 "$f"; done

# 2. Session context hook
bash .claude/hooks/session-context.sh

# 3. Block-dangerous — проверить что блокирует rm -rf
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
  | bash .claude/hooks/block-dangerous.sh; echo "exit: $?"

# 4. Block-dangerous — проверить что пропускает безопасное
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  | bash .claude/hooks/block-dangerous.sh; echo "exit: $?"

# 5. Убедиться, что DSP-тесты по-прежнему зелёные (ничего не сломано)
python3 -m unittest discover core/tests 2>&1 | tail -3
/opt/homebrew/opt/rust/bin/cargo test --workspace 2>&1 | tail -5
```

---

## 9. Risks

| Риск | Вероятность | Митигация |
|---|---|---|
| `settings.json` уже содержит `hooks` → перезапишем существующие | средняя | Прочитать файл перед записью; merge, а не replace |
| Хук `session-context.sh` падает если git/flutter/cargo не в PATH | средняя | Использовать явные бинарники из AGENTS.md; `command -v` guard |
| `block-dangerous.sh` блокирует легитимные тесты через `expect()` в cargo test output | низкая | Grep только в `tool_input.command`, не в stdout; `expect()` — Rust строка, не bash |
| Агент `fresh-eyes` с `omitClaudeMd` (несуществующее поле) молча игнорируется Claude Code | низкая | Реализовать через инструкцию в body агента |
| Дублирование с уже существующими агентами (dspman ↔ rust-dsp-reviewer) | средняя | Явно разграничить: dspman = имплементация DSP, rust-dsp-reviewer = статический анализ качества кода |
| Classifier блокирует auto-approve hooks | высокая | **НЕ создавать** hooks возвращающие `permissionDecision=allow`; использовать `permissions.allow` в settings.json вместо этого |

---

## 10. Done when

- [ ] `.claude/agents/codebase-guide.md` — создан, frontmatter корректный
- [ ] `.claude/agents/flutter-reviewer.md` — создан
- [ ] `.claude/agents/rust-dsp-reviewer.md` — создан  
- [ ] `.claude/agents/fresh-eyes.md` — создан
- [ ] `.claude/skills/full-audit/SKILL.md` — создан
- [ ] `.claude/hooks/session-context.sh` — создан, исполняемый, выводит ветку/версии
- [ ] `.claude/hooks/block-dangerous.sh` — создан, exit 2 на `rm -rf` / `git push --force`
- [ ] `.claude/docs/project-map.md` — создан с реальной картой проекта
- [ ] `.claude/settings.json` — обновлён с hooks SessionStart + PreToolUse (без фейковых полей)
- [ ] `bash .claude/hooks/block-dangerous.sh` блокирует `rm -rf /` → exit code 2
- [ ] `python3 -m unittest discover core/tests` — по-прежнему зелёный
- [ ] Никаких изменений в `core/dsp/`, `core/ffi/`, `apps/mobile/lib/`
- [ ] `docs/plans/claude-code-infrastructure.md` — этот план сохранён

---

## Адаптации относительно запроса

Следующие элементы из оригинального промпта адаптированы под реальный Claude Code API:

| Запрошено | Проблема | Реализовано вместо |
|---|---|---|
| `.claude/hooks/*.sh` с `permissionDecision=allow` | Обход permission system — блокируется classifier | `permissions.allow` массив в settings.json |
| `asyncRewake` в block script | Не существует в Claude Code API | Exit code 2 = блокировка в PreToolUse |
| `autoMemoryEnabled: true` | Не существует в settings.json | Память уже работает автоматически через авто-память |
| `autoDreamEnabled: true` | Не существует в settings.json | Нет эквивалента |
| `memory: project` в agent frontmatter | Не поддерживается | Описание в body агента |
| `effort: high/max` в agent frontmatter | Не поддерживается | `model: opus` для max-effort агентов |
| `omitClaudeMd: true` | Не поддерживается | Инструкция "ignore CLAUDE.md" в body |
| `.claude/CLAUDE.md` как главный источник знаний | Корневой `CLAUDE.md` уже существует и является source of truth | Создать `.claude/docs/project-map.md` как MAGIC DOC; не дублировать CLAUDE.md |
