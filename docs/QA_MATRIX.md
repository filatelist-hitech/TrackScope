# QA Matrix

## Acceptance Targets

| Area | Required pass condition |
| --- | --- |
| Clean synthetic click tracks | 170, 180, 190, 200, and 220 BPM detected within +/-1 BPM |
| Noisy mic / club-like input | Primary BPM within +/-2-4 BPM when SNR is adequate |
| First lock | Reaches `LOCKING` or a usable candidate within 6 seconds |
| Stable lock | Reaches `STABLE` within 12 seconds only for valid consistent signal |
| Silence | Must not emit `STABLE` |
| White/pink noise | Must not emit `STABLE` |
| Clipped mic | Must flag clipping and reduce confidence or enter `CLIPPED_MIC` |
| Breakdown/no-kick | Must leave `STABLE` or decay confidence |
| Candidate normalization | Half-time and double-time candidates must be preserved |
| Hitech preference | 100 BPM must not win if normalized 200 BPM is stronger |

## Required Test Cases

| Case | Fixture | Expected primary | Expected state | Key checks |
| --- | --- | --- | --- | --- |
| Clean 170 | synthetic click or kick pulse | `170 +/-1` | `STABLE` by 12s | high candidate score |
| Clean 180 | synthetic click or kick pulse | `180 +/-1` | `STABLE` by 12s | no 90 BPM final lock |
| Clean 190 | synthetic click or kick pulse | `190 +/-1` | `STABLE` by 12s | stable ranking |
| Clean 200 | synthetic click or kick pulse | `200 +/-1` | `STABLE` by 12s | hitech baseline |
| Clean 220 | synthetic click or kick pulse | `220 +/-1` | `STABLE` by 12s | upper-range stability |
| Half-time trap | 100 BPM pulse in hitech mode | normalized `200 +/-1` if stronger | `STABLE` only when normalized candidate wins | raw 100 remains visible |
| Double-time trap | 400 BPM pulse | normalized `200 +/-1` if stronger | `STABLE` only when normalized candidate wins | raw 400 remains visible |
| Silence | zeros | `null` | `SEARCHING` or `NOISE_ONLY` | no false lock |
| White noise | broadband random | `null` or low-confidence candidate | `NOISE_ONLY` or `SEARCHING` | no false `STABLE` |
| Pink noise | 1/f noise | `null` or low-confidence candidate | `NOISE_ONLY` or `SEARCHING` | no false periodicity lock |
| Noisy 200 | 200 BPM plus noise | `196-204` | `LOCKING` or `STABLE` if SNR adequate | quality warning if noisy |
| Clipped 200 | hard-clipped 200 BPM | `196-204` if recoverable | `CLIPPED_MIC` or low confidence | clipping flag true |
| Breakdown | valid BPM then low/no onset section | prior BPM may decay | `BREAKDOWN` or `UNSTABLE` | confidence decay |
| Dense hitech bassline | simulated 190-210 rolling bass | +/-2 clean, +/-4 noisy | `STABLE` if periodic | avoid sub-pulse double lock |
| Unstable club simulation | noisy pulse with changing level/onset clarity | low-confidence or `UNSTABLE` unless consistent | `UNSTABLE` or `LOCKING` | uncertainty remains visible |

## Dataset Layout

```text
datasets/synthetic/     Generated clean click tracks, kick pulses, traps, silence, and noise.
datasets/hitech/        Curated real hitech / psytrance excerpts with licensing notes.
datasets/noisy_club/    Club-like noise, crowd rumble, and microphone contamination.
datasets/clipped_mic/   Phone microphone clipping and hard-limited examples.
datasets/breakdowns/    No-kick and low-onset sections after a stable pulse.
```

## QA Report Shape

Each offline-lab report row should include:

- fixture name
- expected BPM
- detected BPM
- BPM error
- confidence
- lock state
- signal quality warnings
- candidate list
- pass/fail
- notes

## Regression Policy

Every DSP algorithm change must add or update tests. Clean synthetic tests are the first gate, but they are not enough for production confidence; noisy, clipped, and breakdown cases are required before mobile integration is considered ready.

## Validation Commands

```sh
python3 -m unittest discover core/tests
node --test core/dsp/index.test.js
cargo test --workspace
```

Flutter validation becomes required once platform files and the microphone bridge are implemented.
