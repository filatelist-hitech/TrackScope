#!/usr/bin/env bash
# Собирает libhitech_bpm_ffi.a для iOS (device + simulator) и кладёт в:
#   apps/mobile/ios/Frameworks/iphoneos/libhitech_bpm_ffi.a      (device)
#   apps/mobile/ios/Frameworks/iphonesimulator/libhitech_bpm_ffi.a (simulator)
#
# Xcode автоматически выбирает нужную библиотеку через $(PLATFORM_NAME) в
# OTHER_LDFLAGS = "-force_load $(PROJECT_DIR)/Frameworks/$(PLATFORM_NAME)/libhitech_bpm_ffi.a"
#
# Использование:
#   bash scripts/build_ios_native.sh          # release (дефолт, device + simulator)
#   bash scripts/build_ios_native.sh debug    # debug
#
# Предварительные требования:
#   1. rustup установлен: https://rustup.rs (НЕ Homebrew Rust — нужен rustup для ios-sim target)
#   2. Xcode Command Line Tools: xcode-select --install
#
# Подпись (однократно в Xcode):
#   Runner → Signing & Capabilities → Team → выбери свой Apple ID

set -euo pipefail

if [[ "$(id -u)" == "0" ]]; then
  echo "ОШИБКА: не запускай этот скрипт через sudo/root."
  echo "       Иначе Cargo создаст root-owned артефакты в target, и обычная сборка потом получит Permission denied."
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-release}"
TARGET_DEVICE="aarch64-apple-ios"
TARGET_SIM="aarch64-apple-ios-sim"
OUTPUT_DIR="$REPO_ROOT/apps/mobile/ios/Frameworks"
LIB_NAME="libhitech_bpm_ffi.a"

echo "==> Репозиторий: $REPO_ROOT"
echo "==> Профиль: $PROFILE"
echo "==> Таргеты: $TARGET_DEVICE + $TARGET_SIM"

# --- Найти rustup (поддерживает Homebrew-установку и стандартную) ---
RUSTUP=""
for candidate in \
    "$(command -v rustup 2>/dev/null)" \
    "/opt/homebrew/Cellar/rustup/1.29.0_1/bin/rustup" \
    "/opt/homebrew/bin/rustup" \
    "$HOME/.cargo/bin/rustup"; do
  if [[ -x "$candidate" ]]; then
    RUSTUP="$candidate"
    break
  fi
done

if [[ -z "$RUSTUP" ]]; then
  echo ""
  echo "ОШИБКА: rustup не найден."
  echo "Установи Homebrew-версию: brew install rustup && rustup-init"
  exit 1
fi
echo "==> rustup: $RUSTUP"

RUST_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-stable}"
CARGO_BIN="$("$RUSTUP" which --toolchain "$RUST_TOOLCHAIN" cargo)"
RUSTC_BIN="$("$RUSTUP" which --toolchain "$RUST_TOOLCHAIN" rustc)"
CARGO_CMD=("$CARGO_BIN")
RUSTC_CMD=("$RUSTC_BIN")
echo "==> Rust toolchain: $RUST_TOOLCHAIN"
echo "==> cargo: $("${CARGO_CMD[@]}" --version)"
echo "==> rustc: $RUSTC_BIN"

# Держим cargo-артефакты внутри репозитория, чтобы глобальный
# ~/.cargo/config.toml не уводил build.target-dir в домашний каталог.
export CARGO_TARGET_DIR="$REPO_ROOT/target/ios-native"
export RUSTC="$RUSTC_BIN"
echo "==> Cargo target dir: $CARGO_TARGET_DIR"

if [[ -e "$CARGO_TARGET_DIR" && ! -w "$CARGO_TARGET_DIR" ]]; then
  echo "ОШИБКА: Cargo target dir существует, но недоступен для записи: $CARGO_TARGET_DIR"
  echo "       Обычно это значит, что предыдущая сборка запускалась через sudo."
  echo "       Починка: sudo rm -rf \"$CARGO_TARGET_DIR\""
  exit 1
fi
mkdir -p "$CARGO_TARGET_DIR"

build_target() {
  local TARGET="$1"
  local DEST_SUBDIR="$2"
  local DEST="$OUTPUT_DIR/$DEST_SUBDIR/$LIB_NAME"

  # Добавить таргет если не установлен
  if ! "$RUSTUP" target list --toolchain "$RUST_TOOLCHAIN" --installed 2>/dev/null | grep -q "^${TARGET}$"; then
    echo "==> Добавляю Rust таргет $TARGET..."
    "$RUSTUP" target add --toolchain "$RUST_TOOLCHAIN" "$TARGET"
  fi

  echo ""
  echo "──────────────────────────────────────────"
  echo "==> Компилирую: $TARGET → $DEST_SUBDIR/"

  if [[ "$PROFILE" == "release" ]]; then
    "${CARGO_CMD[@]}" build --release --target "$TARGET" -p hitech-bpm-ffi
    SRC="$CARGO_TARGET_DIR/$TARGET/release/$LIB_NAME"
  else
    "${CARGO_CMD[@]}" build --target "$TARGET" -p hitech-bpm-ffi
    SRC="$CARGO_TARGET_DIR/$TARGET/debug/$LIB_NAME"
  fi

  mkdir -p "$OUTPUT_DIR/$DEST_SUBDIR"
  cp "$SRC" "$DEST"
  echo "==> Готово: $DEST ($(du -sh "$DEST" | cut -f1))"
}

cd "$REPO_ROOT"

# Device (iphoneos)
build_target "$TARGET_DEVICE" "iphoneos"

# Simulator (iphonesimulator — arm64-apple-ios-sim, Apple Silicon Mac)
build_target "$TARGET_SIM" "iphonesimulator"

# Backward-compat copy (device lib) для старых ссылок
cp "$OUTPUT_DIR/iphoneos/$LIB_NAME" "$OUTPUT_DIR/$LIB_NAME"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✓  Готово:"
echo "   Device:    $OUTPUT_DIR/iphoneos/$LIB_NAME"
echo "   Simulator: $OUTPUT_DIR/iphonesimulator/$LIB_NAME"
echo ""
echo "   Xcode подхватит нужную автоматически через:"
echo "   OTHER_LDFLAGS = -force_load \$(PROJECT_DIR)/Frameworks/\$(PLATFORM_NAME)/libhitech_bpm_ffi.a"
echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│  Следующий шаг:                                             │"
echo "│  flutter build ios --simulator --no-codesign  (симулятор)   │"
echo "│  flutter run (device — нужна подпись в Xcode)               │"
echo "└──────────────────────────────────────────────────────────────┘"
