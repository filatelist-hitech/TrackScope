---
name: qa-audio-dataset
description: Use for creating or maintaining synthetic audio fixtures, regression datasets, noisy/clipped/breakdown cases, and offline-lab QA reports for hitech-bpm-radar. Trigger when editing core/tests/helpers/synthetic_fixtures.py, datasets/**, tools/offline-lab/, when adding a new acceptance row to docs/QA_MATRIX.md, or when the user says "fixture", "dataset", "QA report", "regression test", "acceptance".
---

# QA Audio Dataset

Required deterministic fixtures (must always be present and green):

- Clean synthetic at 170, 180, 190, 200, 220 BPM.
- 100 BPM half-time trap → expects normalized 200 BPM as primary, raw 100 still visible.
- 400 BPM double-time trap → expects normalized 200 BPM as primary, raw 400 still visible.
- Silence → `primary_bpm: null`, state `SEARCHING` or `NOISE_ONLY`, no false lock.
- White noise → `primary_bpm: null` or low confidence, no `STABLE`.
- Pink noise → `primary_bpm: null` or low confidence, no `STABLE`.
- Clipped microphone (severe) → `primary_bpm: null`, state `CLIPPED_MIC`, clipping flag true.
- Clipped microphone (recoverable) → BPM within ±2–4 BPM if SNR adequate, clipping flag still true.
- Breakdown / no-kick after a stable section → state `BREAKDOWN` or `UNSTABLE`, confidence decays.
- Dense hitech bassline at ~200 BPM → ±2 clean, ±4 noisy.
- Unstable club simulation → low-confidence or `UNSTABLE`, uncertainty visible.

Report rows must include: fixture name, expected BPM, detected BPM, error, confidence, lock state, signal quality, candidate list (with relation and source_bpm for half/double), pass/fail, notes.

Hard rules:

- Expected BPM is metadata only — never inject it into the analyzer.
- Half/double rows must assert `relation` + `source_bpm` of the normalized candidate, not only the numeric BPM.
- A regression that fails an existing row must be fixed in the algorithm, not by relaxing the fixture.

Run with:

```sh
python3 tools/offline-lab/offline_lab.py report
```

Exits non-zero on any regression.

References: @CLAUDE.md, @docs/QA_MATRIX.md
