#!/usr/bin/env bash
# SessionStart hook — outputs project context for Claude

REPO_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel 2>/dev/null || echo "unknown")"

BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
MODIFIED="$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

FLUTTER_VER="$(flutter --version 2>/dev/null | head -1 || echo "flutter not in PATH")"
RUST_VER="$(/opt/homebrew/opt/rust/bin/cargo --version 2>/dev/null || echo "cargo not found")"

WATCHED_CHANGED=""
for f in pubspec.yaml Cargo.toml Cargo.lock apps/mobile/android/app/build.gradle.kts apps/mobile/android/settings.gradle apps/mobile/ios/Podfile; do
  if git -C "$REPO_ROOT" diff --name-only HEAD 2>/dev/null | grep -q "$f"; then
    WATCHED_CHANGED="$WATCHED_CHANGED $f"
  fi
done

CONTEXT="Branch: $BRANCH | Modified files: $MODIFIED"
[ -n "$FLUTTER_VER" ] && CONTEXT="$CONTEXT | $FLUTTER_VER"
[ -n "$RUST_VER" ] && CONTEXT="$CONTEXT | $RUST_VER"
[ -n "$WATCHED_CHANGED" ] && CONTEXT="$CONTEXT | CHANGED:$WATCHED_CHANGED"

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' \
  "$(echo "$CONTEXT" | sed 's/"/\\"/g')"
