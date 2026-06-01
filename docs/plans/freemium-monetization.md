# Freemium monetization: Free vs Pro (RevenueCat IAP)

## Context

The app is a DSP-first hitech/psytrance BPM detector (Flutter shell over a Rust DSP
core via FFI). Today it ships every capability to everyone and has no monetization.
The goal is a **two-tier freemium model** (Free / Pro) with RevenueCat IAP, a paywall,
and feature gates on: BPM range, debug screen, BPM history, and log export. The lock-screen
widget is explicitly **out of scope** (next PR) and only stubbed as "coming soon".

Two product decisions were confirmed with the user up front:

1. **BPM-range gate = extend the FFI to pass `min_bpm` into Rust.** The Free detector
   becomes *literally* 170–230 (sub-170 simply never out-ranks / locks); Pro is 155–230.
   This **modifies the DSP/FFI core by explicit user choice**, which supersedes the
   repo's "don't modify DSP core" constraint for this task. It is the honest path
   (Rust does the ranging; no UI BPM math, anti-fake clean).
2. **History = a dedicated History screen** (not just a cap chip), since the app has no
   history feature at all today.

### Reality vs. the task's sample code (important divergences)

- There is **no `StreamingConfig`** in Dart and `hitech_bpm_engine_new(void)` takes **no
  config** — so `min_bpm` must be threaded through a *new* FFI entry point. (`DspConfig`
  already has a `target_bpm_min` field, default `155.0`, used by `range_score()` at
  `core/dsp/src/lib.rs:1043` — so no DSP *algorithm* change, only a new constructor path.)
- There is **no `provider`** package; the repo uses explicit constructor injection +
  `ChangeNotifier` (e.g. `VizController`) + `Stream`s. We will **not** add `provider`;
  `ProStatusService` is a `ChangeNotifier` singleton consumed via `ListenableBuilder`.
- There is **no history/export feature** — `BpmHistory`, the controller, the screen, and
  the exporter are all net-new.
- `main_web.dart` is a separate web-preview entry (MockDspStream). It must stay
  web-safe: **`purchases_flutter` must not enter the web build tree.**
- Toolchain verified: Flutter 3.44 / Dart 3.12, Cargo 1.95. Android `minSdk =
  flutter.minSdkVersion` (≥21 ✓ for RevenueCat), iOS target 13.0 ✓.

---

## Task classification
- **Complexity:** high
- **Domains:** dsp (FFI knob), mobile (primary), ui (paywall/history/gates), qa (tests), docs, security (secret handling)

## Agents & skills (for implementation phase)
- `@dspman` — review the FFI `min_bpm` knob + add the Rust FFI contract test (parity unaffected: default ctor stays 155).
- `@mobileman` (primary) — all Flutter: SDK, ProStatusService, FeatureFlags, paywall, gates, history, export, FFI plumbing.
- `@archman` — confirm gating does not leak into the DSP contract beyond the intended `min_bpm` knob.
- `@reviewman` + skill `review-gate` — pre-merge gate.
- Skill `mobile-audio-input` — history/export consume audio-derived results.

---

## Implementation steps

### 0. Persist plan
- Copy this plan to `docs/plans/freemium-monetization.md` (repo convention from `docs/plans/`).

### 1. FFI `min_bpm` knob (additive, backward-compatible)
- **`core/ffi/src/lib.rs`** — add a second constructor (keep the existing one):
  ```rust
  #[no_mangle]
  pub extern "C" fn hitech_bpm_engine_new_with_min_bpm(min_bpm: f32) -> *mut HitechBpmEngine {
      let clamped = if min_bpm.is_finite() { min_bpm.clamp(80.0, 230.0) } else { 155.0 };
      let cfg = DspConfig { target_bpm_min: clamped, ..DspConfig::default() };
      Box::into_raw(Box::new(HitechBpmEngine { inner: DspEngine::new(cfg) }))
  }
  ```
  Existing `hitech_bpm_engine_new()` is unchanged (delegates to `DspConfig::default()` = 155).
- **`core/ffi/include/hitech_bpm_ffi.h`** — add prototype
  `HitechBpmEngine *hitech_bpm_engine_new_with_min_bpm(float min_bpm);`
- **`core/ffi/tests/ffi_contract.rs`** — add a test mirroring existing style
  (`pulse_*_bpm` + `analyze_json`): with `min_bpm = 170`, a clean ~160 BPM pulse must
  **not** finalize as `STABLE` at ~160 (range under-ranked), while the default ctor
  (155) does lock ~160; and a 200 BPM pulse still reaches `STABLE` under both. Proves
  the knob end-to-end.
- **No change to `core/dsp/src/lib.rs` math** — `DspConfig`/`DspEngine::new` already accept it.
- **Caveat to document:** the prebuilt `.so/.dylib/.a` are gitignored and must be rebuilt
  to run on device/desktop (`scripts/build_{ios,android}_native.sh`; macOS test dylib is
  auto-built by `test/helpers/native_library.dart` only when *absent* — devs with a stale
  `target/release` dylib should `cargo build --release -p hitech-bpm-ffi`). `ffigen`
  regen is optional since `bindings.dart` is hand-edited below.

