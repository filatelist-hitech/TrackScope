# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to semantic versioning once releases begin.

## [Unreleased]

### Added
- Phase 1 offline DSP lab: synthetic fixture generator, Python reference analyzer (`core/dsp/tempo.py`), Rust crate (`core/dsp/src/lib.rs`), Node offline analyzer (`core/dsp/index.js`), and `tools/offline-lab/offline_lab.py report` deterministic gate.
- Hitech candidate normalization: raw < 130 BPM emits `normalized_from_half`, raw > 260 BPM emits `normalized_from_double`; raw, half-time, double-time, and normalized candidates are all preserved.
- Lock-state machine covering `SEARCHING`, `LOCKING`, `STABLE`, `UNSTABLE`, `BREAKDOWN`, `CLIPPED_MIC`, `NOISE_ONLY`.
- Graded clipping handling: mild clipping caps confidence below `STABLE` while keeping candidates visible; severe clipping (clipped-frame ratio >= 5%) forces `CLIPPED_MIC` and suppresses `primary_bpm`.
- Harmonic-ambiguity penalty applied to the confidence score so a close-second candidate decays final confidence.
- New `recoverable_clipped_200` fixture and offline-lab row to assert mild-clipping behavior.
- Rust ↔ Python parity test `core/dsp/tests/python_parity.rs` running the Python analyzer over a shared fixture matrix.
- QA matrix entry and DSP algorithm notes for graded clipping and parity test coverage.

### Notes
- No hardcoded BPM in production paths; silence, noise-only, and severely clipped inputs return `primary_bpm: null`.
- Half-time and double-time candidates are never hidden — they remain in the candidate list with relation/source metadata.

[Unreleased]: https://github.com/filatelist-hitech/hitech-bpm-radar/compare/main...HEAD
