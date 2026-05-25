---
description: Run cross-language parity tests — Python reference vs Rust DSP — and report any drift in primary_bpm or confidence.
allowed-tools: Bash(/opt/homebrew/opt/rust/bin/cargo test:*), Bash(cargo test:*), Bash(python3:*)
---

Run cross-language parity:

!`/opt/homebrew/opt/rust/bin/cargo test --workspace`

!`python3 -m unittest discover core/tests`

Then:

1. Report pass/fail counts for both runs.
2. If any parity test failed, extract the failing case names (look for `python_parity` or `parity` in the test names) and show:
   - the fixture / input it tested,
   - the expected `primary_bpm` and `confidence`,
   - the actual values from each side,
   - the absolute diff.
3. Identify whether the drift is in tempo math (autocorrelation, normalization), confidence scoring, or signal-quality measurement.
4. Recommend whether the Rust side or the Python reference should be the one updated, and delegate to `@dspman`.

Hard rule: parity must not be "fixed" by relaxing assertions. Either Rust or Python is wrong — find which.

References: @CLAUDE.md, @docs/DSP_ALGORITHM.md
