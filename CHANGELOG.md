# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to semantic versioning once releases begin.

## [Unreleased]

### Added
- Phase 2 streaming DSP core — `DspEngine` now holds a **rolling onset history**: `pcm_window`, `pcm_pending`, `onset_history`, and `prev_frame_rms`. On each `push_samples`, only the *new* PCM region is converted into spectral-flux frames and appended to the bounded onset ring; the oldest entries drop off the back. Per-push CPU cost is independent of stream duration.
- Shared `analyze_from_envelope` post-onset pipeline used by both batch `analyze_pcm` and streaming `DspEngine::analyze`, so both paths produce equivalent steady-state `DspResult` snapshots.
- Three new Rust streaming tests in `core/dsp/tests/streaming.rs`:
  - `streaming_first_lock_under_six_seconds_for_200_bpm` — engine leaves `SEARCHING` within `lock_min_seconds` on a clean 200 BPM pulse.
  - `streaming_stable_lock_under_twelve_seconds_for_200_bpm` — engine reaches `STABLE` with `primary_bpm` within ±2 BPM in `stable_min_seconds`.
  - `streaming_reflects_mid_stream_tempo_change_within_one_window` — 12 s of 180 BPM concatenated with 12 s of 200 BPM; engine locks to 180, transitions through a non-`STABLE` state during the change, and catches up to ~200 BPM within one analysis window. Proves the engine does not silently swap one tempo for another while remaining `STABLE`.
- `core/dsp/tests/streaming_perf.rs` (`--ignored`) — release-mode timing harness for `push_samples` + `analyze` over a 60-second stream in 100 ms chunks, asserting a 200 ms per-push upper bound.

### Changed
- `DspEngine` now pre-sizes its rings from `DspConfig` in `new()`. Public API unchanged: `new`, `config`, `push_samples`, `analyze`, `analyze_raw_candidates`, and `reset` keep their existing signatures.
- `docs/DSP_ALGORITHM.md` documents the rolling onset history and the new streaming tests.

### Performance
- `push_samples` (release, 100 ms chunks at 48 kHz): median 42µs → **29µs** (−31%), p95 119µs → **50µs** (−58%), max 329µs → **78µs** (−76%).
- `analyze` (release): median 2591µs → **1747µs** (−33%), p95 3236µs → **2167µs** (−33%), max 8272µs → **2553µs** (−69%).
- Total per-chunk cost (push + analyze): median 2633µs → **1776µs** (−33%); max 8601µs → **2631µs** (−69%).

### Earlier in [Unreleased]

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
