# Execution Plan: Phase 2.6 — Share Set Energy Card

## 1. Task classification

- **complexity:** medium
- **domains:** mobile, ui

---

## 2. Agents

- **mobileman** — setlist_screen.dart wiring, CaptureBridge untouched, share_plus/path_provider I/O
- **uiman** — SetEnergyCardPainter (CustomPainter), AppColors token usage, 1080×1080 layout

No DSP/FFI/QA agents needed: data flows entirely from already-populated `SetlistEntry` fields; Rust DSP untouched.

---

## 3. Files to inspect

Already inspected:
- `apps/mobile/lib/features/setlist/setlist_entry.dart` — fields: bpm, camelotKey, energyLevel, timestamp ✓
- `apps/mobile/lib/features/setlist/setlist_service.dart` — entries, exportJson/exportCsv ✓
- `apps/mobile/lib/features/setlist/setlist_screen.dart` — actions list, _ExportButton pattern ✓
- `apps/mobile/lib/monetization/feature_flags.dart` — canExport/canAccessSetlist pattern ✓
- `apps/mobile/lib/theme/app_colors.dart` — accent/danger/warning/textMuted tokens ✓
- `apps/mobile/test/features/setlist/setlist_screen_test.dart` — test structure ✓

New files to create:
- `apps/mobile/lib/features/share_card/set_energy_card_painter.dart`
- `apps/mobile/lib/features/share_card/set_energy_card.dart`
- `apps/mobile/test/features/share_card/set_energy_card_test.dart`

---

## 4. Current behavior

- `SetlistService.entries` → `List<SetlistEntry>` with bpm, camelotKey, energyLevel, timestamp — populated from Phase 2.4.
- `SetlistScreen._SetlistView.build()` shows export actions (CSV, JSON) in AppBar when `entries.isNotEmpty`.
- `FeatureFlags` has `canExport`, `canAccessSetlist` — no `canShareCard`.
- No share-card feature exists.

---

## 5. Target behavior

