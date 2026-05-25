# Mobile Audio Notes

Mobile microphone integration starts after the Rust DSP/FFI contract can emit verified `DspResult` snapshots.

## Platform Responsibilities

Flutter owns permission flow, screen state, debug rendering, and session history. Native audio code owns low-latency PCM capture and pushes frames into `core/ffi`. The DSP core owns all BPM, confidence, lock-state, clipping, and candidate decisions.

## Latency Policy

- Audio callbacks must not allocate heavily, block on UI work, or perform file/network IO.
- Frame size and hop size must be documented per platform before release.
- The bridge should pass timestamps or monotonically ordered chunks so the DSP core can measure first-lock and stable-lock timing.
- Sample-rate conversion must happen in a documented adapter layer, not in UI widgets.

## Permission Policy

- Android must declare microphone permission in the app manifest when platform files are generated.
- iOS must include a human-readable microphone usage string when platform files are generated.
- Permission denial must keep the DSP state nullable and must not show fake BPM.

## Debug Requirements

Debug mode must show `primary_bpm`, confidence, lock state, signal quality, and the full candidate list. Clipping and unstable states must be visible in the live screen.
