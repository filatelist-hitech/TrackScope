---
description: Run the offline-lab deterministic QA report and summarize lock states, candidate normalization, and any regressions.
allowed-tools: Bash(python3 tools/offline-lab/offline_lab.py:*), Read
---

Run the deterministic offline QA report and summarize the result.

!`python3 tools/offline-lab/offline_lab.py report`

Then:

1. Report the exit code. Non-zero means a regression — list which fixtures failed.
2. For each row, note: fixture, expected BPM, detected BPM, error, confidence, lock state.
3. Flag any row where:
   - `silence`, `white_noise`, `pink_noise`, `unstable_club_simulation` reach `STABLE` (must not happen).
   - `clipped_*` does not flag `clipping: true`.
   - `half_time_trap_100` does not show normalized 200 BPM with relation `normalized_from_half` AND raw 100 BPM visible.
   - `double_time_trap_400` does not show normalized 200 BPM with relation `normalized_from_double` AND raw 400 BPM visible.
   - `breakdown_200` reaches `STABLE`.
4. If anything regressed, recommend the next patch (which agent + which fixture + which DSP component).

Reference acceptance targets: @docs/QA_MATRIX.md
