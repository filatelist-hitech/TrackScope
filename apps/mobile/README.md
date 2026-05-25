# apps/mobile

Future mobile application boundary.

This app will own microphone permissions, native audio bridge integration, live result rendering, debug output, and session history. It must not calculate BPM outside `core/dsp`.

No final UI should be built until the DSP contract and Phase 1 synthetic tests exist.