### 2. Dart FFI plumbing (thread min_bpm through the worker)
- **`apps/mobile/lib/dsp/bindings.dart`** — add `engineNewWithMinBpm` typedef
  (`Pointer<HitechBpmEngine> Function(Float)` / `Function(double)`) + `dylib.lookup(...)`,
  matching ffigen style.
- **`apps/mobile/lib/dsp/engine.dart`** — `DspEngine.open({..., double? minBpm})` and
  `fromBindings({..., double? minBpm})`: if `minBpm != null` call `engineNewWithMinBpm`,
  else `engineNew()` (back-compat; existing tests untouched).
- **`apps/mobile/lib/capture/capture_messages.dart`** — add `final double? minBpm` to `WorkerInit`.
- **`apps/mobile/lib/capture/dsp_worker.dart`** — pass `init.minBpm` to `DspEngine.open`.
- **`apps/mobile/lib/capture/capture_bridge.dart`** — `CaptureBridge({..., double? minBpm})`
  → into `WorkerInit`.

### 3. Monetization core (new `apps/mobile/lib/monetization/`)
- **`purchases_gateway.dart`** — abstract `PurchasesGateway` (configure / getIsPro /
  purchaseLifetime / purchaseAnnual / restore / onProChanged) — the **test seam**.
- **`revenuecat_gateway.dart`** — real impl; the **only** file importing
  `purchases_flutter`. Maps entitlement `'pro'`, packages `$rc_lifetime` / `$rc_annual`.
- **`pro_status_service.dart`** — `ChangeNotifier` singleton (`ProStatusService.instance`),
  holds `bool isPro`, takes a `PurchasesGateway` (default real, injectable fake).
  `initialize({iosKey, androidKey})` is a **no-op staying Free when the key is empty** →
  Free works fully offline/keyless. **Does not import `purchases_flutter`.**
- **`feature_flags.dart`** — `FeatureFlags({required isPro})`: `minBpm` (170/155),
  `maxBpm` 230, `canAccessDebugScreen`, `canExport`, `canAccessWidget`,
  `maxHistoryDuration` (30s / 24h), `maxHistorySamples`.
- **`config.dart.template`** (committed) — documents key setup. Real keys are supplied at
  build via `--dart-define` / `--dart-define-from-file` and read in `main.dart` with
  `String.fromEnvironment`. **No committed lib code imports `config.dart`**, so its
  absence never breaks `flutter analyze`/CI. Add `apps/mobile/lib/monetization/config.dart`
  to `.gitignore` (satisfies the literal requirement; file stays an optional local convenience).

### 4. Paywall (new `apps/mobile/lib/monetization/paywall_screen.dart`)
- `PaywallScreen({required String feature})`; comparison table (Free vs Pro), Lifetime
  $4.99 + Annual $3.99/yr buttons, "Restore purchases", and the lock-screen-widget
  "Скоро · iOS 16+ и Android" tile. **Styled with `AppTheme` tokens** from
  `design_tokens.dart` (accent `#00E5CC`, bg `#07070F`, mono), not raw hex.
- Buttons call `ProStatusService.instance.purchase*/restore`; show success/cancel/error
  via SnackBar. **No `debugPrint` of purchase/transaction data.**

### 5. History + export (new)
- **`apps/mobile/lib/history/bpm_history.dart`** — `BpmSample(bpm, state, timestamp)` +
  `BpmHistory(flags)`; cap primarily by `flags.maxHistoryDuration` (drop leading samples
  older than `now - duration`) with `maxHistorySamples` as a hard ceiling; `isAtLimit`.
- **`apps/mobile/lib/history/session_history_controller.dart`** — `ChangeNotifier`
  subscribing to `CaptureBridge.results`; **downsample to ~1 Hz** (store when `primaryBpm
  != null` and ≥1 s since last); rebuildable when `FeatureFlags` change.
- **`apps/mobile/lib/history/history_screen.dart`** — dedicated screen: scrollable
  timestamp / BPM / lock-state rows; Pro shows export menu (CSV/JSON); Free shows a
  "30 сек · Upgrade →" cap banner that opens `PaywallScreen(feature:'history')`.
- **`apps/mobile/lib/export/bpm_exporter.dart`** — **pure** `buildCsv(samples)->String`
  and `buildJson(samples)->String` (unit-tested) split from the IO
  `exportCsv/exportJson` (share_plus + path_provider). CSV header
  `timestamp,bpm,lock_state`; JSON `{app, exported_at, samples:[{timestamp,bpm,lock_state}]}`.

### 6. Wiring & gates
- **`apps/mobile/lib/main.dart`** — at startup read keys via `String.fromEnvironment`,
  `await ProStatusService.instance.initialize(...)`; own a `SessionHistoryController`;
  derive `FeatureFlags` from pro status; build `CaptureBridge(minBpm: flags.minBpm)`.
  Wrap the live scaffold in `ListenableBuilder(listenable: ProStatusService.instance)`:
  **on tier change, dispose + respawn the `CaptureBridge` with the new `minBpm`** and
  restart mic capture (engine rolling state resets — acceptable; this is not an app
  restart, satisfying "switches without restart"). Pass `flags` + history controller +
  pro service down to `MainScreen`.
