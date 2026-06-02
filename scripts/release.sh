#!/usr/bin/env bash
# Unified release-скрипт для hitech-bpm-radar
#
# Использование:
#   bash scripts/release.sh android          # Android: Free APK + PRO APK
#   bash scripts/release.sh ios              # iOS: деплой на iPhone (Free + PRO)
#   bash scripts/release.sh ios-free         # iOS: только Free на iPhone
#   bash scripts/release.sh ios-pro          # iOS: только PRO на iPhone
#   bash scripts/release.sh simulator        # iOS Simulator: Free + PRO
#   bash scripts/release.sh all              # Android APK + iOS деплой
#   bash scripts/release.sh clean            # Мягкая очистка (Flutter + Gradle transforms)
#   bash scripts/release.sh clean-all        # Полная очистка (+ Rust target)
#
# Переменные окружения:
#   IPHONE_ID     — UDID устройства (дефолт: 00008030-0011382E21E0C02E)
#   JAVA_HOME     — JDK 17+ (дефолт: Android Studio bundled JDK 21)
#   ANDROID_HOME  — Android SDK (дефолт: ~/Library/Android/sdk)
#   SKIP_NATIVE   — если "1", пропускает сборку Rust .so/.a (ускоряет повторные запуски)
#
# Требования:
#   Android: JAVA_HOME, Android NDK, rustup
#   iOS: Xcode, rustup, CocoaPods, подпись в Xcode (Signing & Capabilities → Team)

set -euo pipefail

# ────────────────────────────────────────────────
# Константы
# ────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$REPO_ROOT/apps/mobile"
SCRIPT_DIR="$REPO_ROOT/scripts"
CMD="${1:-help}"

# Устройства
IPHONE_ID="${IPHONE_ID:-00008030-0011382E21E0C02E}"

# Java / Android SDK
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/$(ls "$ANDROID_HOME/ndk" 2>/dev/null | sort -V | tail -1)}"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

# Цвета
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${CYAN}==> $*${NC}"; }
ok()   { echo -e "${GREEN}✓  $*${NC}"; }
warn() { echo -e "${YELLOW}⚠  $*${NC}"; }
err()  { echo -e "${RED}✗  $*${NC}"; exit 1; }

# ────────────────────────────────────────────────
# Утилиты
# ────────────────────────────────────────────────

check_java() {
  if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
    err "JAVA_HOME не найден: $JAVA_HOME
    Убедись, что Android Studio установлен, или задай JAVA_HOME вручную."
  fi
  local ver
  ver="$("$JAVA_HOME/bin/java" -version 2>&1 | head -1)"
  log "Java: $ver"
}

check_flutter() {
  if ! command -v flutter &>/dev/null; then
    err "flutter не найден в PATH."
  fi
  log "Flutter: $(flutter --version 2>&1 | head -1)"
}

build_rust_android() {
  if [[ "${SKIP_NATIVE:-0}" == "1" ]]; then
    warn "SKIP_NATIVE=1 — пропускаем Rust Android (.so)."
    return
  fi
  log "Собираем Rust → Android .so..."
  bash "$SCRIPT_DIR/build_android_native.sh" release
}

build_rust_ios() {
  if [[ "${SKIP_NATIVE:-0}" == "1" ]]; then
    warn "SKIP_NATIVE=1 — пропускаем Rust iOS (.a)."
    return
  fi
  log "Собираем Rust → iOS .a (device + simulator)..."
  bash "$SCRIPT_DIR/build_ios_native.sh" release
}

apk_output() {
  ls -lh "$MOBILE_DIR/build/app/outputs/flutter-apk/"*.apk 2>/dev/null || true
}

# ────────────────────────────────────────────────
# Команда: android
# ────────────────────────────────────────────────

