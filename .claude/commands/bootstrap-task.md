---
description: Full task-start workflow — read AGENTS.md & CLAUDE.md, classify complexity, pick subagents/skills, scaffold a plan for medium/high tasks.
argument-hint: "[task-description]"
---

Start of task: **$ARGUMENTS**

Run the full bootstrap workflow:

1. Read @AGENTS.md and @CLAUDE.md. Internalize the DspResult contract and anti-fake rules.
2. Classify the task:
   - Complexity: low / medium / high.
   - Domains touched: dsp / mobile / ui / qa / docs / performance / security.
3. List the relevant subagents to delegate to (only the ones actually needed):
   - DSP work → `@dspman` + skill `dsp-tempo-analysis`.
   - Mobile / Flutter / FFI → `@mobileman` + skill `mobile-audio-input`.
   - Tests / fixtures / QA → `@qaman` + skill `qa-audio-dataset`.
   - Architecture / contracts → `@archman`.
   - Performance → `@perfman`.
   - Docs / release notes → `@docman`.
   - Pre-merge → `@reviewman` + skill `review-gate`.
4. For medium/high complexity, run `/plan $ARGUMENTS` to scaffold a full execution plan.
5. For low complexity, write a 5-line plan inline (current behavior, target behavior, files to touch, tests, done-when).
6. Confirm tests will be added or updated alongside the change.
7. Confirm no fake/demo BPM will be introduced and no half/double candidates will be hidden.

Output: a concise checklist with the classification, chosen agents/skills, plan location (or inline plan), and the first concrete next step.

References: @AGENTS.md, @CLAUDE.md, @.codex/plans/PLANS.md
