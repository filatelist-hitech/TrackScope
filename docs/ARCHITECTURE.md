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

The production source of truth is the Rust crate in `core/dsp`. The current Python/Node offline analyzer remains as a Phase 1 deterministic lab and regression reference until the Rust streaming engine reaches parity.

## Module Boundaries

### `core/dsp`

Owns:

- Rust `DspEngine` contract
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

Owns the Python offline analyzer, synthetic fixture generator, and report runner. During Phase 1 it may call the Python prototype under `core/dsp`; after Rust parity it must call the Rust DSP API through the same boundary as mobile.

### `core/ffi`

Owns the native C ABI handle boundary used by Flutter/native code. It may manage engine lifetimes and pass PCM frames into Rust DSP, but it must not score or rank BPM itself.

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

The Rust DSP crate exposes the stable conceptual API:

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

## Codex Infrastructure

- `.codex/config.toml` sets the project model, sandbox, and max agent concurrency.
- `.codex/agents/*.toml` defines ARCHMAN, DSPMAN, MOBILEMAN, QAMAN, PERFMAN, REVIEWMAN, and DOCMAN.
- `.codex/plans/PLANS.md` is the required planning template for non-trivial work.
- `.agents/skills/*/SKILL.md` stores reusable local skills for bootstrap, DSP, mobile audio, QA datasets, and review gates.

## Primary Risks

- UI-first work can create fake confidence before the detector exists.
- Dense hitech material can produce half-time and double-time ambiguity.
- Microphone clipping and AGC can distort onset strength.
- Noise-only and breakdown sections can create false periodicity unless confidence is conservative.
- Mobile sample-rate drift and callback latency can affect lock timing.