- **`apps/mobile/lib/ui/main_screen.dart`** — add `FeatureFlags flags`,
  `SessionHistoryController history`, and paywall/history navigation callbacks:
  - Debug icon (`main_screen.dart:93`): if `flags.canAccessDebugScreen` → debug, else →
    `PaywallScreen(feature:'debug_screen')`.
  - App-bar: add a History entry + a small upgrade/PRO affordance → paywall.
  - Info card: history cap chip (Free, `history.isAtLimit`) + export affordance
    (Pro popup CSV/JSON; Free locked icon → paywall). Keep the existing ×½/×2 cell visible
    for all tiers (half/double stay visible per anti-fake).
- **`apps/mobile/lib/main_web.dart`** — keep web-safe: construct `MainScreen` with a fixed
  `FeatureFlags(isPro: …)` + a no-op `ProStatusService` (fake gateway) + empty history; do
  **not** pull `revenuecat_gateway.dart` into the web tree.

### 7. Dependencies — `apps/mobile/pubspec.yaml`
- Add `purchases_flutter`, `share_plus`, `path_provider`, pinned to versions compatible
  with Flutter 3.44 / Dart 3.12 (resolve actual constraints with `flutter pub get`; the
  task's `^7/^9/^2` are starting points, bump if resolution fails).

---

## Tests
New (Flutter):
- `test/monetization/pro_status_service_test.dart` — fake `PurchasesGateway`: `isPro`
  toggles + `notifyListeners` fires; empty-key `initialize` stays Free.
- `test/monetization/feature_flags_test.dart` — `minBpm` 170(free)/155(pro), maxHistory
  caps, gate booleans.
- `test/monetization/paywall_screen_test.dart` — smoke render; both purchase buttons +
  Restore + "Скоро" widget tile present.
- `test/history/bpm_history_test.dart` — add/cap (Free 30s vs Pro), `isAtLimit`.
- `test/export/bpm_exporter_test.dart` — CSV header+rows + JSON shape on mock samples
  (pure builders; no platform channel).
- `test/widget_test.dart` — update `MainScreen(...)` constructor calls (new params);
  add debug-gate test (Free→paywall, Pro→debug).
New (Rust): the `core/ffi/tests/ffi_contract.rs` min_bpm test (step 1).

Commands (run before reporting done):
```sh
/opt/homebrew/opt/rust/bin/cargo test --workspace          # Rust DSP+FFI incl new min_bpm test
cd apps/mobile && flutter analyze                          # must be 0 errors
cd apps/mobile && flutter test                             # all incl new monetization/history/export
python3 -m unittest discover core/tests                    # unaffected; run as guard
```
- `parity.py` is unaffected (default ctor still 155; new symbol is additive).
- UI preview (localhost:7654, `ui-preview` skill) to visually verify paywall + history
  layout — note purchases are no-op on web; preview Pro vs Free via the fixed flag.

## Risks & fallbacks
- **Stale native dylib** hides the new symbol → document the rebuild; Rust test covers
  the knob regardless.
- **`purchases_flutter` web/test linkage** → isolated behind `revenuecat_gateway.dart`;
  service + flags + UI never import it directly, keeping web build and `flutter test` clean.
- **Version resolution** of new packages on Flutter 3.44 → bump constraints per
  `flutter pub get`.
- **Anti-fake:** the only DSP contract change is the honest `min_bpm` knob; no fake BPM,
  no hidden half/double on the main screen, no `STABLE` without evidence.

## Done when
- `cargo test --workspace`, `flutter analyze` (0 errors), `flutter test` all green.
- FFI exposes `hitech_bpm_engine_new_with_min_bpm`; Free engine = 170–230, Pro = 155–230,
  switching on purchase without an app restart.
- Debug screen + export gated → paywall in Free; available in Pro. History capped 30s
  (Free) / unlimited (Pro) on a dedicated screen. Restore works. Widget shows "Скоро".
- `config.dart` gitignored, `config.dart.template` committed; Free works keyless/offline;
  no `debugPrint` of purchase data.
- `CHANGELOG.md [Unreleased]` + `README.md` (Free vs Pro + Monetization Setup) updated;
  `docs/plans/freemium-monetization.md` persisted; brief notes in `docs/ARCHITECTURE.md`
  (new `monetization`/`history`/`export` layers + FFI knob) and `docs/ROADMAP.md`.

## Out of scope / guardrails
- Lock-screen widget (WidgetKit) — next PR; stub only.
- Do **not** modify `.codex/` or `.agents/`.
- **Do not `git commit`/`git push` without explicit user confirmation.**

## Next patch
- Lock-screen widget: native Swift WidgetKit (iOS 16+) + Android App Widget, fed by a
  shared-storage bridge from the DSP result; gated by `flags.canAccessWidget`.
