---
description: Запустить детерминированный QA-отчёт offline-lab и суммировать состояния захвата, нормализацию кандидатов и любые регрессии.
allowed-tools: Bash(python3 tools/offline-lab/offline_lab.py:*), Read
---

Запустить детерминированный офлайн-QA-отчёт и суммировать результат.

!`python3 tools/offline-lab/offline_lab.py report`

Затем:

1. Отчитаться о коде выхода. Не-ноль означает регрессию — перечислить, какие фикстуры упали.
2. Для каждой строки указать: фикстуру, ожидаемый BPM, детектированный BPM, ошибку, уверенность, состояние захвата.
3. Поднять флаг на любой строке, где:
   - `silence`, `white_noise`, `pink_noise`, `unstable_club_simulation` достигают `STABLE` (так быть не должно);
   - `clipped_*` не поднимает `clipping: true`;
   - `half_time_trap_100` не показывает нормализованный 200 BPM с relation `normalized_from_half` И raw 100 BPM видимым;
   - `double_time_trap_400` не показывает нормализованный 200 BPM с relation `normalized_from_double` И raw 400 BPM видимым;
   - `breakdown_200` достигает `STABLE`.
4. Если что-то регрессировало — рекомендовать следующий патч (какой агент + какая фикстура + какой DSP-компонент).

Референс целей приёмки: @docs/QA_MATRIX.md
