# core/dsp

Rust DSP source-of-truth boundary for BPM detection, with a temporary Python/Node offline prototype retained for Phase 1 regression coverage.

This module owns the engine contract, preprocessing, onset detection, tempo candidate estimation, hitech normalization, confidence scoring, and lock state machine.

Current state:

- Rust crate defines `DspResult`, `TempoCandidate`, `SignalQuality`, lock states, hitech normalization, PCM onset analysis, autocorrelation tempo estimation, confidence gates, and a streaming engine boundary.
- Python/Node code remains as deterministic offline prototype coverage while Rust parity is verified.

Do not add UI code, microphone permission code, file decoding, or demo BPM values here.
