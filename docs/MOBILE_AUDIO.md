# Mobile Audio Notes

Phase 3 step 2 lands the live capture pipeline: `package:record` feeds PCM into a dedicated DSP worker isolate that owns the Rust FFI handle, parses rolling `DspResult` snapshots, and ships them back to the UI isolate for `StreamBuilder` rendering.

## Pipeline (end-to-end)

```
┌─────────────── main (UI) isolate ───────────────┐    ┌──────── DSP worker isolate ────────┐
│                                                 │    │                                    │
│ AudioRecorder (package:record)                  │    │ DspEngine (FFI handle)             │
│   ↓ Stream<Uint8List> pcm16 mono 48 kHz         │    │   pushSamples(Float32List, sr)    │
│ MicrophoneSource                                │    │   analyzeJson() @ 20 Hz timer     │
│   ↓                                             │    │     ↓ JSON string                 │
│ CaptureBridge.start(pcmStream, sr, encoding)    │    │                                    │
│   sendPort.send(PushPcm(bytes, sr, encoding))   ├───►│ ReceivePort listener              │
│                                                 │    │   _decodePcm16Mono(bytes) → f32   │
│ ReceivePort listener:                           │    │   engine.pushSamples(f32, sr)     │
│   DspResultMessage(json) → DspResult.parse      │◄───┤ Timer.periodic → sendPort.send    │
│   WorkerError(message) → CaptureError stream    │    │   StopWorker → engine.dispose()   │
│                                                 │    │                                    │
│ Stream<DspResult> results                       │    │                                    │
│   → StreamBuilder<DspResult> on main/debug      │    │                                    │
└─────────────────────────────────────────────────┘    └────────────────────────────────────┘
```

## Capture Package Choice

`package:record` 5.x — pure Dart, supports `startStream(RecordConfig)` returning a `Stream<Uint8List>` of PCM bytes on every supported platform (Android, iOS, macOS, Linux, Web). The plugin runs its own native capture thread (AudioRecord on Android, AVAudioEngine on iOS), so the Dart-side stream callback receives buffers off the UI thread already. No platform channels written by us — the bridge stays UI-free.

## Isolate Model

We use a **dedicated DSP worker isolate**, not a dedicated capture isolate. Justification: `package:record`'s plugin platform channels are not designed to be initialized in a background Dart isolate; opening the recorder there risks "no implementation found" failures on first call. Capture itself is already off the UI thread (native side); the work that benefits from isolation is the FFI poll, JSON serialization, and PCM16 → f32 conversion — those move into the worker.

Spawn lifecycle:

1. `CaptureBridge.start()` is called from `_LiveCaptureScaffold.initState` after permission grant.
2. `Isolate.spawn(dspWorkerEntry, WorkerInit{replyPort, libraryPath, sampleRate, pollIntervalMs})`.
3. Worker opens its own `DspEngine` via `DspEngine.open(libraryPath:)` — each isolate must load the dylib in its own VM, but the FFI ABI is process-shared.
4. Worker sends `WorkerReady`; main signals start by listening to the local `package:record` stream and forwarding `PushPcm` messages over the SendPort.
5. Worker drives its own `Timer.periodic` calling `engine.analyzeJson()` and sends `DspResultMessage(json)` back. The engine's internal stream timer is disabled in this configuration (poll interval set to 1 hour) — the worker owns the poll cadence.
6. `CaptureBridge.dispose()` sends `StopWorker`, the worker frees its handle, then the bridge kills the isolate.

## Frame Format Reconciliation

| Platform | `package:record` output | Bridge conversion                          | DSP input    |
| -------- | ----------------------- | ------------------------------------------ | ------------ |
| Android  | PCM16 signed LE, mono   | `s / 32768.0` → Float32                    | f32 mono     |
| iOS      | PCM16 signed LE, mono   | `s / 32768.0` → Float32                    | f32 mono     |
| macOS    | PCM16 signed LE, mono   | `s / 32768.0` → Float32                    | f32 mono     |
| Linux    | PCM16 signed LE, mono   | `s / 32768.0` → Float32                    | f32 mono     |

