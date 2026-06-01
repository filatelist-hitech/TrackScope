# Design System v2: 3 Sprints Implementation Plan

## 1. Task Classification

- **Complexity:** high
- **Domains:** mobile, ui, docs

---

## 2. Agents

| Agent | Why |
|---|---|
| `@mobileman` | Primary — all Flutter/Dart code: tokens, widgets, screens, navigation, persistence |
| `@archman` | Tab Bar is a structural architectural change — AppNavigator design before coding |
| `@reviewman` | Pre-merge gate: BPM anti-fake, no random values in History/Signal Analyzer |
| `@docman` | Update `docs/ARCHITECTURE.md` with new navigation structure |

---

## 3. Files to Inspect (done)

- `apps/mobile/lib/ui/design_tokens.dart` — existing AppTheme (JetBrains Mono, #07070F, #00E5CC)
- `apps/mobile/lib/ui/main_screen.dart` — 3-panel layout, no Tab Bar
- `apps/mobile/lib/capture/bpm_display.dart` — data class (EMA filter), NOT a widget
- `apps/mobile/lib/ui/debug_screen.dart` — raw debug screen → becomes Signal Analyzer
- `apps/mobile/lib/history/history_screen.dart` — existing, uses BpmSample model
- `apps/mobile/lib/main.dart` — single-screen navigator, owns CaptureBridge
- `apps/mobile/pubspec.yaml` — missing: `shared_preferences`, `wakelock_plus`
- `apps/mobile/design/CLAUDE_CODE_HANDOFF.md` — Swift/UIKit spec → must translate to Flutter/Dart
- `apps/mobile/design/BPM Radar Prototype.html` — visual source of truth

---

## 4. Current Behavior

- Single-screen app: `MainScreen` (waveform 35% + spectrum 22% + glassmorphism card 43%).
- BPM number is small, not hero-sized. Empty state shows white rectangle.
- Confidence bar is 2px single-color.
- No Tab Bar — History pushed via callback, no Settings screen.
- `DebugScreen` accessible via top-right icon (Pro gate).
- Design tokens: `AppTheme` in `lib/ui/design_tokens.dart` (JetBrains Mono, #00E5CC accent).
- No `shared_preferences`, no `wakelock_plus` in pubspec.
- `BpmDisplay` in `lib/capture/bpm_display.dart` is a **data class** (EMA), not a widget.

---

## 5. Target Behavior

- New design tokens: `lib/theme/app_colors.dart` + `lib/theme/app_text_styles.dart`.
  Font: IBM Plex Mono. Background: #050807. Accent: #00DFB0.
- **Sprint 1**: BPM hero 72px · BPM empty = "— — —" dim · Confidence 7px+colors ·
  Waveform 120px · Break button redesign · Listening indicator · Paywall redesign.
- **Sprint 2**: Tab Bar (Радар / История / Настройки) via `AppNavigator` with `IndexedStack`.
  `CaptureBridge` NOT recreated on tab switch — stays in `_CapturePipeline`.
- **Sprint 3**: Signal Analyzer screen (Pro, push from Radar) · History screen (Pro, tab) ·
  Settings screen (SharedPreferences-backed).

---

## 6. Data Contracts

### New: `lib/features/history/bpm_session.dart`
```dart
class BpmSession {
  final String id;
  final DateTime date;
  final double avgBpm;
  final double peakBpm;
  final Duration duration;
  final double avgConfidence;
  final List<double> bpmTimeline;
}
```

### New: `lib/settings/app_settings.dart`
```dart
class AppSettings extends ChangeNotifier {
  bool showWaveform = true;
  bool showSpectrum = true;
  bool keepScreenOn = true;
  double inputSensitivity = 0.0; // dB
}
```

### Navigation enum: `lib/navigation/app_navigator.dart`
```dart
enum AppTab { radar, history, settings }
```

### Widget name resolution
- Keep `lib/capture/bpm_display.dart` (data class, EMA) — unchanged.
- New hero widget: `lib/widgets/bpm_hero_display.dart` (`BpmHeroDisplay` widget).
- No name collision.

---

## 7. Implementation Steps

### Phase 0 — pubspec + theme files (no UI changes)
1. Add `shared_preferences: ^2.3.0` and `wakelock_plus: ^1.2.0` to `pubspec.yaml`.
2. Create `apps/mobile/lib/theme/app_colors.dart` (AppColors class).
3. Create `apps/mobile/lib/theme/app_text_styles.dart` (AppTextStyles class).
4. Run `flutter pub get`.

### Phase 1 — New widgets (Sprint 1)
5. Create `lib/widgets/bpm_hero_display.dart` (BpmHeroDisplay — replaces role of BPM number in card).
6. Create `lib/widgets/confidence_bar.dart` (ConfidenceBar — 7px + color thresholds).
7. Create `lib/widgets/break_button.dart` (BreakButton — icon + label).
8. Create `lib/widgets/listening_indicator.dart` (ListeningIndicator — animated dot).
9. Update `lib/ui/main_screen.dart`:
   - Replace BPM number rendering with `BpmHeroDisplay`.
   - Change waveform container height to 120.
   - Add ListeningIndicator.
   - Add BreakButton.
10. Update `lib/monetization/paywall_screen.dart`:
    - Add value headline.
    - Add column headers (Free / Pro).
    - Rename "Debug Screen" → "Signal Analyzer".
    - Replace duplicate widget row with Roadmap card.
    - Redesign CTA buttons (primary filled + "Best value" badge, secondary outline).

### Phase 2 — Tab Bar (Sprint 2)
11. Create `lib/navigation/app_navigator.dart` (AppNavigator, AppTab enum, IndexedStack).
12. Create `lib/widgets/app_tab_bar.dart` (AppTabBar widget — custom, not Material NavigationBar).
13. Create stub `lib/screens/settings_screen.dart` (Settings — full implementation in Phase 3).
14. Update `lib/main.dart`:
    - Replace `MainScreen(...)` with `AppNavigator(...)`.
    - Pass `CaptureBridge` streams + callbacks through AppNavigator props.

### Phase 3 — New screens (Sprint 3)
15. Create `lib/screens/signal_analyzer_screen.dart`:
    - Rename/extend `DebugScreen` content.
    - Add CandidatesList widget, AlgorithmMetrics placeholder.
    - Pro gate: if `!flags.canAccessDebugScreen` → show PaywallScreen.
16. Create `lib/features/history/bpm_session.dart` (BpmSession model).
17. Create `lib/features/history/history_service.dart` (HistoryService — SharedPreferences persistence).
18. Update `lib/history/history_screen.dart` with new BpmSession-based UI (groups: Today/Yesterday/Older, mini waveform).
19. Create `lib/settings/app_settings.dart` (AppSettings ChangeNotifier).
20. Implement `lib/screens/settings_screen.dart` (5 sections + WakelockPlus integration).
21. Update AppNavigator to wire up all three tab bodies.

### Phase 4 — Tests + docs
22. Add widget tests: `bpm_hero_display_test.dart`, `confidence_bar_test.dart`, `app_tab_bar_test.dart`.
23. Add screen tests: `signal_analyzer_screen_test.dart`, `history_screen_test.dart`, `settings_screen_test.dart`.
24. Run `flutter analyze`, `flutter test`, `cargo test --workspace`.
25. Update `docs/ARCHITECTURE.md` with new navigation structure.
26. Update `CHANGELOG.md` + `README.md`.

---

## 8. Tests Required

| Test file | Key cases |
|---|---|
| `test/widgets/bpm_hero_display_test.dart` | null→"— — —" dim, detecting→accent, unstable→amber+pill |
| `test/widgets/confidence_bar_test.dart` | 10%→red, 50%→yellow, 80%→teal |
| `test/widgets/app_tab_bar_test.dart` | 3 tabs rendered, active=accent, onChanged fires |
| `test/screens/signal_analyzer_screen_test.dart` | smoke+mock, no-Pro→Paywall, back works |
| `test/screens/history_screen_test.dart` | empty state, session displayed, grouping, no-Pro→Paywall |
| `test/screens/settings_screen_test.dart` | all sections, toggle→AppSettings, reset dialog |

Commands:
```sh
/opt/homebrew/opt/rust/bin/cargo test --workspace
cd apps/mobile && flutter analyze
cd apps/mobile && flutter test --reporter=expanded
```

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| `BpmDisplay` name collision (data class vs new widget) | New widget named `BpmHeroDisplay` in `lib/widgets/` |
| Existing `AppTheme` used in 10+ files → new `AppColors` must coexist | Keep old tokens; new widgets use AppColors; migrate incrementally |
| `CaptureBridge` recreated on tab switch | `IndexedStack` + `_CapturePipeline` stays above AppNavigator |
| No physical devices available | Use `flutter run -d chrome` + web preview at :7654 for visual verification |
| `wakelock_plus` platform channels → test failures | Wrap in interface; mock in tests |

---

## 10. Done When

- `flutter analyze` → 0 errors.
- `flutter test --reporter=expanded` → all PASS (≥ 60 tests total incl. ≥20 new).
- `cargo test --workspace` → no regression.
- Tab Bar renders 3 tabs; CaptureBridge stream continues on tab switch.
- BPM null → "— — —" dim #1E3530 (not white rectangle).
- Confidence bar 7px + red/yellow/teal.
- PaywallScreen has column headers + value headline + CTA hierarchy.
- Signal Analyzer shows real DspResult data (not random).
- History groups BpmSession by Today/Yesterday/Older; Pro-gated.
- Settings persists via SharedPreferences; Keep Screen On via WakelockPlus.
- `docs/ARCHITECTURE.md` updated.
- `CHANGELOG.md` and `README.md` updated.
- No hardcoded BPM values introduced.
