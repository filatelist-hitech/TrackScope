# Execution Plan: Pre-release v1.0.0

## 1. Task classification

- **complexity**: high
- **domains**: dsp, mobile, ui, qa, docs

## 2. Agents

- `@dspman` — Group 1 (clippy fixes) + Group 3 (DSP tests)
- `@mobileman` — Group 2 (platform setup: version, labels, signing, icons)
- `@qaman` — Group 3 (test coverage) + Group 4 (known-fail tracking)
- `@docman` — Group 5 (documentation updates)
- `@reviewman` — final gate after all groups

## 3. Files to inspect

**Group 1 (clippy):**
- `core/dsp/src/lib.rs` — lines 403, 1132-1134, 1404
- `apps/mobile/ios/Runner/Info.plist` — CFBundleDisplayName

**Group 2 (platform):**
- `apps/mobile/pubspec.yaml` — version bump
- `apps/mobile/android/app/src/main/AndroidManifest.xml` — label
- `apps/mobile/android/app/build.gradle.kts` — signing config
- `apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/` — icons audit
- `apps/mobile/android/app/src/main/res/mipmap-*/` — icons audit

**Group 3 (tests):**
- `core/dsp/tests/streaming.rs` — add 170/220 BPM timing tests
- `core/dsp/tests/stability.rs` — add 170 BPM streak test
- `core/ffi/tests/` — add half/double/clipping tests

**Group 4 (known-fail):**
- `datasets/fixture_manifest.json` — mark hitech_real_10
- `tools/offline-lab/parity.py` — handle known_fail

**Group 5 (docs):**
- `README.md` — current status section
- `docs/RELEASE_CHECKLIST.md` — update statuses
- `docs/MOBILE_AUDIO.md` — latency table
- `CHANGELOG.md` — finalize v1.0.0 entry

## 4. Current behavior

**Clippy:** 3 warnings in `core/dsp/src/lib.rs`
**Version:** 0.1.0+1
**Android label:** hardcoded "mobile" in AndroidManifest.xml
**Android signing:** no release config
**Icons:** unknown (need audit)
**Tests:** streaming timing only for 200 BPM, streak only for 180/195/200/220, FFI only 3 tests
**Known-fail:** hitech_real_10 fails parity, no tracking mechanism
**Docs:** README outdated, CHANGELOG has [Unreleased]

## 5. Target behavior

**Clippy:** 0 warnings with `-D warnings`
**Version:** 1.0.0+1
**Android label:** "TrackScope" from strings.xml
**Android signing:** release config with key.properties template
**Icons:** documented (custom or placeholder replaced)
**Tests:** 170/200/220 timing, 170/180/195/200/220 streak, 6+ FFI tests, breakdown-exit test
**Known-fail:** hitech_real_10 tracked, parity.py exits 0
**Docs:** README v1.0.0 status, CHANGELOG finalized, RELEASE_CHECKLIST current

## 6. Data contracts

**No breaking changes** — all public APIs remain stable:
- `DspResult` contract unchanged
- FFI boundary unchanged
- Flutter `DspResult` Dart model unchanged

## 7. Implementation steps

### Group 1 — Trivial code fixes (@dspman)
1. Fix clippy line 403 — replace `is_none()` check with `?`
2. Fix clippy lines 1132-1134 — merge identical if-blocks
3. Fix clippy line 1404 — remove redundant closure
4. Fix iOS CFBundleDisplayName → "TrackScope"
5. Verify: `cargo clippy --workspace -- -D warnings` → 0 errors

### Group 2 — Platform setup (@mobileman)
1. Bump `pubspec.yaml` version to 1.0.0+1
2. Create `android/app/src/main/res/values/strings.xml` with app_name
3. Update AndroidManifest.xml to use `@string/app_name`
4. Create `android/key.properties.template`
5. Update `android/.gitignore` with key.properties, *.jks
6. Add signing config to `android/app/build.gradle.kts`
7. Audit app icons (iOS + Android)
8. If placeholder: create temporary icon or document blocker

### Group 3 — Test coverage (@dspman + @qaman)
1. Add `streaming_first_lock_170_bpm` test
2. Add `streaming_first_lock_220_bpm` test
3. Add `streak_stability_170_bpm` test
4. Add `streaming_breakdown_exits_stable` test
5. Add `ffi_half_time_candidate_visible` test
6. Add `ffi_double_time_candidate_visible` test
7. Add `ffi_clipped_returns_clipped_mic_state` test
8. Verify: `cargo test --workspace` → all pass

### Group 4 — Known-fail tracking (@qaman)
1. Add `known_fail` fields to `fixture_manifest.json` for hitech_real_10
2. Update `parity.py` to handle known_fail fixtures
3. Verify: `parity.py` exits 0 with known_fail present

### Group 5 — Documentation (@docman)
1. Update README.md with v1.0.0 status section
2. Update RELEASE_CHECKLIST.md statuses
3. Add latency table to MOBILE_AUDIO.md
4. Finalize CHANGELOG.md [1.0.0] entry with date 2026-05-30

## 8. Tests

```bash
# Rust
/opt/homebrew/opt/rust/bin/cargo clippy --workspace -- -D warnings
/opt/homebrew/opt/rust/bin/cargo test --workspace

# Python
python3 -m unittest discover core/tests
python3 tools/offline-lab/offline_lab.py report
python3 tools/offline-lab/parity.py

# Node
/opt/homebrew/opt/nodejs/bin/node --test core/dsp/index.test.js

# Flutter
cd apps/mobile && flutter analyze
cd apps/mobile && flutter test
```

## 9. Risks

**High risk (excluded from this prompt):**
- CocoaPods → SPM migration — separate PR, high complexity

**Medium risk:**
- App icons: if placeholder, need design/generation — may require manual work
- Android signing: template only, actual keystore creation is manual

**Low risk:**
- Clippy fixes: mechanical, no logic change
- Version bump: trivial
- Test additions: follow existing patterns

**Fallback:**
- If icons are placeholder and cannot generate: document as blocker, continue
- If signing template fails: document manual steps, continue
- If any test fails: investigate, fix, or document as known issue

## 10. Done when

**Group 1:**
- [ ] `cargo clippy --workspace -- -D warnings` → 0 errors
- [ ] `Info.plist` contains `CFBundleDisplayName = "TrackScope"`

**Group 2:**
- [ ] `pubspec.yaml` → `version: 1.0.0+1`
- [ ] `strings.xml` exists with `app_name = "TrackScope"`
- [ ] `key.properties.template` exists, `key.properties` in `.gitignore`
- [ ] `build.gradle.kts` contains `signingConfigs.release`
- [ ] App icons documented (custom or placeholder replaced)

**Group 3:**
- [ ] 5 new tests added and passing
- [ ] Streaming timing: 170/200/220 BPM covered
- [ ] Streak stability: 170/180/195/200/220 BPM covered
- [ ] Breakdown-exit-from-STABLE test passes
- [ ] FFI tests ≥ 6 (was 3, added 3)

**Group 4:**
- [ ] `parity.py` exits 0 with known_fail fixtures
- [ ] `hitech_real_10` in KNOWN FAILS section, not FAILURES

**Group 5:**
- [ ] `README.md` contains `## Current Status — v1.0.0`
- [ ] `RELEASE_CHECKLIST.md` all statuses current
- [ ] `CHANGELOG.md` contains `[1.0.0] — 2026-05-30`

**Overall:**
- [ ] `flutter analyze apps/mobile` → 0 errors (CocoaPods warnings OK)
- [ ] `flutter test` passes
- [ ] All Python/Node tests pass
- [ ] No git-committed secrets (key.properties, *.jks)
