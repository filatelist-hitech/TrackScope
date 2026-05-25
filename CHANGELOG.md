# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to semantic versioning once releases begin.

## [Unreleased]

### Added
- Rust DSP is now the authoritative production analyzer. `cargo test --workspace` runs hermetically with no `python3` subprocess.
- `core/dsp/tests/common/mod.rs` — shared deterministic Rust fixture module mirroring `core/tests/helpers/synthetic_fixtures.py`. Covers silence, white/pink noise, clean 170/180/190/200/220, half-time and double-time traps, severely- and recoverable-clipped, breakdown, dense hitech bassline, and unstable club simulation.
- `canonical_fixture_inventory_round_trip` test in `core/dsp/tests/offline_contract.rs` walks the full Rust fixture inventory and asserts anti-fake invariants.
- `core/dsp/src/bin/analyze_wav.rs` — Rust CLI that reads a 16-bit PCM WAV and emits the `DspResult` as JSON; used by the standalone parity tool.
- `tools/offline-lab/parity.py` — opt-in cross-language drift check that runs the Python analyzer and the Rust `analyze_wav` binary on the same WAV fixtures and tabulates per-fixture drift in `primary_bpm`, `confidence`, `lock_state`, and candidate relations.
- `serde` / `serde_json` derives on the public DSP result types (`DspResult`, `TempoCandidate`, `SignalQuality`, etc.) so the result contract serializes to the same JSON shape Python emits.

### Changed
- `core/dsp/tests/offline_contract.rs` now consumes the shared `common::*` fixture module; the duplicated generators are gone.
- `docs/DSP_ALGORITHM.md` documents the Rust-as-source-of-truth posture and the parity refactor (Option A — no Python subprocess in `cargo test`).
- `docs/QA_MATRIX.md` adds the Rust fixture inventory table and the new `parity.py` validation command.
- `README.md` documents the hermetic `cargo test` workflow and the optional `parity.py` cross-language drift check.

### Removed
- `core/dsp/tests/python_parity.rs`. The Rust contract is asserted directly in `offline_contract.rs`; cross-language comparison moved to the standalone `tools/offline-lab/parity.py` tool.

## [0.0.1] - 2026-05-25 (Phase 1 offline DSP lab baseline)

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
