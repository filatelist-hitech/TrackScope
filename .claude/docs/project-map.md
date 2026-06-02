# MAGIC DOC: Project Structure

_Track architecture changes, important files, build system changes, DSP pipeline changes and FFI integrations._

_Last updated: 2026-06-03 (Radar no-scroll + energy/key always visible). Update this file when adding modules, changing FFI ABI, renaming build scripts, or shifting DSP pipeline stages._

---

## Overview

**hitech-bpm-radar** — DSP-first mobile BPM detector for hitech / psytrance (155–230 BPM target range). Microphone input only, no tap-tempo.

```
datasets/         Synthetic + real audio fixtures
core/
  dsp/            Rust DSP crate — source of truth; Python reference (tempo.py)
  ffi/            C ABI bridge (Flutter ↔ Rust)
  tests/          Python regression + parity tests
tools/offline-lab/ Python CLI analyzer, fixture generator, QA reports
apps/mobile/      Flutter shell — renders DSP contract, zero BPM math
docs/             Architecture, DSP algorithm spec, QA matrix, roadmap
scripts/          Build scripts (iOS / Android / release)
```

---

## Entry Points

| Context | Entry point |
|---|---|
| Rust DSP library | `core/dsp/src/lib.rs` — `DspEngine`, `analyze_pcm`, `DspConfig` |
| Rust DSP binary | `core/dsp/src/bin/analyze_wav.rs` — CLI WAV analyzer |
| Rust FFI | `core/ffi/src/lib.rs` — 6 C symbols exported |
| Flutter app (mobile) | `apps/mobile/lib/main.dart` |
| Flutter app (web) | `apps/mobile/lib/main_web.dart` (no RevenueCat) |
| Python offline analyzer | `tools/offline-lab/offline_lab.py` |
| Python parity tool | `tools/offline-lab/parity.py` |
| iOS native build | `scripts/build_ios_native.sh` → `libhitech_bpm_ffi.a` |
| Android native build | `scripts/build_android_native.sh` → `.so` (arm64/armeabi/x86_64) |

---

## Flutter Layer (`apps/mobile/lib/`)

```
lib/
├── main.dart                   App entry: ProStatusService init, ListenableBuilder tier-reactive CaptureBridge
├── main_web.dart               Web-safe entry (no purchases_flutter)
├── dsp/
│   ├── bindings.dart           Raw C ABI via dart:ffi
│   ├── dsp_result.dart         Typed DspResult, DspDebug, LockState, TempoRelation, KeyResult (Phase 2.1)
│   └── engine.dart             FFI handle lifetime + stream/poll
├── capture/
│   ├── capture_bridge.dart     DSP worker isolate, PCM→f32, analyzeJson poll, broadcast streams
│   ├── dsp_worker.dart         Isolate entry, owns FFI handle, PCM16→f32, ~10–30 Hz poll
│   ├── bpm_smoother.dart       Dart smoothing: median N=5, EMA conf α=0.2, hysteresis K=3
│   └── bpm_display.dart        EMA α=0.2 for big BPM number, snap on STABLE entry
├── permissions/
│   └── permission_gate.dart    Wraps package:permission_handler, re-checks on resume
├── theme/
│   ├── app_colors.dart         #050807 bg, #00DFB0 accent + surface/warning/success/noise tokens
│   └── app_text_styles.dart    IBM Plex Mono, roles: bpmHero/sectionLabel/ctaButton/…
├── widgets/
│   ├── bpm_hero_display.dart   72px hero, 3 modes: idle/detecting/unstable
│   ├── confidence_bar.dart     7px, red<30%/yellow30–70%/teal>70%, 400ms animation
│   ├── break_button.dart
│   ├── listening_indicator.dart
│   └── app_tab_bar.dart        7px tab labels
├── navigation/
│   └── app_navigator.dart      IndexedStack 3 tabs: Radar/History/Settings. CaptureBridge not recreated on tab switch
├── ui/
│   └── main_screen.dart        Waveform + Live Spectrum + InfoCard + ½/×2 cell + ListeningIndicator
├── screens/
│   ├── signal_analyzer_screen.dart  Pro-only, DspDebug metrics, top-4 candidates, 4px score bars
│   ├── settings_screen.dart    5 sections, SharedPreferences, WakelockPlus, BpmSmoothing picker
│   └── permission_denied_screen.dart
├── settings/
│   └── app_settings.dart       ChangeNotifier singleton: showWaveform, showSpectrum, keepScreenOn, inputSensitivity, bpmSmoothing
├── monetization/
│   ├── purchases_gateway.dart  Abstract
│   ├── revenue_cat_gateway.dart  Only file importing purchases_flutter
│   ├── pro_status_service.dart ChangeNotifier singleton
│   ├── feature_flags.dart      BPM range, debug, history, export gating
│   └── paywall_screen.dart     Design v2: FREE/PRO columns, CTA hierarchy, Roadmap card
├── history/
│   ├── bpm_history.dart        BpmSample (bpm, confidence), capped by duration/count
│   ├── session_history_controller.dart  ChangeNotifier, downsampler ~1 Hz
│   └── history_screen.dart     Group by day, 20px teal BPM + 3px confidence bar
├── export/
│   ├── bpm_exporter.dart       Pure builders buildCsv/buildJson
│   └── export_io.dart          exportCsv/exportJson via share_plus
├── viz/
│   ├── viz_controller.dart     ChangeNotifier: PCM ring buffer ~4s, Dart FFT via compute()
│   ├── waveform_painter.dart   Oscilloscope PCM, ambient glow + beat-reactive, red on clipping
│   ├── live_spectrum_painter.dart  Real-time FFT curve, gradient fill, peak-hold, log X 20–20kHz
│   └── spectrogram_painter.dart  Scrolling FFT map 200×128 bins (kept but not primary)
├── mock/
│   └── mock_dsp_stream.dart    Test-only mock stream
└── features/                   Feature flag helpers
```

