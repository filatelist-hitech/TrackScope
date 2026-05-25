# core/dsp

Rust DSP source-of-truth boundary for BPM detection, with a temporary Python/Node offline prototype retained for Phase 1 regression coverage.

This module owns the engine contract, preprocessing, onset detection, tempo candidate estimation, hitech normalization, confidence scoring, and lock state machine.

Current state:

- Rust crate defines `DspResult`, `TempoCandidate`, `SignalQuality`, lock states, hitech normalization, and the streaming engine boundary.
- Python/Node code provides the current deterministic offline analyzer used by tests.

Do not add UI code, microphone permission code, file decoding, or demo BPM values here.
