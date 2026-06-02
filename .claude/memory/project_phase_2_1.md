---
name: phase-2-1-hpcp-key-analyzer
description: Phase 2.1 HPCP KeyAnalyzer — детекция тональности завершена 2026-06-02
metadata:
  type: project
---

Phase 2.1 завершена 2026-06-02.

**Что сделано:**
- `core/dsp/src/key_analyzer.rs` — STFT→HPCP→K-S корреляция→Camelot, `Debug` impl, `Clone` ручной (FftPlanner не Clone).
- `core/dsp/src/lib.rs` — `DspEngine` получил `key_analyzer: KeyAnalyzer`; гейт подавления: `ClippedMic | NoiseOnly | silence → key_result = None`.
- `core/dsp/tests/key_detection.rs` — 13 тестов (+ noise_only_no_key).
- `apps/mobile/lib/dsp/dsp_result.dart` — класс `KeyResult`, поле `DspResult.keyResult`.
- Документация: `docs/DSP_ALGORITHM.md` + `docs/ROADMAP.md` + `.claude/docs/project-map.md`.

**Why:** anti-fake правило расширено на key_result: NOISE_ONLY и CLIPPED_MIC не дают тональность.

**How to apply:** при любых изменениях гейта `key_result` в `DspEngine::analyze()` проверять, что NoiseOnly и ClippedMic явно перечислены в условии подавления.
