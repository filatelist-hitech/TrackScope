# Промпт: Design System V2 Visual Parity Audit

> Готовый к копированию промпт для Claude Code.
> Инфраструктура: агент @uiman, скиллы flutter-ui-audit / flutter-design-system / golden-testing / review-gate.

---

```
Before implementation:
1. Verify Flutter:  `flutter --version`
2. Verify Cargo:    `/opt/homebrew/opt/rust/bin/cargo --version`
3. Verify Node.js:  `/opt/homebrew/opt/nodejs/bin/node --version`
Abort if any required tool is unavailable.

Before doing the task:
1. Read @CLAUDE.md and @AGENTS.md.
2. Read @.claude/docs/project-map.md — current module map.
3. Inspect `.claude/agents/` and `.claude/skills/`.
4. Classify: HIGH complexity. Domains: ui, qa, docs.
   Reasons: full repository audit, visual parity migration, Flutter UI refactor,
   theme consolidation, widget-level updates, navigation validation,
   screenshot/golden testing, risk of UI regressions.
5. Run `/plan "Design System V2 Visual Parity Audit"` → save to `docs/plans/`.
6. DIAGNOSIS IS MANDATORY BEFORE ANY CODE CHANGES.
7. Delegate via @<name> as specified below.
8. Activate required skills explicitly.
9. Main invariant: visual parity must improve WITHOUT:
   - breaking architecture (CaptureBridge lifecycle, FFI contract, AppNavigator IndexedStack)
   - duplicating widgets / navigation / themes / screens
   - breaking Rust integration
   - breaking tests
10. Add or update tests alongside every change.
11. Return: changed files, tests run, limitations, next patch.

After doing the task:
1. Update `.claude/docs/project-map.md` → Flutter Layer: theme/, widgets/, viz/.
2. Update `docs/plans/design_system_v2.md` if implementation diverges.
3. Update `CHANGELOG.md` under `[Unreleased]`.
4. Confirmation required before git commit and git push.

---

# TASK
Perform a complete repository-wide Design System V2 audit and migration.

Goal: achieve maximum visual parity with
`apps/mobile/design/BPM Radar Prototype v2.html`
while preserving all existing architecture and business logic.
Modify existing code — do not create parallel implementations.

# CONTEXT
Source of truth:
1. Visual design:            `apps/mobile/design/BPM Radar Prototype v2.html`
2. Architecture constraints: `docs/plans/design_system_v2.md`
3. Module map:               `.claude/docs/project-map.md`

Repository already contains partial implementation.
DO NOT assume anything is missing. Audit first. Implementation second.

# DESIGN SPECIFICATION
Values extracted from `apps/mobile/design/BPM Radar Prototype v2.html`.
Treat as canonical.

## TYPOGRAPHY
Primary Font: IBM Plex Mono — Weights: 300, 400, 500, 600

## COLORS
Background: #050807     Root Background: #07090A
Secondary BG: #040705   Card Background: #0C1410
Surface BG: #0D1712     Track BG: #111916
Divider: #080C09        Primary Accent: #00DFB0
Warning Accent: #FFE090 Premium: #E0822A
Recording: #E04040      Primary Text: #C8DCD8
Secondary Text: #7AB8AA Medium Text: #5A8878
Muted Text: #3A6858     Disabled: #1E3530
Deep Disabled: #1A3028  Border: #1A2D24

## SPACING
Base Scale: 4,5,6,7,8,9,10,11,12,13,14,16,18,20,22,24,26
Screen Padding: 22 / Card Padding: 24 / Group Padding: 16

## BORDER RADII
MainCard: 22 / Surface: 13 / CTA: 16 / Button: 7–9 / Pill: 20 / Badge: 5–16

## BPM HERO
72px w600 lh:1.0 ls:-0.04em
Active: #00DFB0 / Unstable: #FFE090 / Empty: #1E3530 / Placeholder: — — —

## SECTION LABELS
9px w500 uppercase ls:0.14–0.20em

## CONFIDENCE BAR
h:8 r:4 bg:#111916 animate:width 400ms
Low=Red / Medium=Yellow / High=Teal

## TOGGLES
34×20, Thumb 16×16, ON:#00DFB0, OFF:#1E3530, transition:200ms

## PILLS
9px p:4×12 r:20
Teal: bg rgba(0,223,176,.10) border rgba(0,223,176,.30) text #00DFB0
Amber: bg rgba(200,138,24,.18) border rgba(200,138,24,.30) text #FFE090

## BUTTONS
Nav: 36×36 bg:#0D1712 r:9 pressed:#1A2D24 opacity:0.8
Primary CTA: bg:#00DFB0 text:#000000 r:16 w:600
Secondary CTA: transparent border:#1E3530 r:16

## ANIMATIONS
Screen transition: transform+opacity 300ms cubic-bezier(.4,0,.2,1)
Interaction: 150ms / Toggle: 200ms / Blink REC: 1.2s infinite
PageRouteBuilder curve: Curves.easeInOutCubic 300ms
InkWell splashColor transparent, bg change 150ms
AnimationController repeat opacity 1→0.2 over 1.2s

## WAVEFORM
h:120 primary:#00DFB0 secondary:#C8A020 gradient stops: 100%,66%,20%

## TAB BAR
topBorder:#0F1712 bg:#050807 padding:14 0 20
Tab: vertical gap:6 label:9px w500 uppercase ls:0.1em

## SHADOWS
Phone Shell: 0 0 0 6px #030504, 0 40px 100px rgba(0,0,0,.9)

## LAYOUT ORDER
StatusBar → Navigation → ZoneLabel → Waveform → FrequencyAxis → MainCard → TabBar

## MIGRATION RULE
If existing implementation differs: document mismatch → update implementation
→ update tests → verify visual parity.
Use existing widgets. Do not create replacement implementations.

---

# DIAGNOSIS PHASE (MANDATORY — no code before this)

Activate: `/flutter-ui-audit`

@uiman performs repository-wide diagnostics:

Metric 1: design_parity_score — % match between current UI and prototype
Metric 2: token_consistency_score — % visual values using centralized tokens
Metric 3: hardcoded_visual_values — count of Color(), TextStyle(), BorderRadius(),
          EdgeInsets(), Duration(), BoxShadow() outside design system
Metric 4: visual_mismatch_inventory — every mismatch: typography, spacing, colors,
          cards, waveform, confidence bar, BPM hero, tab bar, navigation, settings, history
Metric 5: duplicate_ui_components — duplicated widgets, themes, design tokens

Save findings to `docs/plans/ui-audit-<DATE>.md`. No implementation until report is complete.

---

# SUBAGENTS

Delegate and wait for results before proceeding.

@uiman (PRIMARY):
- Full UI audit using `/flutter-ui-audit`
- Prototype comparison → mismatch inventory
- Migration using `/flutter-design-system`
- Theme normalization (app_colors.dart + app_text_styles.dart)
- Visual parity verification
- After each theme file change: update `.claude/docs/project-map.md` Flutter Layer section

@qaman:
- Widget test coverage: BpmHeroDisplay, ConfidenceBar, AppTabBar, InfoCard
- Screen test coverage: SignalAnalyzerScreen, HistoryScreen, SettingsScreen
- Golden tests using `/golden-testing`:
  bpm_hero_stable/unstable/empty, confidence_bar_low/mid/high,
  tab_bar_*.png, signal_analyzer.png, history_*.png, settings.png
- Regression validation: confirm existing 148+ tests still pass

@perfman:
- Ensure migration does not introduce unnecessary rebuilds
- Verify no excessive widget tree depth from theme wrapping
- Check CustomPainter shouldRepaint() correctness after color changes
- No performance regressions from visual refactors

@reviewman (FINAL GATE):
- No duplicated architecture / widgets / themes / dead code
- Visual parity improved vs pre-migration baseline
- All tests updated and passing
- Documentation updated
- anti-fake invariants intact (UI never computes BPM)

---

# SKILLS

Activate explicitly:
- `/flutter-ui-audit`     — diagnosis phase
- `/flutter-design-system` — migration phase
- `/golden-testing`        — visual regression tests
- `/review-gate`           — pre-merge validation

---

# AUDIT REQUIREMENTS

Inspect:
- `apps/mobile/lib/**`
- `apps/mobile/test/**`
- `apps/mobile/design/**`
- `docs/**`
- `pubspec.yaml`

Build repository map:
navigation / screens / widgets / theme / tokens /
BPM rendering / waveform rendering / confidence rendering / tests

Generate parity table:
| Prototype Element | Existing File | Status (Match/Partial/Missing) |
|---|---|---|
| BPM Hero | | |
| Confidence Bar | | |
| Waveform | | |
| Tab Bar | | |
| Navigation | | |
| Settings | | |
| History | | |
| Theme Tokens | | |
| Cards | | |
| Animations | | |

---

# DESIGN TOKEN AUDIT

Find all hardcoded:
Color(...) / TextStyle(...) / FontWeight(...) / FontSize(...)
BorderRadius(...) / EdgeInsets(...) / Duration(...) / Opacity(...)
Gradient(...) / BoxShadow(...)

Generate report: file, line, current value, expected token, severity.
Do not modify before report generation.

---

# VISUAL PARITY REQUIREMENTS

Audit and update:
typography, spacing, colors, opacity, gradients, borders, shadows, radii,
icon sizes, icon alignment, animations, transitions,
waveform rendering, confidence bar, BPM hero, cards,
tab bar, navigation, settings rows, history rows, badges, pills, toggles.

Do not approximate. Use values from prototype.
Do not use Material defaults when prototype values exist.

---

# COMPONENT REQUIREMENTS

## BPM Hero
Verify: fontFamily=IBMPlexMono, fontSize=72, fontWeight=w600,
letterSpacing=-0.04em, lineHeight=1.0,
active=#00DFB0, unstable=#FFE090, empty=#1E3530, placeholder="— — —",
alignment, animation on state change.

## Confidence Bar
Verify: height=8, borderRadius=4, background=#111916,
low=red, medium=yellow, high=teal, animated width 400ms.

## Waveform
Verify: height≈120, primaryColor=#00DFB0, ambient glow always-on,
beat-reactive pulse, red on clipping.
Do not rewrite waveform engine. Prefer visual adjustments.

## Tab Bar
Verify: topBorder=#0F1712, bg=#050807, label=9px w500 uppercase ls:0.1em,
safe area, icon size, active/inactive states. Must match prototype.

## Cards
Verify: radius=22 (main) / 13 (surface), padding=24, border=#1A2D24,
spacing, background colors. Must match prototype.

---

# THEME MIGRATION

Replace hardcoded visual values with centralized tokens.
Goals: single source of truth, no duplicated colors / spacing / text styles / radii.
`design_tokens.dart` stays as thin proxy → AppColors/AppTextStyles.

---

# IMPLEMENTATION RULES

- Modify existing code only. Prefer refactoring over creation.
- NEVER create duplicate widgets, screens, themes, navigation, state management.
- If equivalent widget exists: MODIFY IT.
- One concern per Edit call — do not batch unrelated changes.

---

# ARCHITECTURE CONSTRAINTS (must not break)

- CaptureBridge lifecycle and broadcast streams
- Rust FFI contract (DspResult JSON, 6 C symbols)
- AppNavigator IndexedStack structure
- `has_ever_been_stable`, adaptive window, tempo jump logic in Rust
- Existing state management (ChangeNotifier / ListenableBuilder)
- Repository layout

---

# TEST REQUIREMENTS

Update existing tests first. Create new tests only if required.

Widget tests: BpmHeroDisplay, ConfidenceBar, AppTabBar
Screen tests: SignalAnalyzerScreen, HistoryScreen, SettingsScreen
State tests: loading, empty, navigation, settings persistence

Golden tests (via `/golden-testing`):
SignalAnalyzerScreen, HistoryScreen, SettingsScreen,
BpmHeroDisplay (3 states), ConfidenceBar (3 states), AppTabBar (3 active tabs).

---

# VALIDATION

Run in order — fix before continuing to next:
```sh
flutter analyze        # zero errors required
flutter test           # all tests pass
/opt/homebrew/opt/rust/bin/cargo test --workspace  # must stay green
```

---

# ACCEPTANCE CRITERIA

Done when ALL are true:
- [ ] repository audit completed + `docs/plans/ui-audit-<DATE>.md` saved
- [ ] design_parity_score > baseline (measured before vs after)
- [ ] token_consistency_score > baseline
- [ ] hardcoded_visual_values count reduced
- [ ] no duplicated UI systems introduced
- [ ] BPM Hero matches prototype (72px w600 -0.04em active/unstable/empty)
- [ ] ConfidenceBar matches prototype (h=8 r=4 400ms)
- [ ] Tab Bar matches prototype
- [ ] flutter analyze → 0 errors
- [ ] flutter test → all pass (≥148)
- [ ] cargo test --workspace → all pass
- [ ] golden tests created and green
- [ ] `.claude/docs/project-map.md` updated
- [ ] `CHANGELOG.md` entry added

---

# FINAL RESPONSE FORMAT

1. Summary
2. Repository audit table (Prototype Element / File / Status)
3. Design token audit (hardcoded count before → after)
4. Visual mismatch report (what changed)
5. Files modified
6. Files created / deleted
7. Visual parity fixes (before/after values)
8. Widget test results
9. Screen test results
10. Golden test results
11. `flutter analyze` result
12. `flutter test` result
13. `cargo test` result
14. Known limitations
15. Next patch
16. PR status
```
