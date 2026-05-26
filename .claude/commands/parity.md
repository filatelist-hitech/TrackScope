---
description: Запустить кросс-языковые parity-тесты — Python-референс против Rust DSP — и отчитаться о любом дрифте в primary_bpm или confidence.
allowed-tools: Bash(/opt/homebrew/opt/rust/bin/cargo test:*), Bash(cargo test:*), Bash(python3:*)
---

Запустить кросс-языковой parity:

!`/opt/homebrew/opt/rust/bin/cargo test --workspace`

!`python3 -m unittest discover core/tests`

Затем:

1. Отчитаться о pass/fail-счётчиках обоих прогонов.
2. Если какой-либо parity-тест упал, извлечь имена упавших кейсов (искать `python_parity` или `parity` в именах тестов) и показать:
   - фикстуру / вход, который тестировался;
   - ожидаемый `primary_bpm` и `confidence`;
   - фактические значения с каждой стороны;
   - абсолютную разницу.
3. Определить, в чём дрифт: в темповой математике (автокорреляция, нормализация), в скоринге уверенности или в измерении качества сигнала.
4. Рекомендовать, какую сторону обновлять — Rust или Python-референс, — и делегировать `@dspman`.

Жёсткое правило: parity не «чинится» ослаблением assertion'ов. Либо Rust, либо Python неправ — найти, кто.

Ссылки: @CLAUDE.md, @docs/DSP_ALGORITHM.md