- **Sample rate:** we ask the platform for 48 kHz; no resampling is performed. If a device cannot deliver 48 kHz, `package:record` rounds to the nearest supported rate — the worker forwards the announced rate into `pushSamples`, so the DSP sees the true rate.
- **Channels:** mono via `RecordConfig(numChannels: 1)`. No downmix code needed; the bridge rejects any chunk whose declared encoding it does not know rather than guessing.
- **dtype/byte order:** `pcm16bits` is signed 16-bit little-endian. Conversion happens in `apps/mobile/lib/capture/dsp_worker.dart::_decodePcm16Mono`, in the worker isolate. The DSP crate is never asked to handle integer samples.

The bridge also supports `pcm_f32le` for future ports that already deliver f32; the encoding is negotiated explicitly via `PushPcm.encoding` so a surprise format yields a `WorkerError`, not a silent miscount.

## Latency Policy

- Audio callbacks do not allocate beyond the per-chunk `Float32List` (negligible — a 100 ms chunk at 48 kHz is 9600 samples = 38 KB).
- The UI isolate sees no raw audio bytes; only typed `DspResult` snapshots reach the widget tree.
- Worker poll interval defaults to 50 ms (~20 Hz). Adjustable via `CaptureBridge(pollInterval:)`.
- First-lock and stable-lock timing acceptance (under 6 s / under 12 s on clean signal) is enforced by `core/dsp/tests/streaming.rs` and exercised end-to-end through the FFI by `apps/mobile/test/dsp_engine_test.dart`.

## Permission Policy

- Android: `<uses-permission android:name="android.permission.RECORD_AUDIO" />` in `apps/mobile/android/app/src/main/AndroidManifest.xml`. Runtime request via `package:permission_handler` on first launch.
- iOS: `NSMicrophoneUsageDescription` in `apps/mobile/ios/Runner/Info.plist` with user-readable copy explaining on-device processing and that no audio is recorded or sent.
- Denial path: `PermissionDeniedScreen` renders an explainer and either re-prompts (`Permission.microphone.request()`) on soft denial or opens system settings (`openAppSettings()`) on permanent denial. The app never silently falls back to a synthetic audio source.

## Anti-Fake Guarantees

- `apps/mobile/lib/` contains no hardcoded BPM literals (verified via grep). The only BPM-shaped value in production code is `bpm == null ? '— —' : bpm.toStringAsFixed(1)` in `main_screen.dart`, which reads from `DspResult.primaryBpm`.
- If `record` fails to start, `_LiveCaptureScaffold` surfaces the exception via a labelled error screen — the worker isolate is not asked to fabricate frames.
- If the FFI dylib fails to load in the worker, the worker emits `WorkerError("failed to open native DSP: …")` over the SendPort. `CaptureBridge` forwards this on its `errors` stream and `MainScreen` renders an error banner; the worker exits cleanly.
- UI subscribes only to `CaptureBridge.results`. No parallel state, no fallback timer, no demo source.

## Debug Requirements

The debug screen (`apps/mobile/lib/ui/debug_screen.dart`) renders:

- Full `candidates[]` list with `bpm`, `relation` (including `main`, `raw`, `half_time`, `double_time`, `normalized_from_half`, `normalized_from_double`), `score`, and `source_bpm` — half- and double-time candidates are always visible.
- All `signal_quality` fields (`input_level_dbfs`, `peak_dbfs`, `clipping`, `clipped_frame_ratio`, `noise_level`, `snr_estimate_db`, `silence`, `breakdown_likely`).
- `DspTiming` (analysis time, window, hop, first-lock time).

Both screens use the same `Stream<DspResult>` backed by `CaptureBridge.results`; no screen polls the engine.
