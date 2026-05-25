---
name: codex-review-gate
description: Use before accepting a patch. Reviews architecture, correctness, fake/demo behavior, tests, docs, and known limitations.
---

# Codex Review Gate Skill

Before accepting a patch:

1. Inspect git diff.
2. Check whether implementation matches task.
3. Check if tests were added or updated.
4. Check if docs need updates.
5. Look for fake data, hardcoded BPM, hidden uncertainty.
6. Run relevant tests if possible.
7. Return:
   - PASS / FAIL
   - blocking issues
   - non-blocking issues
   - tests run
   - files reviewed
   - next patch recommendation