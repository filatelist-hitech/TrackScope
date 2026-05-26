# apps/mobile

Flutter mobile application boundary.

This app owns microphone permissions, native audio bridge integration, live result rendering, debug output, and session history. It must not calculate BPM outside `core/dsp`.

## Current state (Phase 3, step 1)

- `pubspec.yaml` defines the Flutter shell and the `ffigen` config that regenerates the Dart bindings from `core/ffi/include/hitech_bpm_ffi.h`.
- `lib/main.dart` renders a contract-gated placeholder with no fake BPM.
- `lib/dsp/bindings.dart` exposes the C ABI as `HitechBpmFfi`.
- `lib/dsp/dsp_result.dart` is a typed view over the JSON snapshot the Rust DSP emits — no BPM math on this side.
- `lib/dsp/engine.dart` owns the native handle, accepts mono `Float32List` PCM, and exposes a broadcast `Stream<DspResult>` polled at UI rate.
- Microphone capture and platform plugin code are intentionally not generated yet — they land in step 2.

## Running the FFI test

The Flutter test suite drives the real Rust DSP through the FFI layer:

```sh
# from the workspace root, build the shared library once
/opt/homebrew/opt/rust/bin/cargo build --release -p hitech-bpm-ffi

# from apps/mobile/
/opt/homebrew/bin/flutter pub get
/opt/homebrew/bin/flutter test
```

`test/helpers/native_library.dart` invokes `cargo build --release -p hitech-bpm-ffi` automatically if the dylib is missing, so a bare `flutter test` is enough on a clean checkout (provided the Rust toolchain is installed at the path documented in `AGENTS.md`).

## Regenerating the bindings

`lib/dsp/bindings.dart` is checked in so contributors don't need libclang locally just to build. To regenerate after changing the C header:

```sh
# from apps/mobile/
/opt/homebrew/bin/flutter pub run ffigen --config pubspec.yaml
```

## Next mobile patch

1. Generate Android/iOS platform files with Flutter.
2. Add microphone permissions (`NSMicrophoneUsageDescription`, `RECORD_AUDIO`).
3. Bind native audio capture to `DspEngine.pushSamples`.
4. Render only verified `DspResult` values from Rust (main + debug screens).
