# Manual Test Checklist — Phase 3 step 2

Things that automated tests cannot validate. Run these on hardware before merging the Phase 3 mobile bridge to `stage`.

## Setup

- [ ] Workspace built: `cargo build --release -p hitech-bpm-ffi` from repo root.
- [ ] `flutter pub get` clean in `apps/mobile/`.
- [ ] `flutter analyze` clean.
- [ ] `flutter test` green (FFI + widget tests).
- [ ] Hardware: at least one of:
  - Android device or emulator with API ≥ 24
  - iOS device or simulator with iOS ≥ 12
- [ ] Reference audio: a phone or speaker that can play a known-BPM track (suggested: a 200 BPM hitech mix, or a metronome at 200 BPM).

## Build & launch

- [ ] `cd apps/mobile && flutter run` succeeds on the target device.
- [ ] App icon appears with name "Hitech BPM Radar".
- [ ] No crash on cold launch.

## Permission flow

- [ ] First launch: system microphone permission prompt appears.
- [ ] iOS prompt text contains "music around you" wording (matches `NSMicrophoneUsageDescription`).
- [ ] On **grant**: app transitions to the live BPM screen within ~1 second; the BPM display starts as `— —` and updates as audio arrives.
- [ ] On **deny** (soft): app lands on the `PermissionDeniedScreen` with title "We need the microphone to detect BPM".
- [ ] Tapping "Grant microphone access" re-prompts. On grant the live screen appears without restart.
- [ ] On **permanently deny** (Android: tick "Don't ask again"; iOS: deny twice): screen offers "Open system settings"; tapping it opens system settings for this app.
- [ ] After enabling the permission in system settings and returning to the app, `PermissionGate` re-checks (via `didChangeAppLifecycleState`) and transitions to the live screen.

## Live capture path (with a reference speaker playing 200 BPM)

- [ ] Hold the phone within ~30 cm of the speaker.
- [ ] Within 6 s, `lock_state` leaves `SEARCHING` (badge changes color/label).
- [ ] Within 12 s, `lock_state` reads `STABLE` and `primary_bpm` is within 198–202 BPM.
- [ ] Confidence percentage rises monotonically (small dips OK) toward ≥ 70%.
- [ ] Input level dBFS meter is visible and moves with the speaker volume.
- [ ] Recent BPM sparkline shows a roughly flat line near 200 once locked.

## Negative / anti-fake spot checks

- [ ] Silence (mute speaker, cover mic): `lock_state` does NOT reach `STABLE`. `primary_bpm` returns to `— —`.
- [ ] Very loud playback (hold phone against the speaker): `signal_quality.clipping` flips to `true`, the red `CLIPPING` chip appears, and `lock_state` does not stay `STABLE` indefinitely (`CLIPPED_MIC` allowed).
- [ ] Half-time trap (play a 100 BPM kick): debug screen shows raw 100 BPM candidate visible AND a normalized 200 BPM candidate; primary should prefer 200 BPM in hitech mode.

## Debug screen

- [ ] Tapping the bug icon opens the debug screen.
- [ ] Candidate list shows ≥ 2 rows during STABLE playback.
- [ ] Each candidate row shows BPM (2 decimals), relation label (`main` / `half_time` / `double_time` / `raw` / `normalized_from_*`), and score.
- [ ] Signal-quality block shows every field from the DspResult contract (input_level_dbfs, peak_dbfs, clipping, clipped_frame_ratio, noise_level, snr_estimate_db, silence, breakdown_likely).
- [ ] Timing block shows analysis_time_sec advancing.
- [ ] Returning to the main screen does not restart capture (BPM does not drop back to `— —`).

## UI smoothness

- [ ] Sustained 60-second capture: UI remains responsive; no jank scrolling the debug screen.
- [ ] Background → foreground: app picks up where it left off (lock state may briefly transition through non-STABLE).
- [ ] Force-quit and relaunch: permission is remembered; live screen appears without re-prompting.

## Known platform-specific items

- Android emulator: the host microphone is shared with the emulator only if AVD audio passthrough is enabled. The lock test may pass with the host-side speaker playing reference audio.
- iOS simulator: there is no real microphone path; this checklist must be run on a physical iOS device for the live-capture rows.
- macOS (if ever built as a desktop target): privacy settings → Microphone must include the app; otherwise the permission flow falls through to `PermissionDeniedScreen` despite Apple-issued grants.

## Sign-off

- [ ] Hardware target(s) used: ____________________
- [ ] OS version(s): ____________________
- [ ] Date: ____________________
- [ ] Tester: ____________________
