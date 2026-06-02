#!/usr/bin/env bash
# PostToolUse hook — targeted docs-update reminders after file edits
#
# Reads CLAUDE_TOOL_INPUT_FILE_PATH from environment.
# Outputs JSON additionalContext only when the changed file has known doc dependencies.
# Silent (exit 0, no output) when no docs need updating — avoids noise.

f="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"
[ -z "$f" ] && exit 0

# Normalise to relative-style for matching (strip any leading path prefix)
rel="${f#*hitech-bpm-radar/}"

DOCS=""
REASON=""

add() { DOCS="${DOCS}${DOCS:+, }$1"; REASON="${REASON}${REASON:+; }$2"; }

# ── DSP algorithm core ────────────────────────────────────────────────────────
case "$rel" in
  core/dsp/src/lib.rs)
    add "docs/DSP_ALGORITHM.md"    "DspEngine / algorithm constants may have changed"
    add "docs/QA_MATRIX.md"        "acceptance criteria or fixture inventory may need a row"
    add ".claude/docs/project-map.md" "Rust DSP Layer section (constants, key functions)"
    ;;
  core/dsp/src/bin/*)
    add "docs/DSP_ALGORITHM.md"    "offline binary / CLI interface may have changed"
    ;;
  core/dsp/src/energy_analyzer.rs|core/dsp/src/genre_preset.rs|core/dsp/src/key_analyzer.rs)
    add "docs/DSP_ALGORITHM.md"    "DSP sub-module changed — pipeline description may be stale"
    add ".claude/docs/project-map.md" "Rust DSP Layer: file list or responsibilities"
    ;;
  core/dsp/tests/*)
    add "docs/QA_MATRIX.md"        "Rust fixture inventory section may need updating"
    ;;
esac

# ── FFI boundary ─────────────────────────────────────────────────────────────
case "$rel" in
  core/ffi/src/*|core/ffi/include/*)
    add "docs/ARCHITECTURE.md"     "FFI boundary section (exported symbols / ABI)"
    add "docs/DSP_ALGORITHM.md"    "FFI boundary sub-section"
    add ".claude/docs/project-map.md" "FFI Layer section (exported C symbols)"
    ;;
esac

# ── Flutter DSP / capture layer ───────────────────────────────────────────────
case "$rel" in
  apps/mobile/lib/dsp/*)
    add "docs/ARCHITECTURE.md"     "Flutter DSP layer description (bindings / engine)"
    add ".claude/docs/project-map.md" "Flutter Layer: lib/dsp/"
    ;;
  apps/mobile/lib/capture/capture_bridge.dart|apps/mobile/lib/capture/dsp_worker.dart)
    add "docs/ARCHITECTURE.md"     "capture pipeline description (CaptureBridge / isolate)"
    add "docs/MOBILE_AUDIO.md"     "latency / isolate architecture notes"
    add ".claude/docs/project-map.md" "Flutter Layer: lib/capture/"
    ;;
  apps/mobile/lib/capture/bpm_smoother.dart|apps/mobile/lib/capture/bpm_display.dart)
    add "docs/DSP_ALGORITHM.md"    "Dart smoothing layer section (BpmSmoother / BpmDisplay)"
    ;;
esac

# ── Navigation / screens (public UI surface) ──────────────────────────────────
case "$rel" in
  apps/mobile/lib/navigation/*)
    add "docs/ARCHITECTURE.md"     "navigation structure / tab layout"
    add ".claude/docs/project-map.md" "Flutter Layer: lib/navigation/ + nav diagram"
    ;;
  apps/mobile/lib/screens/*)
    add "docs/ROADMAP.md"          "phase completion status or screen-level feature description"
    add ".claude/docs/project-map.md" "Flutter Layer: lib/screens/"
    ;;
  apps/mobile/lib/monetization/*)
    add "docs/ROADMAP.md"          "Phase 10 / monetization status or feature flags"
    add ".claude/docs/project-map.md" "Flutter Layer: lib/monetization/"
    ;;
esac

# ── Build system ──────────────────────────────────────────────────────────────
case "$rel" in
  scripts/build_ios_native.sh)
    add "docs/RELEASE_CHECKLIST.md" "iOS build step or artifact path changed"
    add "docs/MOBILE_AUDIO.md"      "iOS build / link notes"
    add "README.md"                 "iOS build instructions"
    add ".claude/docs/project-map.md" "Build System: iOS section"
    ;;
  scripts/build_android_native.sh)
    add "docs/RELEASE_CHECKLIST.md" "Android build step, targets, or artifact path changed"
    add "docs/ANDROID_TEST_PLAN.md" "build command or ABI list changed"
    add "README.md"                 "Android build instructions"
    add ".claude/docs/project-map.md" "Build System: Android section"
    ;;
  scripts/release.sh)
    add "docs/RELEASE_CHECKLIST.md" "release script changed"
    add "README.md"                 "release instructions"
    ;;
  apps/mobile/pubspec.yaml)
    add "README.md"                 "Flutter dependency list or version constraints"
    add ".claude/docs/project-map.md" "Flutter Layer: pubspec.yaml deps note"
    ;;
  core/dsp/Cargo.toml|Cargo.toml)
    add "README.md"                 "Rust dependency or toolchain requirement changed"
    ;;
  apps/mobile/android/app/build.gradle.kts|apps/mobile/android/settings.gradle*)
    add "docs/RELEASE_CHECKLIST.md" "Android Gradle config changed"
    add ".claude/docs/project-map.md" "Build System: Android section"
    ;;
  apps/mobile/ios/Podfile)
    add "docs/RELEASE_CHECKLIST.md" "iOS Podfile changed — run pod install"
    add ".claude/docs/project-map.md" "Build System: iOS section"
    ;;
esac

# ── Python tests / offline-lab ────────────────────────────────────────────────
case "$rel" in
  core/tests/*)
    add "docs/QA_MATRIX.md"        "Python test inventory or acceptance criteria"
    ;;
  tools/offline-lab/offline_lab.py|tools/offline-lab/parity.py)
    add "docs/QA_MATRIX.md"        "offline-lab report format or parity logic changed"
    ;;
  datasets/fixture_manifest.json)
    add "docs/QA_MATRIX.md"        "fixture manifest changed — snapshot inventory may be stale"
    ;;
esac

# ── Design system / theme ────────────────────────────────────────────────────
case "$rel" in
  apps/mobile/lib/theme/app_colors.dart)
    add "apps/mobile/design/BPM Radar Prototype v2.html" "verify all new tokens match prototype values"
    add "docs/ARCHITECTURE.md"     "Design System V2 tokens section"
    add ".claude/docs/project-map.md" "Flutter Layer: lib/theme/"
    ;;
  apps/mobile/lib/theme/app_text_styles.dart)
    add "apps/mobile/design/BPM Radar Prototype v2.html" "verify typography roles match prototype spec"
    add ".claude/docs/project-map.md" "Flutter Layer: lib/theme/"
    ;;
  apps/mobile/lib/theme/design_tokens.dart)
    add "apps/mobile/lib/theme/app_colors.dart" "design_tokens is proxy — verify it delegates to AppColors"
    add "docs/ARCHITECTURE.md"     "legacy Design System reference"
    ;;
esac

# ── Widgets (visual components) ───────────────────────────────────────────────
case "$rel" in
  apps/mobile/lib/widgets/bpm_hero_display.dart)
    add "apps/mobile/design/BPM Radar Prototype v2.html" "verify BPM Hero: 72px w600 ls:-0.04 active=#00DFB0 unstable=#FFE090 empty=#1E3530"
    add "docs/ROADMAP.md"          "Phase 11/12 BPM Hero spec"
    ;;
  apps/mobile/lib/widgets/confidence_bar.dart)
    add "apps/mobile/design/BPM Radar Prototype v2.html" "verify ConfidenceBar: h=8 r=4 400ms low/mid/high"
    ;;
  apps/mobile/lib/widgets/app_tab_bar.dart)
    add "apps/mobile/design/BPM Radar Prototype v2.html" "verify Tab Bar: border=#0F1712 bg=#050807 9px w500 uppercase"
    add ".claude/docs/project-map.md" "Flutter Layer: lib/widgets/app_tab_bar"
    ;;
esac

# ── Viz / painters ────────────────────────────────────────────────────────────
case "$rel" in
  apps/mobile/lib/viz/waveform_painter.dart)
    add "apps/mobile/design/BPM Radar Prototype v2.html" "verify Waveform: h=120 primary=#00DFB0 ambient glow + beat-reactive"
    add "docs/ROADMAP.md"          "Phase 5/12 waveform spec"
    ;;
  apps/mobile/lib/viz/live_spectrum_painter.dart)
    add "apps/mobile/design/BPM Radar Prototype v2.html" "verify Spectrum painter colors / gradient"
    add "docs/ROADMAP.md"          "Phase 7/12 spectrum spec"
    ;;
  apps/mobile/lib/viz/viz_controller.dart)
    add ".claude/docs/project-map.md" "Flutter Layer: lib/viz/viz_controller responsibilities"
    ;;
esac

# ── Design prototype (source of truth changed) ────────────────────────────────
case "$rel" in
  apps/mobile/design/*)
    add ".claude/docs/project-map.md" "design source of truth changed — update canonical values reference"
    add "apps/mobile/lib/theme/app_colors.dart" "re-audit tokens against updated prototype"
    add "apps/mobile/lib/theme/app_text_styles.dart" "re-audit typography against updated prototype"
    add "docs/plans/design_system_v2.md" "update design spec if values changed"
    ;;
esac

# ── Roadmap / phase completion ────────────────────────────────────────────────
# If someone edits ROADMAP directly — check ARCHITECTURE for consistency
case "$rel" in
  docs/ROADMAP.md)
    add "docs/ARCHITECTURE.md"     "verify architecture section matches new roadmap phase"
    ;;
  docs/DSP_ALGORITHM.md)
    add "docs/ROADMAP.md"          "check if phase exit criteria need updating"
    ;;
esac

[ -z "$DOCS" ] && exit 0

MSG="DOCS UPDATE CHECK after editing ${rel##*/}: consider updating — ${DOCS}. Reasons: ${REASON}. Update only if content actually changed; skip if already accurate."

# Escape for JSON
MSG_ESC="$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n' | sed 's/\\n$//')"

printf '{"hookSpecificOutput":{"additionalContext":"%s"}}' "$MSG_ESC"
