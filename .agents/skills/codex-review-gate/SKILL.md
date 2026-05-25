---
name: codex-review-gate
description: Use before accepting or merging a patch to check correctness, fake/demo behavior, test coverage, docs, and architecture drift.
---

# Codex Review Gate

1. Inspect the diff.
2. Verify BPM is computed from audio/onset evidence or typed test candidates, never hardcoded production values.
3. Confirm confidence is calculated and uncertainty remains visible.
4. Confirm candidates and half/double interpretations are preserved.
5. Check that mobile code does not compute BPM directly.
6. Run relevant tests when available.
7. Report blocking issues, non-blocking issues, tests run, docs touched, and next patch.
