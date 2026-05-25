# DSP Algorithm

## Scope

The DSP core detects BPM automatically from PCM audio. The primary genre target is hitech / psytrance at 170-230 BPM. Tap tempo is not the main mechanism.

The first implementation should be deterministic DSP. Machine learning is not part of the initial plan because the project needs explainable candidates, synthetic regression tests, and predictable mobile CPU behavior.

## Result Contract

```ts
type LockState =
  | "SEARCHING"
  | "LOCKING"
  | "STABLE"
  | "UNSTABLE"
  | "BREAKDOWN"
  | "CLIPPED_MIC"
  | "NOISE_ONLY";

type TempoRelation =
  | "raw"
  | "main"
  | "half_time"
  | "double_time"
  | "normalized_from_half"
  | "normalized_from_double";

interface DspResult {
  primary_bpm: number | null;
  confidence: number;
  lock_state: LockState;
  signal_quality: SignalQuality;
  candidates: TempoCandidate[];
  timing: DspTiming;
  debug?: DspDebug;
}

interface SignalQuality {
  input_level_dbfs: number | null;
  peak_dbfs: number | null;
  clipping: boolean;
  clipped_frame_ratio: number;
  noise_level: "low" | "medium" | "high" | "noise_only" | "unknown";
  snr_estimate_db: number | null;
  silence: boolean;
  breakdown_likely: boolean;
}

interface TempoCandidate {
  bpm: number;
  relation: TempoRelation;
  score: number;
  raw_score: number;
  stability_score: number;
  range_score: number;
  source_bpm?: number;
  confidence_factors: {
    onset_clarity: number;
    peak_prominence: number;
    harmonic_support: number;
    recent_stability: number;
    signal_quality: number;
  };
}

interface DspTiming {
  analysis_time_sec: number;
  window_time_sec: number;
  hop_time_sec: number;
  first_lock_time_sec: number | null;
}

interface DspDebug {
  onset_rate_hz: number;
  onset_strength: number;
  tempo_peak_prominence: number;
  harmonic_ambiguity: number;
  stability_score: number;
  warnings: string[];
}
```

Contract rules:

- `primary_bpm` is `null` until confidence clears the current lock threshold.
- `confidence` is always in the range `0.0..1.0`.
- `candidates` preserves raw and normalized options with relation metadata.
- Hitech mode prefers 170-230 BPM but does not hide ambiguity.
- A raw 100 BPM candidate can yield a normalized 200 BPM candidate, but both remain visible.
- A raw 400 BPM candidate can yield a normalized 200 BPM candidate, but both remain visible.

## Pipeline

1. Accept PCM audio chunks.
2. Convert to mono floating-point samples.
3. Normalize sample format and resample to the DSP rate if needed.
4. Preprocess with level tracking, silence detection, clipping detection, and kick-relevant filtering.
5. Compute multiband onset evidence:
   - broadband spectral flux
   - low-frequency energy flux for kick pulse
   - high-frequency transient flux for noisy recordings
6. Maintain onset history in rolling windows.
7. Estimate tempo candidates using autocorrelation, comb matching, and inter-onset interval support.
8. Normalize hitech half-time and double-time candidates.
9. Score candidates using tempo evidence, hitech range fit, harmonic support, recent stability, and signal quality.
10. Classify lock state.
11. Emit a `DspResult` snapshot.

## Candidate Normalization

Search a broad internal range, such as 80-460 BPM, so traps are observable before normalization.

Rules:

- If a raw candidate is below 130 BPM, also create `bpm * 2` with relation `normalized_from_half`.
- If a raw candidate is above 260 BPM, also create `bpm / 2` with relation `normalized_from_double`.
- Keep raw, half-time, double-time, and normalized candidates in the candidate list.
- Choose the primary candidate by combined score, not by range alone.
- Do not finalize 100 BPM in hitech mode if normalized 200 BPM has stronger evidence.

## Confidence Engine

Confidence is a composite of:

- onset clarity
- tempo peak prominence
- harmonic support
- recent candidate stability
- hitech range score
- signal quality
- amount of audio observed
- ambiguity penalty between close candidates

Silence, clipping, weak onset density, noise-only structure, and breakdown sections must suppress confidence.

## Lock States

- `SEARCHING`: not enough usable signal or history.
- `LOCKING`: candidate exists, but stability or duration is not yet sufficient.
- `STABLE`: high confidence, stable primary candidate, and acceptable signal quality.
- `UNSTABLE`: candidates jump or confidence drops while signal remains musical.
- `BREAKDOWN`: a previous tempo existed, but current onset density or kick pulse collapsed.
- `CLIPPED_MIC`: clipping ratio is high enough to compromise analysis.
- `NOISE_ONLY`: signal exists, but there is no reliable periodic onset structure.

Silence and noise-only input must never become `STABLE`.

## Streaming And Offline Boundaries

The streaming core processes small chunks, maintains ring buffers, and emits periodic snapshots. It must support session reset.

The offline analyzer feeds decoded audio into the same engine in deterministic chunks. It may produce richer reports, but it must not use a separate tempo algorithm after Rust parity.

Current implementation state:

- Rust `core/dsp` is the production source of truth: it contains the typed contract, signal-quality measurement, multiband onset envelope, autocorrelation tempo estimation, hitech candidate normalization, confidence scoring, and lock-state gates as native code (no FFI, no subprocess).
- `core/dsp/tempo.py` and `core/dsp/synthetic.py` remain as the readable algorithmic reference and are exercised by the Python suite and the offline-lab report; they are no longer a runtime dependency of `cargo test`.
- `cargo test --workspace` is hermetic: Rust DSP regression coverage lives in `core/dsp/tests/offline_contract.rs` (using the shared deterministic fixture module `core/dsp/tests/common/mod.rs`) and asserts the contract directly, without invoking Python.
- Cross-language parity is an opt-in tool: `python3 tools/offline-lab/parity.py` generates the canonical fixture inventory, runs both the Python analyzer and the Rust `analyze_wav` binary on the same WAV bytes, and reports per-fixture drift. It is not part of `cargo test`.
- Python signal quality emits `snr_estimate_db: null` until a real noise-floor estimator exists; current noise gating uses level, clipping, crest, and onset-periodicity evidence instead of a fake SNR value.
- Clipping is graded by clipped-frame ratio: mild clipping caps confidence below `STABLE` while keeping candidates visible; severe clipping (>= 5% of frames) forces `CLIPPED_MIC` and suppresses `primary_bpm`.
