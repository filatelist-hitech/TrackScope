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
| Clipped 200 | hard-clipped 200 BPM | `null` for severe clipping; `196-204` only if recoverable | `CLIPPED_MIC` or low confidence | clipping flag true and no false `STABLE` |
| Breakdown | valid BPM then low/no onset section | prior BPM may decay | `BREAKDOWN` or `UNSTABLE` | confidence decay |
| Dense hitech bassline | simulated 190-210 rolling bass | +/-2 clean, +/-4 noisy | `STABLE` if periodic | avoid sub-pulse double lock |
| Unstable club simulation | noisy pulse with changing level/onset clarity | low-confidence or `UNSTABLE` unless consistent | `UNSTABLE` or `LOCKING` | uncertainty remains visible |

## Current Offline Lab Verification

Verified on 2026-05-25 with deterministic generated PCM fixtures through `python3 tools/offline-lab/offline_lab.py report`. The report generates audio samples in memory, analyzes PCM onset evidence, and uses expected BPM metadata only for pass/fail evaluation; it does not hardcode analyzer output.

| Fixture | Expected BPM | Detected BPM | Error | Confidence | Lock state | Signal quality | Candidate evidence | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `clean_170` | 170.0 | 170.2 | 0.2 | 0.856 | `STABLE` | no clipping | 170.2 `main`, 170.2 `raw`, 85.1 `raw` | PASS | Clean hitech-range pulse within +/-1 BPM. |
| `clean_180` | 180.0 | 180.5 | 0.5 | 0.774 | `STABLE` | no clipping | 180.5 `main`, 180.5 `raw`, 89.9 `raw` | PASS | Clean hitech-range pulse within +/-1 BPM. |
| `clean_190` | 190.0 | 190.5 | 0.5 | 0.809 | `STABLE` | no clipping | 190.5 `main`, 190.5 `raw`, 94.9 `raw` | PASS | Clean hitech-range pulse within +/-1 BPM. |
| `clean_200` | 200.0 | 200.0 | 0.0 | 0.874 | `STABLE` | no clipping | 200.0 `main`, 200.0 `raw`, 100.0 `raw` | PASS | Clean hitech baseline. |
| `clean_220` | 220.0 | 220.2 | 0.2 | 0.867 | `STABLE` | no clipping | 220.2 `main`, 220.2 `raw`, 110.1 `raw` | PASS | Upper hitech-range pulse within +/-1 BPM. |
| `half_time_trap_100` | 200.0 | 200.0 | 0.0 | 0.854 | `STABLE` | no clipping | 200.0 `main`, 200.0 `normalized_from_half`, 100.0 `raw` | PASS | Preserves raw 100 BPM while choosing normalized 200 BPM in hitech mode. |
| `double_time_trap_400` | 200.0 | 200.0 | 0.0 | 0.858 | `STABLE` | no clipping | 200.0 `main`, 200.0 `normalized_from_double`, 400.0 `raw` | PASS | Preserves raw 400 BPM while choosing normalized 200 BPM in hitech mode. |
| `silence` | `null` | `null` | n/a | 0.0 | `SEARCHING` | silence, no clipping | none | PASS | No false `STABLE` lock. |
| `white_noise` | `null` | `null` | n/a | 0.203 | `NOISE_ONLY` | no clipping | low-score candidates only | PASS | No false `STABLE` lock on deterministic broadband noise. |
| `pink_noise` | `null` | `null` | n/a | 0.219 | `NOISE_ONLY` | no clipping | low-score candidates only | PASS | No false `STABLE` lock on deterministic low-frequency-biased noise. |
| `clipped_200` | `null` | `null` | n/a | 0.34 | `CLIPPED_MIC` | severe clipping flagged | 200.0 `main`, 200.0 `raw`, 100.0 `raw` | PASS | Candidate evidence remains visible, but primary BPM is suppressed when clipped-frame ratio reaches the severe threshold. |
| `recoverable_clipped_200` | 200.0 | 200.0 | 0.0 | 0.690 | `LOCKING` | mild clipping flagged | 200.0 `main`, 200.0 `raw`, 100.0 `raw` | PASS | Mild clipping caps confidence below `STABLE` while tempo candidates stay usable. |
| `breakdown_200` | `null` | `null` | n/a | 0.42 | `BREAKDOWN` | breakdown likely, no clipping | 200.0 `main`, 200.0 `raw`, 100.0 `raw` | PASS | Prior tempo candidate remains visible, but final lock is rejected. |
| `dense_hitech_bassline_200` | 200.0 | 200.0 | 0.0 | 0.874 | `STABLE` | no clipping | 200.0 `main`, 200.0 `raw`, 100.0 `raw` | PASS | Rolling bassline does not promote sub-pulses over the beat. |
| `unstable_club_simulation` | `null` | `null` | n/a | 0.182 | `NOISE_ONLY` | noisy, no clipping | low-score candidates only | PASS | Tempo drift, dropouts, rumble, and broadband noise keep uncertainty visible. |

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