cmd_android() {
  log "=== ANDROID BUILD ==="
  check_java
  check_flutter
  build_rust_android

  cd "$MOBILE_DIR"

  echo ""
  log "Android Free APK (release)..."
  flutter build apk --release
  cp build/app/outputs/flutter-apk/app-release.apk \
     build/app/outputs/flutter-apk/app-release-free.apk
  ok "Free APK: build/app/outputs/flutter-apk/app-release-free.apk"

  echo ""
  log "Android PRO APK (release, FORCE_PRO=true)..."
  flutter build apk --release --dart-define=FORCE_PRO=true
  cp build/app/outputs/flutter-apk/app-release.apk \
     build/app/outputs/flutter-apk/app-release-pro.apk
  ok "PRO APK:  build/app/outputs/flutter-apk/app-release-pro.apk"

  echo ""
  echo "═══════════════════════════════════════════════════"
  ok "Android сборка завершена:"
  apk_output
}

# ────────────────────────────────────────────────
# Команда: ios / ios-free / ios-pro
# ────────────────────────────────────────────────

cmd_ios() {
  local variant="${1:-both}"  # free | pro | both
  log "=== iOS DEPLOY → $IPHONE_ID ==="
  check_flutter
  build_rust_ios

  cd "$MOBILE_DIR"

  if [[ "$variant" == "free" || "$variant" == "both" ]]; then
    echo ""
    log "Деплой iOS Free на iPhone ($IPHONE_ID)..."
    flutter run --release -d "$IPHONE_ID"
    ok "iOS Free установлена."
  fi

  if [[ "$variant" == "pro" || "$variant" == "both" ]]; then
    echo ""
    log "Деплой iOS PRO на iPhone ($IPHONE_ID)..."
    flutter run --release --dart-define=FORCE_PRO=true -d "$IPHONE_ID"
    ok "iOS PRO установлена."
  fi
}

# ────────────────────────────────────────────────
# Команда: simulator
# ────────────────────────────────────────────────

cmd_simulator() {
  log "=== iOS SIMULATOR BUILD ==="
  check_flutter
  build_rust_ios

  cd "$MOBILE_DIR"

  echo ""
  log "iOS Simulator Free..."
  flutter build ios --simulator --no-codesign
  ok "Free: build/ios/iphonesimulator/Runner.app"

  echo ""
  log "iOS Simulator PRO (FORCE_PRO=true)..."
  flutter build ios --simulator --no-codesign --dart-define=FORCE_PRO=true
  ok "PRO: build/ios/iphonesimulator/Runner.app (overwritten — install manually if need both)"
}

# ────────────────────────────────────────────────
# Команда: all
# ────────────────────────────────────────────────

cmd_all() {
  log "=== FULL RELEASE BUILD ==="
  cmd_android
  echo ""
  cmd_ios "pro"
}

# ────────────────────────────────────────────────
# Команда: clean
# ────────────────────────────────────────────────

