# AGENTS.md — hitech-bpm-radar

## Toolchain Requirements

Always use these explicit binaries:

Node.js:
`/opt/homebrew/opt/nodejs/bin/node`

Cargo:
`/opt/homebrew/opt/rust/bin/cargo`

Do not rely on system PATH for Node.js or Rust toolchain discovery.

When running tests or build commands:
- use the explicit node binary
- use the explicit cargo binary

Examples:

```
/opt/homebrew/opt/nodejs/bin/node --version
/opt/homebrew/opt/rust/bin/cargo test
```

Never substitute these binaries with system-installed alternatives unless explicitly instructed.



## Project goal

Build a mobile application that detects BPM automatically through microphone input.
Primary target genre: hitech / psytrance, 170–230 BPM.
No tap tempo as the main mechanism.

The product must show:
- detected BPM
- confidence
- lock state
- tempo candidates
- half-time / double-time correction
- signal quality warnings
- session history

## Non-negotiable rules

- Do not fake BPM values.
- Do not hardcode demo BPM into production logic.
- Do not build UI before the DSP contract exists.
- Do not treat 100 BPM as final in hitech mode if 200 BPM is a stronger normalized candidate.
- Always expose confidence and candidate list in debug mode.
- For complex tasks, plan first, then implement.
- For every implementation task, update or add tests.
- For DSP changes, add synthetic test cases.
- For mobile audio changes, document platform-specific latency and permission behavior.
- Final answer must include:
  - changed files
  - what was implemented
  - how it was tested
  - known limitations
  - next recommended patch

## Target architecture

apps/mobile:
- UI
- microphone permissions
- native audio bridge
- live BPM screen
- debug screen
- session history

core/dsp:
- ring buffer
- preprocessing
- onset detection
- tempo estimation
- hitech BPM normalizer
- confidence engine
- lock state machine

tools/offline-lab:
- CLI analyzer for audio files
- synthetic fixture generator
- algorithm comparison reports

datasets:
- synthetic click tracks
- hitech test samples
- noisy club recordings
- clipped microphone examples

docs:
- architecture
- DSP algorithm
- QA matrix
- mobile audio notes
- release checklist

## Preferred implementation approach

Phase 1:
- Create offline analyzer and synthetic tests.
- No mobile UI yet.

Phase 2:
- Implement streaming DSP core.
- Define stable public API.

Phase 3:
- Add mobile microphone input.
- Connect live DSP output to UI.

Phase 4:
- Harden for club noise, clipping, breakdowns, unstable tempo.

## BPM logic

Primary target range:
- hitech: 170–230 BPM

Candidate normalization:
- if candidate < 130 BPM, test candidate * 2
- if candidate > 260 BPM, test candidate / 2
- keep all candidates with scores
- choose primary by score + genre range + stability
- never discard half-time / double-time candidates silently

## Required lock states

- SEARCHING
- LOCKING
- STABLE
- UNSTABLE
- BREAKDOWN
- CLIPPED_MIC
- NOISE_ONLY

## Required output contract

The DSP core must return nullable BPM results. If the signal is silence, noise-only, clipped beyond recovery, or otherwise untrustworthy, `primary_bpm` must be `null`; do not invent a fallback tempo.

```json
{
  "primary_bpm": 198.4,
  "confidence": 0.91,
  "lock_state": "STABLE",
  "signal_quality": {
    "input_level_dbfs": -12.4,
    "clipping": false,
    "noise_level": "medium"
  },
  "candidates": [
    {
      "bpm": 198.4,
      "relation": "main",
      "score": 0.91
    },
    {
      "bpm": 99.2,
      "relation": "half_time",
      "score": 0.67
    }
  ]
}
```

The full contract is documented in `docs/DSP_ALGORITHM.md`.

## Required tests

# DSP:

- 170 BPM synthetic
- 180 BPM synthetic
- 190 BPM synthetic
- 200 BPM synthetic
- 220 BPM synthetic
- 100 BPM half-time trap
- 400 BPM double-time trap
- noisy input
- clipped input
- breakdown / no-kick section

## Acceptance:

- clean synthetic accuracy: +/-1 BPM
- noisy mic target: +/-2-4 BPM
- first lock target: under 6 seconds
- stable lock target: under 12 seconds
- no false STABLE state on silence or noise-only input
