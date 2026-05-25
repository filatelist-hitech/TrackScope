---
name: mobile-audio-input
description: Use for mobile microphone input, audio permissions, native audio bridge, frame buffering, realtime audio flow, and UI connection.
---

# Mobile Audio Input Skill

Use this workflow for mobile audio work.

Required behavior:

1. Request microphone permission.
2. Capture mono PCM frames.
3. Send frames to DSP core.
4. Receive BPM state.
5. Render:
   - BPM
   - confidence
   - lock state
   - input level
   - warnings
6. Keep UI and DSP separated.

Rules:

- No fake demo BPM in production path.
- No blocking operations in audio callback.
- Document sample rate, frame size, hop size, and latency.
- Show clipping and unstable states clearly.