cmd_clean() {
  log "=== МЯГКАЯ ОЧИСТКА ==="

  # Flutter build artifacts
  if [[ -d "$MOBILE_DIR" ]]; then
    log "flutter clean..."
    cd "$MOBILE_DIR"
    flutter clean
    ok "Flutter build artifacts удалены."
  fi

  # Убиваем зависшие Gradle daemon'ы
  log "Останавливаем Gradle daemon'ы..."
  pkill -f "GradleDaemon\|gradle-launcher" 2>/dev/null || true
  sleep 1
  ok "Gradle daemon'ы остановлены."

  # Удаляем только lock-файлы execution history (не весь transforms cache)
  rm -f "$MOBILE_DIR/android/.gradle/"*/executionHistory/*.lock 2>/dev/null || true
  ok "Gradle lock-файлы удалены."

  echo ""
  ok "Мягкая очистка завершена."
  warn "Совет: если следующая сборка падает с gradle-1.0.0.jar — запусти clean-gradle"
}

cmd_clean_gradle() {
  log "Очищаем Gradle transform cache (fixes gradle-1.0.0.jar error)..."
  pkill -f "GradleDaemon\|gradle-launcher" 2>/dev/null || true; sleep 1
  rm -rf ~/.gradle/caches/9.1.0/transforms/ 2>/dev/null || true
  ok "~/.gradle/caches/9.1.0/transforms/ очищен."
  warn "Следующая сборка перекачает Gradle transform artifacts (~30-60 сек)."
}

cmd_clean_all() {
  log "=== ПОЛНАЯ ОЧИСТКА ==="
  cmd_clean
  cmd_clean_gradle

  # Rust build artifacts
  log "Очищаем Rust target (ios-native + android-native)..."
  rm -rf "$REPO_ROOT/target/ios-native" 2>/dev/null || true
  rm -rf "$REPO_ROOT/target/android-native" 2>/dev/null || true
  ok "Rust target директории удалены."

  # Все Gradle caches (пересоздаст при следующей сборке — займёт ~2-3 мин)
  log "Очищаем все Gradle caches (9.1.0)..."
  rm -rf ~/.gradle/caches/9.1.0/ 2>/dev/null || true
  ok "~/.gradle/caches/9.1.0/ очищен."

  echo ""
  ok "Полная очистка завершена. Следующая сборка пересоберёт всё с нуля (~5-10 мин)."
  warn "Примечание: ~/.gradle/caches/modules-2/ (Maven deps) НЕ удалён — он большой и не ломается."
}

# ────────────────────────────────────────────────
# Команда: help
# ────────────────────────────────────────────────

cmd_help() {
  cat <<'EOF'

hitech-bpm-radar release script

ИСПОЛЬЗОВАНИЕ:
  bash scripts/release.sh <команда> [опции]

КОМАНДЫ:
  android       Собрать Android Free APK + PRO APK (release)
  ios           Задеплоить Free + PRO на iPhone (IPHONE_ID)
  ios-free      Задеплоить только Free на iPhone
  ios-pro       Задеплоить только PRO на iPhone
  simulator     Собрать для iOS Simulator (Free + PRO)
  all           android + ios-pro
  clean         Flutter clean + убить daemon'ы (безопасно, быстро)
  clean-gradle  Очистить Gradle transform cache (фикс gradle-1.0.0.jar)
  clean-all     Полная очистка: flutter + gradle + Rust target
  help          Показать это сообщение

ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ:
  IPHONE_ID     UDID iPhone (дефолт: 00008030-0011382E21E0C02E)
  JAVA_HOME     JDK 17+ (дефолт: Android Studio bundled JDK 21)
  ANDROID_HOME  Android SDK root (дефолт: ~/Library/Android/sdk)
  SKIP_NATIVE   Пропустить Rust-сборку: SKIP_NATIVE=1 bash scripts/release.sh android

ПРИМЕРЫ:
  # Первая сборка (долго ~5 мин):
  bash scripts/release.sh android

  # Повторная сборка без Rust (быстро ~30 сек):
  SKIP_NATIVE=1 bash scripts/release.sh android

  # Задеплоить PRO на iPhone:
  bash scripts/release.sh ios-pro

  # Полная сборка + деплой PRO на iPhone:
  bash scripts/release.sh all

  # Почистить всё и пересобрать с нуля:
  bash scripts/release.sh clean-all && bash scripts/release.sh android

  # Поменять iPhone:
  IPHONE_ID=<your-udid> bash scripts/release.sh ios-pro

APK ФАЙЛЫ (после android):
  apps/mobile/build/app/outputs/flutter-apk/app-release-free.apk
  apps/mobile/build/app/outputs/flutter-apk/app-release-pro.apk

EOF
}

# ────────────────────────────────────────────────
# Router
# ────────────────────────────────────────────────

case "$CMD" in
  android)     cmd_android       ;;
  ios)         cmd_ios "both"    ;;
  ios-free)    cmd_ios "free"    ;;
  ios-pro)     cmd_ios "pro"     ;;
  simulator)   cmd_simulator     ;;
  all)         cmd_all           ;;
  clean)       cmd_clean         ;;
  clean-gradle) cmd_clean_gradle ;;
  clean-all)   cmd_clean_all     ;;
  help|--help|-h) cmd_help       ;;
  *)
    echo "Неизвестная команда: $CMD"
    cmd_help
    exit 1
    ;;
esac