**State management:** `ChangeNotifier` / `ListenableBuilder` / `Provider` (via `ChangeNotifierProvider`). No Riverpod/BLoC.

---

## Rust DSP Layer (`core/dsp/src/`)

```
lib.rs              DspEngine, DspConfig, DspResult, analyze_pcm, analyze_from_envelope
                    — autocorrelation tempo estimation
                    — parabolic peak interpolation (Phase 6)
                    — BPM candidate history N=3 median (Phase 6)
                    — state-based adaptive onset window (Phase 8)
                    — tempo jump detector (Phase 8)
                    — SNR estimation (estimate_snr_db, Phase 4)
energy_analyzer.rs  EnergyAnalyzer: RMS+flux+onset_density → level 1–10 (Phase 2.2)
                    Known: onset_density always maxed (passes flux-frame-count, not peak-count);
                    effective level range 3–10. Fix planned Phase 2.2.2.
genre_preset.rs     Genre presets (hitech 155–230 BPM defaults)
key_analyzer.rs     HPCP KeyAnalyzer (Phase 2.1) — STFT→12-bin HPCP→K-S→Camelot
                    KeyResult {key, mode, camelot, confidence}; integrated in DspEngine
bin/analyze_wav.rs         CLI batch: reads WAV → analyze_pcm → prints JSON
bin/stream_analyze_wav.rs  CLI streaming: feeds WAV → DspEngine 100ms chunks → prints JSON
                           Needed for energy_result / key_result (not in batch path)
```

**Key constants (lib.rs):**
- `ADAPTIVE_WINDOW_LOCKING_SECS = 6.0`
- `ADAPTIVE_WINDOW_SEARCHING_SECS = 2.0`
- `BPM_HISTORY_N = 3`
- `DspConfig::target_bpm_min = 155.0`, `target_bpm_max = 230.0`
- `DspConfig::broad_bpm_min ≈ 80`, `broad_bpm_max ≈ 460`

**Python reference:** `core/dsp/tempo.py`, `core/dsp/synthetic.py` — deterministic reference for parity tests. Not a runtime dependency for `cargo test`.

---

## FFI Layer (`core/ffi/`)

Six exported C symbols (`core/ffi/src/lib.rs`):
```c
hitech_bpm_engine_new()
hitech_bpm_engine_new_with_min_bpm(float min_bpm)  // Phase 10: Free=170, Pro=155
hitech_bpm_engine_free(handle)
hitech_bpm_engine_reset(handle)
hitech_bpm_engine_push_samples(handle, samples, len, sample_rate) -> bool
hitech_bpm_engine_analyze_json(handle) -> *mut c_char
hitech_bpm_string_free(ptr)
```