- `FeatureFlags.canShareCard` — Pro-gated (`bool get canShareCard => isPro`).
- When Pro + `entries.isNotEmpty`: share-card icon button appears in SetlistScreen AppBar.
- Tapping button renders `SetEnergyCardPainter` off-screen in a `RepaintBoundary`, captures via `toImage()`, writes PNG to temp dir, calls `Share.shareXFiles([XFile(path)])`.
- When Free + `entries.isNotEmpty`: button still visible but tapping navigates to `PaywallScreen(feature: 'share_card')`.
- `SetEnergyCardPainter` (1080×1080 px canvas):
  - **BPM curve** — polyline: x = normalized time [0..1], y = BPM in [minBpm..maxBpm] range clamped [140..240].
  - **Camelot pills** — small rounded-rect text label at x-position of each key-change point.
  - **Energy arc** — polar arc of 10 equal segments, each coloured by energy level (danger ≤3, warning 4–7, accent ≥8); drawn around center of lower half.
  - **Watermark** — "TrackScope" muted text, bottom-right.
  - Background: `AppColors.background` (#050807).

---

## 6. Data contracts

No changes to:
- `SetlistEntry` (Dart)
- `DspResult` / FFI / Rust DSP

Changes:
- `FeatureFlags` — add `bool get canShareCard => isPro`
- New widget contract:
  ```dart
  SetEnergyCardPainter(List<SetlistEntry> entries) extends CustomPainter
  SetEnergyCard({required List<SetlistEntry> entries, required VoidCallback onDone})
  ```

---

## 7. Implementation steps

### Step 1 — `feature_flags.dart`: add `canShareCard`
```dart
bool get canShareCard => isPro;
```
Test: unit assert `FeatureFlags(isPro: true).canShareCard == true`, `FeatureFlags(isPro: false).canShareCard == false`.

### Step 2 — `set_energy_card_painter.dart`
- `class SetEnergyCardPainter extends CustomPainter`
- Constructor: `const SetEnergyCardPainter(this.entries)`; field `final List<SetlistEntry> entries`
- `paint(canvas, size)` guard: if `entries.isEmpty` — fill bg only, return.
- `_drawBpmCurve(canvas, size)`: compute time range, BPM range [140..240]. Draw grid lines (muted). Draw polyline (accent color).
- `_drawCamelotPills(canvas, size, ...)`: iterate entries, detect key change (prev != current camelotKey), draw rounded-rect pill with key text at x-position.
- `_drawEnergyArc(canvas, size)`: if any entry has energyLevel != null, compute avg energy level, draw polar arc of 10 equal wedge segments (sweep 36° each), color by level range.
- `_drawWatermark(canvas, size)`: "TrackScope" text bottom-right, textMuted color.
- `shouldRepaint(old) => old.entries != entries`

### Step 3 — `set_energy_card.dart`
- `class SetEnergyCard extends StatefulWidget`
- `_SetEnergyCardState` owns `GlobalKey _boundaryKey = GlobalKey()`
- `build()`: `RepaintBoundary(key: _boundaryKey, child: CustomPaint(painter: SetEnergyCardPainter(entries), size: const Size(1080, 1080)))`
- `captureAndShare()` async: `RenderRepaintBoundary` → `toImage(pixelRatio: 1.0)` → `pngBytes` → `getTemporaryDirectory()` → write file → `Share.shareXFiles([XFile(path)])`
- Public API: expose `captureAndShare()` via controller pattern or via `GlobalKey<_SetEnergyCardState>`.

### Step 4 — `setlist_screen.dart`: add share button
- Add `flags` parameter to `_SetlistView` (already passed to `SetlistScreen`).
- In `actions`: add `_ShareCardButton` when `service.entries.isNotEmpty`:
  - If `flags.canShareCard`: triggers off-screen render + share.
  - Else: navigates to `PaywallScreen(feature: 'share_card')`.
- Off-screen render: use `Offstage` widget with `SetEnergyCard` and `GlobalKey`, capture on button tap.

### Step 5 — Tests (`set_energy_card_test.dart`)
See section 8.

### Step 6 — Update `project-map.md`
Add `share_card/` entry.

---

## 8. Tests

New file: `apps/mobile/test/features/share_card/set_energy_card_test.dart`

| Test | Type | Assertion |
|---|---|---|
| `canShareCard Pro → true` | unit | `FeatureFlags(isPro: true).canShareCard == true` |
| `canShareCard Free → false` | unit | `FeatureFlags(isPro: false).canShareCard == false` |
| `painter renders empty list without throw` | unit (paint smoke) | `SetEnergyCardPainter([]).paint(...)` doesn't throw |
| `painter renders single entry without throw` | unit (paint smoke) | single entry, no exception |
| `painter renders multiple entries without throw` | unit (paint smoke) | 5 entries, no exception |
| `painter BPM curve uses data not hardcode` | unit | painter.entries[0].bpm is entry value, not constant |

Widget tests in `setlist_screen_test.dart` (additions):

| Test | Assertion |
|---|---|
| `share button visible when Pro + entries` | `find.byIcon(Icons.share_outlined)` finds 1 |
| `share button absent when entries empty` | finds nothing |
| `share button shows paywall for Free tier` | tap → `PaywallScreen` in tree |

Commands:
```sh
flutter test
flutter analyze
```

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| `toImage()` only works in real render tree (not in unit tests) | Paint smoke tests call `CustomPainter.paint()` directly with `PictureRecorder` canvas |
| Division by zero when `entries.length == 1` (no time range) | Guard: if single entry, draw dot at center; skip polyline |
| Division by zero if all entries have same BPM | Guard: if bpmRange == 0, use ±5 BPM window |
| `path_provider` needed for temp file | Already in pubspec via setlist_screen.dart's `getTemporaryDirectory()` |
| `SetlistScreen` doesn't currently pass `flags` to `_SetlistView` | Add `flags` parameter in step 4; minimal refactor |

---

## 10. Done when

- [ ] `flutter analyze` → 0 errors
- [ ] `flutter test` → all green (was 203 + 1 pre-existing = 204 total; new tests → 213+)
- [ ] `FeatureFlags.canShareCard` Pro-gated ✓
- [ ] Share button appears in SetlistScreen only when `isPro && entries.isNotEmpty` ✓
- [ ] Free tier tap → PaywallScreen ✓
- [ ] No hardcoded BPM values in painter ✓
- [ ] Anti-fake: data sourced exclusively from `SetlistEntry.bpm` (real DSP output) ✓
- [ ] `project-map.md` updated ✓
- [ ] `docs/ROADMAP.md` Phase 2.6 section added ✓

---

*Anti-fake note: `SetEnergyCardPainter` reads `entry.bpm` from the real DSP output stored in `SetlistEntry`. No demo values, no hardcoded BPM, no timer-based fake pulse. The painter is a pure renderer — it computes layout from data, not the reverse.*
