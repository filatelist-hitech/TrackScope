---
name: project-phase-13-android-insets
description: Phase 13 — Android system navigation bar insets fix for RuStore submission (2026-06-03)
metadata:
  type: project
---

Phase 13 fixes RuStore rejection (version 1.1.0+2): system navigation buttons overlapped the app tab bar on Android.

**Root cause:** `AppTabBar` had hardcoded `padding: EdgeInsets.fromLTRB(0, 14, 0, 20)` without `MediaQuery.paddingOf(context).bottom`. On Flutter 3.44 with Android edge-to-edge, the system nav bar overlapped the tab icons/labels.

**Fix:** 3 files changed, version bumped.
- `apps/mobile/lib/widgets/app_tab_bar.dart:32` — `20 + MediaQuery.paddingOf(context).bottom`
- `apps/mobile/lib/screens/signal_analyzer_screen.dart:126` — ListView bottom padding added
- `apps/mobile/lib/features/setlist/setlist_screen.dart:233` — ListView bottom padding added
- `apps/mobile/pubspec.yaml` — version `1.1.0+3` → `1.1.1+4`

**Why:** Flutter 3.44 uses edge-to-edge by default on Android. Custom `bottomNavigationBar` widgets must handle `MediaQuery.paddingOf(context).bottom` themselves — Flutter Scaffold does NOT auto-add it inside the widget.

**How to apply:** Any future custom bottom bar widget in this project must include `MediaQuery.paddingOf(context).bottom` in its bottom padding. All pushed screens (no bottomNavigationBar) need SafeArea or explicit bottom inset in their scrollable content.

**Status:** DONE. flutter analyze → 0 errors, flutter test → 218/218 (1 pre-existing dsp_engine_test).
