---
name: project-bootstrap
description: Use whenever you are creating, restructuring, or auditing the repository layout for hitech-bpm-radar — including adding new modules under core/, apps/, tools/, datasets/, docs/, or .claude/. Trigger when the user asks to "scaffold", "bootstrap", "set up the project", "add a new module", "restructure", or when phase gates (Phase 0 → 1 → 2 → 3 → 4 → 5) advance. Also trigger before any first commit on a new branch that touches multiple top-level directories.
---

# Project Bootstrap

Goal: keep the DSP-first layout intact while extending the project.

1. Inspect the existing tree before writing files. Do not overwrite work without reading it.
2. Preserve all existing DSP tests, fixtures, and docs. Never weaken a test to pass a refactor.
3. Create missing directories with a `README.md` or `.gitkeep` if they are intentionally empty (e.g. `datasets/*/`).
4. Phase 0/1 stays DSP-first. Do not create mobile BPM behavior — `apps/mobile/` is a shell until the Rust DSP is ready.
5. When boundaries change, update in the same change:
   - `README.md` (repository map, current phase, acceptance targets)
   - `docs/ARCHITECTURE.md` (dependency direction, module ownership)
   - `docs/ROADMAP.md` (phase deliverables and exit criteria)
   - `docs/QA_MATRIX.md` (any new test case row)
6. Run the validation commands listed in @CLAUDE.md "Build & test commands" and report which passed.
7. Preserve `.codex/` and `.agents/` as legacy reference — do not delete or rename them.

References: @CLAUDE.md, @docs/ARCHITECTURE.md, @docs/ROADMAP.md
