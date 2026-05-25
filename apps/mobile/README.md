# apps/mobile

Flutter mobile application boundary.

This app owns microphone permissions, native audio bridge integration, live result rendering, debug output, and session history. It must not calculate BPM outside `core/dsp`.

Current state:

- `pubspec.yaml` defines the Flutter shell.
- `lib/main.dart` renders a contract-gated placeholder with no fake BPM.
- Platform microphone files are intentionally not generated yet.

Next mobile patch:

1. Generate Android/iOS platform files with Flutter.
2. Add microphone permissions.
3. Bind native audio capture to `core/ffi`.
4. Render only verified `DspResult` values from Rust.
