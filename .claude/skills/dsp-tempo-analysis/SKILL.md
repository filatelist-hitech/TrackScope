---
name: dsp-tempo-analysis
description: Use for any task involving onset detection, tempo estimation, BPM normalization, confidence scoring, lock-state classification, or DSP regression tests for hitech-bpm-radar. Trigger whenever editing core/dsp/ (Rust or Python), core/tests/, tools/offline-lab/, when a fixture is added, when half-time / double-time behavior is discussed, or when "BPM", "onset", "tempo", "confidence", "lock state" appear in the request. Required reading before any tempo math is written or modified.
---

# DSP Tempo Analysis

Required pipeline (must remain in this order):

1. Accept normalized mono PCM (resample to the DSP rate if needed).
2. Measure signal quality BEFORE tempo decisions: input level dBFS, peak, clipping ratio, silence, breakdown likelihood.
3. Detect onset evidence from audio: broadband spectral flux + low-frequency kick flux + high-frequency transient flux. Never from timers or constants.
4. Maintain onset history in rolling windows.
5. Estimate raw tempo candidates across a broad internal range (~80–460 BPM) using autocorrelation / comb / IOI evidence.
6. Normalize candidates < 130 BPM by evaluating `bpm * 2` with relation `normalized_from_half`.
7. Normalize candidates > 260 BPM by evaluating `bpm / 2` with relation `normalized_from_double`.
8. Preserve raw, half-time, double-time, and normalized candidates — never drop one silently.
9. Score by evidence + recent stability + hitech range fit + signal quality + ambiguity penalty.
10. Classify lock state: SEARCHING / LOCKING / STABLE / UNSTABLE / BREAKDOWN / CLIPPED_MIC / NOISE_ONLY.
11. Emit `DspResult` with nullable `primary_bpm` and `confidence` in `0.0..1.0`.

Hard rules:

- Never fake BPM, never hide uncertainty.
- Never return `STABLE` for silence, white/pink noise, severe clipping, or breakdown.
- A raw 100 BPM candidate must not finalize in hitech mode if normalized 200 BPM has stronger evidence — but 100 raw must still be in the candidate list.
- Confidence must be derived from evidence, not constants.

Tests to add or update when this skill applies: 170/180/190/200/220 clean, 100 half-time trap, 400 double-time trap, silence, white noise, pink noise, clipped (severe + recoverable), breakdown, dense hitech bassline, unstable club simulation.

References: @CLAUDE.md, @docs/DSP_ALGORITHM.md, @docs/QA_MATRIX.md
