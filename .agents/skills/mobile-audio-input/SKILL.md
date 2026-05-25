---
name: mobile-audio-input
description: Use for Flutter microphone permissions, native audio capture, buffering, latency notes, and DSP bridge integration.
---

# Mobile Audio Input

1. Request microphone permission before opening capture.
2. Capture mono PCM frames without blocking the audio callback.
3. Send frames to `core/ffi`; do not compute BPM in Flutter.
4. Render only values returned by the DSP contract.
5. Show lock state, confidence, clipping warnings, and candidate list in debug mode.
6. Document Android/iOS sample rate, frame size, latency, and permission behavior.

No production path may use demo BPM, random BPM, or timer pulses.
