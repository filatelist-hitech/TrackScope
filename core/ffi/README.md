# core/ffi

Native bridge boundary for Flutter/mobile integration.

Responsibilities:

- own C ABI handles for `DspEngine`
- accept PCM frame pointers from platform audio code
- forward audio into Rust DSP without calculating BPM
- expose future serialized `DspResult` snapshots once the Rust engine reaches analyzer parity

This layer must remain thin. Candidate ranking, confidence, clipping, and lock state belong in `core/dsp`.
