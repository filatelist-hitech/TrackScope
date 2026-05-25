---
name: mobile-audio-input
description: Use for Flutter microphone permissions, native audio capture, mono PCM buffering, sample-rate negotiation, platform latency notes, FFI bridge integration, and live BPM / debug UI rendering. Trigger whenever editing apps/mobile/, core/ffi/, apps/mobile/pubspec.yaml, when permission flows are designed, when iOS/Android audio behavior is discussed, or when the user mentions "microphone", "permissions", "FFI", "Flutter", "Dart", "audio bridge", "live BPM".
---

# Mobile Audio Input

1. Request microphone permission BEFORE opening capture. Document the prompt timing per platform.
2. Capture mono PCM frames in a callback-safe way. Never block the audio callback with allocation, file I/O, or network.
3. Send frames into `core/ffi` (and through it to Rust DSP). Do not compute BPM in Dart or in the FFI glue.
4. Render only values returned by the DSP contract — `primary_bpm`, `confidence`, `lock_state`, `signal_quality`, `candidates`.
5. Debug screen must show: lock state, confidence, candidate list with relation, input level dBFS, clipping flag, and any active warnings.
6. Document per platform: sample rate, frame size, callback latency, permission behavior, AGC notes. Keep `docs/MOBILE_AUDIO.md` aligned.
7. Sample-rate conversion: do it once, before the DSP push, with a deterministic policy.

Hard rules:

- No demo BPM, no random BPM, no timer-based fake pulse — anywhere in the production path.
- No hiding `CLIPPED_MIC`, `NOISE_ONLY`, `UNSTABLE`, or low confidence to keep the UI looking stable.
- No BPM math outside `core/dsp`.

References: @CLAUDE.md, @docs/MOBILE_AUDIO.md, @docs/ARCHITECTURE.md
