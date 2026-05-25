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
