# Architecture

## Intent

hitech-bpm-radar is a DSP-first mobile BPM detector for hitech / psytrance in the 170-230 BPM range. The repository is structured so tempo logic is implemented once in `core/dsp` and reused by both the offline lab and the future mobile app.

## Dependency Direction

```text
datasets/ -> tools/offline-lab/ -> core/dsp/
apps/mobile/ ---------------------> core/dsp/
core/tests/ ----------------------> core/dsp/
docs/ ----------------------------> repository contracts
```

`core/dsp` must not depend on mobile UI code, file-system fixture loading, platform microphone APIs, or demo data. Adapters may feed audio into the DSP core, but they must not calculate BPM themselves.

## Module Boundaries

### `core/dsp`

Owns:

- sample format normalization
- ring buffer and streaming state
- preprocessing
- multiband onset detection
- onset history
- tempo candidate estimation
- hitech half-time / double-time normalization
- confidence scoring
- lock state machine
- public DSP result contract

Does not own:

- mobile permissions
- UI state
- platform audio callbacks
- file decoding
- dataset generation
- fake/demo BPM values

### `core/tests`

Owns deterministic DSP regression tests and expected-result fixtures. Every DSP algorithm change should add or update synthetic coverage.

### `tools/offline-lab`

Owns the offline analyzer, synthetic fixture generator, and report runner. It must call the same DSP API as mobile code.

### `datasets`

Stores generated and curated audio fixtures:

- `synthetic/`
- `hitech/`
- `noisy_club/`
- `clipped_mic/`
- `breakdowns/`

Large licensed audio files should not be committed without an explicit dataset policy.

### `apps/mobile`

Future mobile app boundary. It owns microphone permissions, native audio bridge behavior, result rendering, debug screen, and session history. It must not implement independent BPM logic.

## Public DSP API Shape

The implementation language is still open, but the stable conceptual API is:

```text
DspEngine(config)
DspEngine.push_samples(samples, sample_rate, timestamp_ms)
DspEngine.analyze() -> DspResult
DspEngine.reset()
```

Configuration must include hitech defaults:

```text
mode: hitech
target_bpm_min: 170
target_bpm_max: 230
analysis_window_seconds
hop_seconds
sample_rate
lock_min_seconds
stable_min_seconds
```

## Production Rules

- Do not build final UI before the DSP contract and synthetic tests exist.
- Do not fake BPM values.
- Do not hardcode demo BPM values in production code.
- Preserve raw and normalized tempo candidates.
- Expose confidence and candidate lists in debug output.
- Treat mobile audio as an input adapter, not a second DSP implementation.

## Primary Risks

- UI-first work can create fake confidence before the detector exists.
- Dense hitech material can produce half-time and double-time ambiguity.
- Microphone clipping and AGC can distort onset strength.
- Noise-only and breakdown sections can create false periodicity unless confidence is conservative.
- Mobile sample-rate drift and callback latency can affect lock timing.
