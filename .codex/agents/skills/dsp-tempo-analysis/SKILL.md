---
name: dsp-tempo-analysis
description: Use for BPM detection, onset detection, tempo estimation, beat tracking, hitech BPM normalization, confidence scoring, and DSP tests.
---

# DSP Tempo Analysis Skill

Use this workflow for DSP tasks.

Required pipeline:

1. Input PCM buffer
2. Mono conversion
3. Preprocessing
4. Multiband onset detection
5. Onset history
6. Tempo candidate estimation
7. Hitech normalization
8. Confidence scoring
9. Lock state classification

Required result contract:

- primary_bpm
- confidence
- lock_state
- signal_quality
- candidates[]

Rules:

- Never return fake BPM.
- Never hide uncertainty.
- Always preserve half-time and double-time candidates.
- Add tests for every algorithm change.
- Prefer deterministic DSP before ML.
- Avoid heavy allocations in streaming hot paths.

Required tests:

- 170 BPM
- 180 BPM
- 190 BPM
- 200 BPM
- 220 BPM
- half-time trap
- double-time trap
- silence
- noise
- clipped input