Header: `core/ffi/include/hitech_bpm_ffi.h`

**Internal buffers never cross FFI boundary** (pcm_window, onset_history, bpm_history).

---

## Build System

### iOS
```
scripts/build_ios_native.sh   → apps/mobile/ios/Frameworks/libhitech_bpm_ffi.a
apps/mobile/ios/Podfile       — Flutter + native bridge pod
```
Static lib linked via `Runner.xcodeproj`.

### Android
```
scripts/build_android_native.sh  → apps/mobile/android/app/src/main/jniLibs/<abi>/libhitech_bpm_ffi.so
                                    Targets: aarch64-linux-android, armv7-linux-androideabi, x86_64-linux-android
apps/mobile/android/app/build.gradle.kts
apps/mobile/android/key.properties.template  (key.properties gitignored)
```

### Flutter
```
apps/mobile/pubspec.yaml      — dependencies: fftea, shared_preferences, wakelock_plus, permission_handler,
                                 record, share_plus, purchases_flutter, provider
apps/mobile/lib/monetization/config.dart  — gitignored; RevenueCat API keys via --dart-define
```

---

## Test Infrastructure

```
core/dsp/tests/
  offline_contract.rs     Rust DSP regression (canonical fixture inventory)
  streaming.rs            Streaming timing tests (first-lock ≤6s, stable ≤12s, re-lock ≤3s)
  stability.rs            Parabolic interpolation precision, BPM streak stability
  range_coverage.rs       155–230 BPM matrix (16 points, step 5)
  key_detection.rs        HPCP KeyAnalyzer tests: Camelot mapping, JSON, silence/clip suppression (Phase 2.1)
  common/mod.rs           Deterministic fixture generators mirroring Python helpers

core/tests/
  test_offline_dsp_contract.py   Python regression (QA matrix fixtures)
  helpers/synthetic_fixtures.py  Python fixture generators

apps/mobile/test/
  widget_test.dart               MainScreen + InfoCard + badge states + energy/key always-visible (196 tests)
  dsp_debug_test.dart            DspDebug.fromJson parsing
  screens/signal_analyzer_screen_test.dart

tools/offline-lab/
  offline_lab.py   QA report generator (non-zero exit on regression)
  parity.py        Python↔Rust cross-language parity runner
```

**Test commands:**
```sh
/opt/homebrew/opt/rust/bin/cargo test --workspace
python3 -m unittest discover core/tests
python3 tools/offline-lab/offline_lab.py report
flutter test
flutter analyze
```

---

## DSP Contract (must not break)

`DspResult` JSON keys: `primary_bpm` (nullable), `confidence` (0–1), `lock_state`, `signal_quality`, `candidates`, `timing`, `debug`, `key_result` (optional, Phase 2.1), `energy_result` (optional, Phase 2.2)

`LockState`: SEARCHING | LOCKING | STABLE | UNSTABLE | BREAKDOWN | CLIPPED_MIC | NOISE_ONLY

`TempoRelation`: raw | main | half_time | double_time | normalized_from_half | normalized_from_double

---

## Naming Conventions

- Rust: `snake_case` everywhere; DSP structs `PascalCase`
- Dart/Flutter: `camelCase` methods, `PascalCase` classes, `snake_case` files
- Agents: `kebab-case.md` in `.claude/agents/`
- Skills: `kebab-case/SKILL.md` in `.claude/skills/`
- Test fixtures: `snake_case` (e.g. `clean_200`, `half_time_trap_100`)
- Rust test modules: `snake_case` function names under `#[cfg(test)]`

---

## Anti-Fake Invariants (never violate)

1. No hardcoded or random BPM in production paths
2. `primary_bpm` stays `null` until confidence exceeds capture threshold
3. Silence / noise / severe clipping **never** reach `STABLE`
4. Half-time and double-time candidates always visible in `candidates[]`
5. Confidence computed from onset evidence, not timers or constants
6. Mobile/UI layer never computes BPM — renders DSP contract only
