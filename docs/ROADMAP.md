# Roadmap

## Phase 1: Offline DSP Lab

Goal: prove deterministic BPM detection against synthetic hitech fixtures before UI work.

Deliverables:

- `core/dsp` result contract and engine skeleton
- synthetic fixture generator
- offline analyzer CLI
- clean click/kick tests at 170, 180, 190, 200, and 220 BPM
- half-time and double-time trap tests
- silence and noise-only negative tests

Exit criteria:

- clean synthetic accuracy within +/-1 BPM
- no fake BPM on silence/noise-only
- candidate list exposes raw and normalized candidates
- offline report includes confidence, lock state, signal quality, and pass/fail

## Phase 2: Streaming DSP Core

Goal: make the detector work incrementally on audio chunks.

Deliverables:

- ring buffer
- rolling onset history
- candidate history
- confidence engine
- lock state machine
- first-lock and stable-lock timing tests

Exit criteria:

- first usable lock under 6 seconds on clean synthetic input
- stable lock under 12 seconds on valid hitech input
- no false `STABLE` on silence/noise-only
- `BREAKDOWN`, `CLIPPED_MIC`, and `UNSTABLE` are exercised by tests

## Phase 3: Mobile Audio Bridge

Goal: feed real microphone audio into the already-tested DSP engine.

Deliverables:

- microphone permission flow
- native audio bridge
- sample-rate conversion policy
- platform latency notes
- debug screen that renders the DSP contract
- session history storage

Exit criteria:

- mobile code does not calculate BPM directly
- permission and latency behavior is documented per platform
- debug mode shows candidates and confidence

## Phase 4: Hardening

Goal: handle club noise, clipping, breakdowns, unstable tempo, and real hitech recordings.

Deliverables:

- curated test recordings
- clipped microphone regression fixtures
- noisy club fixtures
- breakdown/no-kick scenarios
- algorithm comparison reports
- release checklist

Exit criteria:

- noisy mic target accuracy within +/-2-4 BPM when signal quality is adequate
- clipped input warns clearly and does not overstate confidence
- breakdown sections do not preserve stale `STABLE`
- release documentation identifies known limitations

## Next Patch

Implement the Phase 1 engine skeleton and test harness:

1. Add typed `DspResult`, `TempoCandidate`, `SignalQuality`, and lock-state definitions.
2. Add synthetic fixture generator for clean click/kick tracks.
3. Add offline test cases for 170, 180, 190, 200, 220, 100 half-time, 400 double-time, silence, noise, and clipped input.
4. Keep mobile UI untouched.
