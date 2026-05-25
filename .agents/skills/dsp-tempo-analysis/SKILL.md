---
name: dsp-tempo-analysis
description: Use for onset detection, tempo estimation, hitech BPM normalization, confidence scoring, lock states, and DSP tests.
---

# DSP Tempo Analysis

Required pipeline:

1. Accept normalized mono PCM.
2. Measure signal quality before tempo decisions.
3. Detect onset evidence from audio, not timers or constants.
4. Estimate raw tempo candidates across a broad range.
5. Normalize candidates below 130 BPM by evaluating double tempo.
6. Normalize candidates above 260 BPM by evaluating half tempo.
7. Preserve raw, half-time, double-time, and normalized candidates.
8. Score confidence from evidence, stability, range fit, ambiguity, and signal quality.
9. Emit nullable `primary_bpm` and an explicit lock state.

Never fake BPM, hide uncertainty, or return `STABLE` for silence/noise-only input.
