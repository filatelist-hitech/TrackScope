---
description: Триггернуть субагента reviewman для pre-merge-ревью — anti-fake-проверка, тесты зелёные, документация согласована, никакого STABLE без evidence.
allowed-tools: Bash(git status:*), Bash(git diff:*), Read, Grep, Glob
---

Использовать субагента **reviewman** на текущих staged + unstaged-изменениях.

Перед делегированием собрать контекст:

!`git status`

!`git diff --staged`

!`git diff`

Затем вызвать `@reviewman` с этим чек-листом:

1. **Anti-fake**: никакого хардкода BPM, никаких случайных BPM, никакого таймер-based фейкового пульса, никаких демо-BPM в продакшен-путях.
2. **Тесты зелёные**: `cargo test --workspace`, `python3 -m unittest discover core/tests`, `python3 tools/offline-lab/offline_lab.py report` — все проходят.
3. **Документация обновлена**: `docs/ARCHITECTURE.md`, `docs/DSP_ALGORITHM.md`, `docs/QA_MATRIX.md`, `docs/ROADMAP.md` отражают изменение.
4. **Никакого STABLE без evidence**: тишина, белый/розовый шум, сильный клиппинг, брейкдаун не могут достичь `STABLE`.
5. **Видимость кандидатов**: half/double-кандидаты с корректными `relation` и `source_bpm` присутствуют.
6. **Границы**: BPM-математика живёт только в `core/dsp/`. FFI и Flutter — адаптеры.
7. **Никаких ослабленных тестов**: ни один существующий тест не удалён и не ослаблен.

Вывод: блокирующие проблемы, не-блокирующие проблемы, отсутствующие тесты, прогнанные команды, рекомендуемый следующий патч.

Ссылки: @CLAUDE.md, @docs/DSP_ALGORITHM.md, @docs/QA_MATRIX.md
