---
description: Trigger the reviewman subagent for a pre-merge review — anti-fake check, tests green, docs aligned, no STABLE without evidence.
allowed-tools: Bash(git status:*), Bash(git diff:*), Read, Grep, Glob
---

Use the **reviewman** subagent on the currently staged + unstaged changes.

Before delegating, gather context:

!`git status`

!`git diff --staged`

!`git diff`

Then invoke `@reviewman` with this checklist:

1. **Anti-fake**: no hardcoded BPM, no random BPM, no timer-based fake pulse, no demo BPM in production paths.
2. **Tests green**: `cargo test --workspace`, `python3 -m unittest discover core/tests`, `python3 tools/offline-lab/offline_lab.py report` all pass.
3. **Docs updated**: `docs/ARCHITECTURE.md`, `docs/DSP_ALGORITHM.md`, `docs/QA_MATRIX.md`, `docs/ROADMAP.md` reflect the change.
4. **No STABLE without evidence**: silence, white/pink noise, severe clipping, breakdown cannot reach `STABLE`.
5. **Candidate visibility**: half/double candidates with correct `relation` and `source_bpm` are present.
6. **Boundary**: BPM math lives only in `core/dsp/`. FFI and Flutter are adapters.
7. **No weakened tests**: no existing test was deleted or relaxed.

Output: blocking issues, non-blocking issues, missing tests, commands run, recommended next patch.

References: @CLAUDE.md, @docs/DSP_ALGORITHM.md, @docs/QA_MATRIX.md
