# Release Checklist

## DSP

- BPM is computed from audio/onset data.
- Confidence is calculated from evidence, not hardcoded.
- Raw and normalized candidates are preserved.
- Hitech normalization is tested.
- Silence and noise-only input do not produce `STABLE`.
- Clipping is detected and suppresses overconfident output.

## Mobile

- Microphone permission is handled on Android and iOS.
- Audio callback does not block.
- Flutter does not compute BPM directly.
- Live UI shows BPM, confidence, lock state, and clipping warnings.
- Debug screen shows tempo candidates and signal quality.

## Tests

- Synthetic BPM tests pass for 170, 180, 190, 200, and 220 BPM.
- Half-time and double-time traps are covered.
- Silence, white noise, pink noise, clipped mic, breakdown, and dense hitech fixtures are covered.
- Rust DSP contract tests pass.
- Offline lab CLI emits the documented JSON contract.

## Docs

- Architecture is current.
- DSP algorithm notes are current.
- Mobile audio latency and permission behavior are documented.
- Known limitations are documented.
