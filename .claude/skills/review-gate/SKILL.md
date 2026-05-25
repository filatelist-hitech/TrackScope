---
name: review-gate
description: Use BEFORE accepting, merging, or pushing any patch in hitech-bpm-radar to check correctness, anti-fake behavior, test coverage, docs alignment, and architecture drift. Trigger when the user says "review", "ready to merge", "ready for PR", "looks good?", "check this diff", or after a non-trivial change to core/dsp, core/ffi, core/tests, tools/offline-lab, apps/mobile. Pair with the reviewman subagent.
---

# Review Gate

1. **Inspect the diff** (staged + unstaged): `git status`, `git diff`, `git diff --staged`.
2. **Anti-fake**: confirm BPM is computed from audio/onset evidence or typed test candidates — never hardcoded production values, random, or timer-based.
3. **Confidence + uncertainty**: confirm `confidence` is calculated from evidence and uncertainty remains visible (no auto-`STABLE`).
4. **Candidate preservation**: raw + half-time + double-time + normalized candidates all present, with correct `relation` and `source_bpm` for traps.
5. **Lock-state gates**: silence, white/pink noise, severe clipping, breakdown cannot reach `STABLE`.
6. **Boundary**: BPM math lives only in `core/dsp/`. `core/ffi/` and `apps/mobile/` are adapters.
7. **Tests**: every DSP algorithm change adds or updates synthetic coverage. No test was weakened or deleted.
8. **Parity**: where Rust ↔ Python parity tests exist, they agree on the changed fixtures.
9. **Docs**: `docs/ARCHITECTURE.md`, `docs/DSP_ALGORITHM.md`, `docs/QA_MATRIX.md`, `docs/ROADMAP.md` reflect the change if relevant.
10. **Run validation**: `cargo test --workspace`, `python3 -m unittest discover core/tests`, `python3 tools/offline-lab/offline_lab.py report`, plus `flutter test`/`flutter analyze` when mobile code is touched.
11. **Report**: blocking issues (with file:line), non-blocking issues, missing tests, docs touched, commands run, recommended next patch.

References: @CLAUDE.md, @AGENTS.md, @docs/DSP_ALGORITHM.md, @docs/QA_MATRIX.md