The first deterministic offline-lab report is produced with:

```sh
python3 tools/offline-lab/offline_lab.py report
```

The report analyzes generated PCM fixtures directly, including clean 170/180/190/200/220 BPM pulses, half-time and double-time traps, silence, white noise, pink noise, severe and recoverable clipped microphone input, no-kick breakdown, dense hitech bassline simulation, and unstable club simulation. It exits non-zero if any row fails.

Half-time and double-time trap rows validate both the visible raw candidate and the normalized candidate relation/source pair, not only the numeric BPM.

## Regression Policy

Every DSP algorithm change must add or update tests. Clean synthetic tests are the first gate, but they are not enough for production confidence; noisy, clipped, and breakdown cases are required before mobile integration is considered ready.

## Validation Commands

```sh
python3 -m unittest discover core/tests
node --test core/dsp/index.test.js
cargo test --workspace                       # hermetic: does not invoke python3
python3 tools/offline-lab/offline_lab.py report
python3 tools/offline-lab/parity.py          # optional cross-language Python ↔ Rust check
```

Flutter validation becomes required once platform files and the microphone bridge are implemented.

## Rust Fixture Inventory

The Rust DSP regression suite (`core/dsp/tests/offline_contract.rs`) consumes the deterministic generators in `core/dsp/tests/common/mod.rs`, which mirror `core/tests/helpers/synthetic_fixtures.py`. The canonical inventory is:

| Fixture | Generator | Expected lock state | Expected primary BPM |
| --- | --- | --- | --- |
| `clean_170` | `pulse_track(170.0, …)` | `STABLE` | 170 ±1 |
| `clean_180` | `pulse_track(180.0, …)` | `STABLE` | 180 ±1 |
| `clean_190` | `pulse_track(190.0, …)` | `STABLE` | 190 ±1 |
| `clean_200` | `pulse_track(200.0, …)` | `STABLE` | 200 ±1 |
| `clean_220` | `pulse_track(220.0, …)` | `STABLE` | 220 ±1 |
| `half_time_trap_100` | `pulse_track(100.0, …)` | `STABLE` | 200 ±1 (raw 100 visible) |
| `double_time_trap_400` | `pulse_track(400.0, …)` | `STABLE` | 200 ±1 (raw 400 visible) |
| `silence` | `silence(…)` | `SEARCHING` / `NOISE_ONLY` | `null` |
| `white_noise` | `white_noise(170170, 0.28, …)` | `NOISE_ONLY` / `UNSTABLE` | `null` |
| `pink_noise` | `pink_noise(220220, 0.32, …)` | `NOISE_ONLY` / `UNSTABLE` | `null` |
| `recoverable_clipped_mic` | `recoverable_clipped_pulse(200.0, …)` | `LOCKING` / `STABLE` | 200 ±2 |
| `severely_clipped_mic` | `severely_clipped_pulse(200.0, …)` | `CLIPPED_MIC` | `null` |
| `breakdown_without_kick` | `breakdown_without_kick(200.0, 6.0, 8.0, …)` | `BREAKDOWN` / `UNSTABLE` / `LOCKING` / `SEARCHING` | `null` |
| `dense_hitech_bassline` | `dense_hitech_bassline(200.0, …)` | `STABLE` | 200 ±2 |
| `unstable_club_simulation` | `unstable_club_simulation(…)` | `NOISE_ONLY` / `UNSTABLE` / `LOCKING` / `SEARCHING` | `null` |

`canonical_fixture_inventory_round_trip` in `offline_contract.rs` walks the full inventory and asserts the anti-fake invariants (no `STABLE` on silence/noise/severe clipping, half/double relations preserved on traps).
