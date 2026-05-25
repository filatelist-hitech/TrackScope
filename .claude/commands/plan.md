---
description: Create a structured execution plan from the PLANS.md template (for medium/high complexity tasks).
argument-hint: "[task-title]"
---

Create an execution plan for: **$ARGUMENTS**

1. Read @.codex/plans/PLANS.md and follow its 10-section template verbatim.
2. Read @CLAUDE.md and @AGENTS.md to ground the plan in the project's contracts and anti-fake rules.
3. Classify the task: complexity (low / medium / high) and affected domains (dsp / mobile / ui / qa / docs / performance / security).
4. List the subagents to delegate to (e.g. `@dspman`, `@qaman`, `@archman`, `@reviewman`) and why each is needed.
5. Enumerate exact files and folders to inspect.
6. Describe current vs target behavior with concrete evidence (file paths, function names, fixture names).
7. State data contracts touched (DspResult fields, FFI signatures, public APIs).
8. Break implementation into small ordered steps. Tests come WITH each step, not at the end.
9. List required tests and the exact commands to run (cargo test, python3 -m unittest discover core/tests, offline-lab report, flutter test when mobile).
10. List risks and a fallback for each.
11. Define concrete acceptance criteria.

Save the resulting plan to `docs/plans/<kebab-task-title>.md` (create `docs/plans/` if missing). If the task is low-complexity, say so explicitly and skip the full template — write a 5-line summary instead.

Hard rule: a plan must never propose fake/demo BPM, hidden half/double candidates, or `STABLE` without evidence.
