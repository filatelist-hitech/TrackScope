# CLAUDE.md — hitech-bpm-radar

DSP-first mobile BPM detector for hitech / psytrance (170–230 BPM target). Microphone input, no tap tempo.

## Stack & layout

- `core/dsp/`         — Rust DSP crate (source of truth) + Python reference (`tempo.py`, `synthetic.py`) used by Phase 1 tests.
- `core/ffi/`         — Native C ABI for Flutter ↔ Rust DSP.
- `core/tests/`       — Python regression and parity tests, synthetic fixtures.
- `tools/offline-lab/` — Python CLI analyzer, fixture generator, QA report.
- `apps/mobile/`      — Flutter shell (microphone, debug screen, history). No BPM math here.
- `datasets/`         — synthetic / hitech / noisy_club / clipped_mic / breakdowns fixtures.
- `docs/`             — architecture, DSP algorithm, QA matrix, roadmap, mobile audio notes.

## DspResult contract (do not break)

```ts
type LockState = "SEARCHING" | "LOCKING" | "STABLE" | "UNSTABLE" | "BREAKDOWN" | "CLIPPED_MIC" | "NOISE_ONLY";
type TempoRelation = "raw" | "main" | "half_time" | "double_time" | "normalized_from_half" | "normalized_from_double";

interface DspResult {
  primary_bpm: number | null;   // null when signal is silence/noise/clipped/untrustworthy
  confidence: number;            // 0.0..1.0
  lock_state: LockState;
  signal_quality: SignalQuality; // input_level_dbfs, clipping, clipped_frame_ratio, noise_level, snr_estimate_db, silence, breakdown_likely
  candidates: TempoCandidate[];  // raw + normalized, with score, raw_score, stability_score, range_score, relation, source_bpm
  timing: DspTiming;
  debug?: DspDebug;
}
```

Rules:
- `primary_bpm` is `null` until confidence clears the lock threshold.
- Silence and noise-only input must NEVER reach `STABLE`.
- Clipped input must flag `clipping: true`; if severe, suppress `primary_bpm` and prefer `CLIPPED_MIC`.
- Breakdown sections decay confidence; do not preserve stale `STABLE`.

Full spec: @docs/DSP_ALGORITHM.md

## Hitech candidate normalization

- Search internal range ~80–460 BPM so half/double traps are observable pre-normalization.
- If raw candidate < 130 BPM → also emit `bpm * 2` with relation `normalized_from_half`.
- If raw candidate > 260 BPM → also emit `bpm / 2` with relation `normalized_from_double`.
- Keep raw, half-time, double-time, and normalized candidates in the list.
- Primary chosen by combined score (evidence + range fit + stability + signal quality), not range alone.
- In hitech mode a raw 100 BPM must not finalize if normalized 200 BPM has stronger evidence.

## Anti-fake rules (non-negotiable)

- NO hardcoded production BPM values.
- NO random BPM, NO timer-based fake pulse, NO demo BPM in production paths.
- NO `STABLE` without onset/tempo evidence and signal-quality gating.
- NEVER hide half-time / double-time candidates — always keep them visible.
- NEVER return a single BPM without an associated confidence.
- Confidence must be derived from evidence (onset clarity, peak prominence, harmonic support, stability, range fit, signal quality, ambiguity penalty).
- Mobile/UI must never compute BPM — only render the DSP contract.

## Workflow for any task

1. Read @AGENTS.md and this file before doing anything.
2. Classify complexity (low / medium / high) and domains (dsp / mobile / ui / qa / docs / performance / security).
3. For medium/high: produce a plan using @.codex/plans/PLANS.md before implementation. The `/plan` command scaffolds it.
4. Pick subagents and skills explicitly by relevance:
   - DSP work → `@dspman`, skill `dsp-tempo-analysis`.
   - Mobile/Flutter/FFI → `@mobileman`, skill `mobile-audio-input`.
   - Test/QA/datasets → `@qaman`, skill `qa-audio-dataset`.
   - Architecture or contracts → `@archman`.
   - Perf/latency/CPU → `@perfman`.
   - Docs/release notes → `@docman`.
   - Before merging → `@reviewman` + skill `review-gate`.
5. Implement minimally; add/update tests next to the change. DSP changes require synthetic coverage.
6. Run the relevant validation commands before reporting done.
7. Final report: changed files, what was implemented, how it was tested, known limitations, recommended next patch.

## Toolchain

Use the explicit binaries (see @AGENTS.md):

- `/opt/homebrew/opt/nodejs/bin/node`
- `/opt/homebrew/opt/rust/bin/cargo`

## Build & test commands

```sh
# Python unit + parity + offline-DSP regression
python3 -m unittest discover core/tests

# Rust workspace (DSP + FFI + python parity)
/opt/homebrew/opt/rust/bin/cargo test --workspace

# Node offline analyzer parity
/opt/homebrew/opt/nodejs/bin/node --test core/dsp/index.test.js

# Deterministic offline QA report (exit-non-zero on regression)
python3 tools/offline-lab/offline_lab.py report

# Flutter (becomes required once mobile bridge lands)
flutter test
flutter analyze
```

## References

- @AGENTS.md
- @docs/ARCHITECTURE.md
- @docs/DSP_ALGORITHM.md
- @docs/QA_MATRIX.md
- @docs/ROADMAP.md
- @.codex/plans/PLANS.md

## Codex ↔ Claude Code agent mapping

The legacy Codex agents in `.codex/agents/*.toml` map 1:1 to Claude Code subagents in `.claude/agents/*.md`:

| Codex (TOML)  | Claude Code (md) | Focus                                         |
| ------------- | ---------------- | --------------------------------------------- |
| ARCHMAN       | archman          | architecture, module boundaries, contracts    |
| DSPMAN        | dspman           | DSP algorithms, parity Rust ↔ Python          |
| MOBILEMAN     | mobileman        | Flutter shell, FFI, microphone capture        |
| QAMAN         | qaman            | offline-lab, dataset matrix, regression tests |
| PERFMAN       | perfman          | latency, CPU, allocations, mobile battery     |
| REVIEWMAN     | reviewman        | pre-merge review gate                         |
| DOCMAN        | docman           | docs, changelog, release notes                |

`.codex/` and `.agents/` are preserved as legacy reference from the original OpenAI Codex environment — do not delete or modify them.
