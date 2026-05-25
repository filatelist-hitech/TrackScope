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
apps/mobile/       Future mobile app shell, microphone permission flow, audio bridge, and result rendering.
core/dsp/          Pure DSP contract and implementation boundary.
core/tests/        Synthetic fixtures, regression tests, and DSP acceptance coverage.
tools/offline-lab/ Offline analyzer, fixture generator, and algorithm comparison reports.
datasets/          Synthetic and real-world audio fixture storage.
docs/              Architecture, DSP algorithm, QA matrix, and roadmap.
```

## Current Phase

Phase 1: Offline DSP Lab.

The next implementation work is to add the `core/dsp` contract stub, synthetic fixture generator, and deterministic tests for clean hitech click tracks before building any mobile UI.

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
