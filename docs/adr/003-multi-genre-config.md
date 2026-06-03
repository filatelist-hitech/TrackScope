# ADR 003: Multi-Genre BPM Preset Configuration

## Status: Accepted

## Date: 2026-06-01

## Context

DSP-ядро поддерживает параметрические `target_bpm_min` / `target_bpm_max`. Разные жанры электронной музыки имеют разные BPM-диапазоны и разные пороги нормализации half/double:

| Жанр | Диапазон | Нормализация half/double |
|---|---|---|
| Hitech / Psy | 155–230 | <130 → ×2, >260 → ÷2 |
| Psytrance | 130–160 | <65 → ×2, >200 → ÷2 |
| DnB | 160–185 | <80 → ×2, >240 → ÷2 |
| Techno | 125–145 | <65 → ×2, >200 → ÷2 |

Вопрос: как хранить и передавать жанровую конфигурацию через FFI-границу?

## Decision

**`GenrePreset` enum в Rust (`core/dsp/src/genre_preset.rs`) + `DspConfig` параметризован через `target_bpm_min` / `target_bpm_max`.**

1. `GenrePreset` — Rust enum с методами `bpm_range()` и `normalization_thresholds()`.
2. Flutter-слой выбирает пресет, вычисляет `(min, max)`, передаёт через `hitech_bpm_engine_new_with_min_bpm(min)` (существующий FFI) или будущий `hitech_bpm_engine_new_with_range(min, max)`.
3. `DspResult` хранит `genre_preset` для диагностики (без влияния на алгоритм).

**Причины:**
- Не добавляет новых FFI-символов в Phase 1; реиспользует существующий `min_bpm` knob.
- `GenrePreset` — Dart enum на мобильной стороне (зеркало Rust), без Round-trip через FFI.
- Custom(min, max) — только Pro; Free tier ограничен тремя preset'ами.

## Consequences

- Нормализационные пороги (`normalization_thresholds()`) не передаются в FFI в Phase 1 — DSP-ядро использует хардкоданные 130/260. **Phase 2**: добавить `hitech_bpm_engine_new_with_config(min, max, norm_lo, norm_hi)`.
- Смена пресета пересоздаёт `CaptureBridge` (аналог смены `minBpm` в Phase 10).
- Free-tier: 3 пресета достаточно для большинства psy-DJ.

## Файлы

`core/dsp/src/genre_preset.rs` (реализовано), `apps/mobile/lib/features/genre_preset/` (Phase 1: Flutter UI — бэклог).
