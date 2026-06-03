---
name: full-audit
description: Полный аудит проекта — flutter analyze, cargo clippy, поиск security-паттернов (unwrap/panic/unsafe/TODO/FIXME), проверка build файлов. Формирует отчёт в .claude/docs/audit-report.md. Запускай перед релизом или после крупного рефакторинга.
allowed-tools: [Bash, Read, Grep, Glob]
---

# Full Audit

Запускай последовательно. Каждый шаг пишет секцию в отчёт.

## 1. Flutter static analysis

```sh
cd apps/mobile
flutter analyze 2>&1
```

Фиксируй: errors / warnings / infos. Любой error — FAIL.

## 2. Rust clippy

```sh
/opt/homebrew/opt/rust/bin/cargo clippy --workspace -- -D warnings 2>&1
```

Фиксируй: warnings count. `-D warnings` означает любой warning = FAIL.

## 3. Rust tests (smoke check)

```sh
/opt/homebrew/opt/rust/bin/cargo test --workspace 2>&1 | tail -20
```

## 4. Python DSP regression

```sh
python3 -m unittest discover core/tests 2>&1 | tail -10
python3 tools/offline-lab/offline_lab.py report 2>&1 | tail -20
```

## 5. Security patterns

Grep по всей кодовой базе (исключая target/, .git/):

```sh
# Rust: panic paths
grep -rn "\.unwrap()\|\.expect(\|panic!" core/ --include="*.rs" | grep -v "#\[cfg(test)\]\|//\|tests/" | head -30

# Rust: unsafe
grep -rn "unsafe " core/ --include="*.rs" | grep -v "//\|tests/" | head -20

# All: TODO / FIXME
grep -rn "TODO\|FIXME\|HACK\|XXX" apps/ core/ tools/ --include="*.rs" --include="*.dart" --include="*.py" | grep -v ".git" | head -40
```

## 6. Build file integrity

```sh
# pubspec.yaml — проверить что config.dart.template существует и config.dart в .gitignore
ls apps/mobile/pubspec.yaml
grep -n "config.dart" apps/mobile/.gitignore 2>/dev/null || echo "WARN: config.dart not in .gitignore"

# Android key.properties
ls apps/mobile/android/key.properties 2>/dev/null && echo "EXISTS (should be gitignored)" || echo "OK: key.properties absent"

# iOS Podfile.lock
ls apps/mobile/ios/Podfile.lock && echo "Podfile.lock present" || echo "WARN: missing"

# Cargo.lock
ls Cargo.lock 2>/dev/null || ls core/Cargo.lock 2>/dev/null && echo "Cargo.lock present" || echo "WARN: missing"
```

## 7. Anti-fake check

```sh
# BPM math in Dart (must be zero outside lib/dsp/)
grep -rn "autocorrelation\|onset_detect\|spectral_flux\|bpm.*=.*[0-9]\{3\}" \
  apps/mobile/lib/ --include="*.dart" \
  | grep -v "lib/dsp/\|lib/capture/dsp_worker\|// \|test/" | head -20

# Hardcoded BPM values in production Rust
grep -rn "primary_bpm.*=.*[0-9]\|bpm.*=.*1[5-9][0-9]\|bpm.*=.*2[0-2][0-9]" \
  core/dsp/src/lib.rs | grep -v "//\|test\|config\|min\|max\|threshold" | head -10
```

## 8. Write report

После всех шагов создай `.claude/docs/audit-report.md` с секциями:

```markdown
# Audit Report — <DATE>

## Summary
PASS / FAIL + one-line status

## Flutter analyze
...results...

## Cargo clippy
...results...

## Rust tests
...results...

## Security patterns
### unwrap/expect in production paths
...
### unsafe blocks
...
### TODO/FIXME
...

## Build files
...

## Anti-fake check
...

## Findings requiring action
| Severity | File | Issue |
|---|---|---|
...
```

Exit с ненулевым кодом если есть FAIL (flutter error, clippy error, anti-fake violation).
