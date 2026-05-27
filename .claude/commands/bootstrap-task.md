---
description: Полный workflow старта задачи — прочитать AGENTS.md и CLAUDE.md, классифицировать сложность, выбрать субагентов / навыки, заскаффолдить план для medium/high задач.
argument-hint: "[task-description]"
---

Старт задачи: **$ARGUMENTS**

Прогони полный bootstrap-workflow:

1. Прочитай @AGENTS.md и @CLAUDE.md. Усвой контракт DspResult и anti-fake правила.
2. Классифицируй задачу:
   - Сложность: low / medium / high.
   - Затронутые домены: dsp / mobile / ui / qa / docs / performance / security.
3. Перечисли релевантных субагентов для делегирования (только реально нужных):
   - DSP-работа → `@dspman` + навык `dsp-tempo-analysis`.
   - Mobile / Flutter / FFI → `@mobileman` + навык `mobile-audio-input`.
   - Тесты / фикстуры / QA → `@qaman` + навык `qa-audio-dataset`.
   - Архитектура / контракты → `@archman`.
   - Производительность → `@perfman`.
   - Документация / релиз-ноты → `@docman`.
   - Пред-мердж → `@reviewman` + навык `review-gate`.
4. Для medium/high — запусти `/plan $ARGUMENTS`, чтобы заскаффолдить полный execution-план.
5. Для low — напиши пятистрочный план inline (текущее поведение, целевое поведение, файлы для правки, тесты, done-when).
6. Подтверди, что тесты будут добавлены или обновлены вместе с изменением.
7. Подтверди, что не будет введено фейкового / демо-BPM и не будут скрыты half/double кандидаты.

Вывод: сжатый чеклист с классификацией, выбранными агентами / навыками, локацией плана (или inline-планом) и первым конкретным следующим шагом.

Ссылки: @AGENTS.md, @CLAUDE.md, @.codex/plans/PLANS.md
