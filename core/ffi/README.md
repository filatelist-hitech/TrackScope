# core/ffi

Native bridge boundary for Flutter/mobile integration.

Responsibilities:

- own C ABI handles for `DspEngine`
- accept PCM frame pointers from platform audio code
- forward audio into Rust DSP without calculating BPM
- expose serialized `DspResult` snapshots via `hitech_bpm_engine_analyze_json` (caller frees with `hitech_bpm_string_free`)

## C ABI surface

| Function | Purpose |
| --- | --- |
| `hitech_bpm_engine_new()` | Allocate a streaming engine with hitech defaults. Returns an opaque `*mut HitechBpmEngine`. |
| `hitech_bpm_engine_free(engine)` | Release an engine. Safe on null. |
| `hitech_bpm_engine_reset(engine)` | Drop rolling state without reallocating buffers. |
| `hitech_bpm_engine_push_samples(engine, samples, len, sample_rate) -> bool` | Append PCM. Allocation-light; safe to call from the audio thread. Returns `false` on null/zero-length input. |
| `hitech_bpm_engine_analyze_json(engine) -> *mut c_char` | Serialize the current rolling `DspResult` as UTF-8 JSON. Caller owns the buffer. Intended for UI-rate polling (~10–30 Hz), not the audio thread. Returns null on invalid handle. |
| `hitech_bpm_string_free(ptr)` | Release a string returned by `analyze_json`. Safe on null. |

JSON keys match the `DspResult` contract documented in `docs/DSP_ALGORITHM.md`: `primary_bpm`, `confidence`, `lock_state`, `signal_quality`, `candidates`, `timing`.

This layer must remain thin. Candidate ranking, confidence, clipping, and lock state belong in `core/dsp`.
