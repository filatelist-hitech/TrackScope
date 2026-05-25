# hitech-bpm-radar

DSP-first BPM detection for hitech / psytrance, targeting automatic microphone-based tempo detection in the 170-230 BPM range.

This repository is not a tap-tempo toy and not a UI demo. The first production milestone is a deterministic DSP core with synthetic tests and an offline analyzer. Mobile microphone capture and UI come only after the DSP contract is stable.

## Product Contract

The product must report:

- detected BPM, or `null` when the signal is not trustworthy
- confidence from `0.0` to `1.0`
- lock state
- tempo candidates with scores
- half-time and double-time relationships
- signal quality warnings
- session history once mobile integration begins

Production logic must never hardcode demo BPM values or invent a tempo for silence, noise-only input, clipped microphone input, or breakdown sections.

## Repository Map

```text
apps/mobile/       Flutter shell, future microphone permission flow, audio bridge, and result rendering.
core/dsp/          Rust DSP contract plus current Python/Node offline prototype used by Phase 1 tests.
core/ffi/          Native bridge boundary for Flutter/mobile integration.
core/tests/        Synthetic fixtures, regression tests, and DSP acceptance coverage.
tools/offline-lab/ Python offline analyzer, fixture generator, and algorithm comparison reports.
datasets/          Synthetic and real-world audio fixture storage.
docs/              Architecture, DSP algorithm, QA matrix, roadmap, mobile notes, and release checklist.
.codex/            Codex config, role agents, and plan template.
.agents/skills/    Reusable project skills for local agent workflows.
```

## Current Phase

Phase 0/1: Infrastructure and Offline DSP Lab.

The repository now has the Codex-driven project infrastructure, a Rust workspace for the DSP/FFI boundary, and an existing deterministic Python/Node offline lab. The next implementation work is to move the tested offline algorithm into the Rust DSP engine and keep the synthetic test suite green.

## Acceptance Targets

- Clean synthetic fixtures: within +/-1 BPM at 170, 180, 190, 200, and 220 BPM.
- Noisy microphone-like input: within +/-2-4 BPM when signal quality is adequate.
- First usable lock: under 6 seconds.
- Stable lock: under 12 seconds.
- Silence and noise-only input must not reach `STABLE`.
- In hitech mode, a 100 BPM half-time candidate must not beat a stronger normalized 200 BPM candidate.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [DSP Algorithm](docs/DSP_ALGORITHM.md)
- [QA Matrix](docs/QA_MATRIX.md)
- [Roadmap](docs/ROADMAP.md)
- [Mobile Audio Notes](docs/MOBILE_AUDIO.md)
- [Release Checklist](docs/RELEASE_CHECKLIST.md)

## Working with Claude Code

The repository is configured for native Claude Code in parallel to the legacy Codex setup.

Where to look:

- `CLAUDE.md` — project memory: DSP contract, hitech normalization rules, anti-fake rules, workflow, build/test commands.
- `.claude/agents/` — 7 subagents (`archman`, `dspman`, `mobileman`, `qaman`, `perfman`, `reviewman`, `docman`) mirroring the Codex `.codex/agents/*.toml` roles.
- `.claude/skills/` — 5 skills (`project-bootstrap`, `dsp-tempo-analysis`, `mobile-audio-input`, `qa-audio-dataset`, `review-gate`) mirroring `.agents/skills/*/SKILL.md`.
- `.claude/commands/` — slash commands: `/plan`, `/qa-report`, `/parity`, `/review-gate`, `/bootstrap-task`.
- `.claude/settings.json` — project permissions and hooks. Personal overrides go in `.claude/settings.local.json` (gitignored).

Typical workflows:

- Start any non-trivial task with `/bootstrap-task <description>` — it reads `AGENTS.md` + `CLAUDE.md`, classifies complexity, picks the relevant subagents and skills, and scaffolds a plan for medium/high tasks.
- `/plan <task-title>` produces a full execution plan from the `.codex/plans/PLANS.md` template.
- `/qa-report` runs `python3 tools/offline-lab/offline_lab.py report` and summarizes regressions and lock-state violations.
- `/parity` runs Rust + Python parity tests and reports drift in `primary_bpm` or `confidence`.
- `/review-gate` invokes the `reviewman` subagent against the staged + unstaged diff before merging.

Subagents and skills are description-matched and activate automatically when their triggers fire; you can also invoke them explicitly via `@agent-name` or by referencing the skill.

> `.codex/` and `.agents/` are preserved as legacy reference from the original OpenAI Codex environment. Do not delete or modify them. The Codex agent → Claude Code subagent mapping is documented at the bottom of `CLAUDE.md`.
