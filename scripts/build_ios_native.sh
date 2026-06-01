#!/usr/bin/env bash
# Собирает libhitech_bpm_ffi.a для iOS (aarch64) и кладёт её в
# apps/mobile/ios/Frameworks/ — откуда Xcode подберёт её при линковке.
#
# Использование:
#   bash scripts/build_ios_native.sh          # release (дефолт)
#   bash scripts/build_ios_native.sh debug    # debug
#
# Предварительные требования:
#   1. rustup установлен: https://rustup.rs
#   2. Xcode Command Line Tools: xcode-select --install
#
# После первого запуска этого скрипта необходимо однократно привязать
# библиотеку к Xcode-проекту вручную (делается один раз):
#   1. Открой apps/mobile/ios/Runner.xcworkspace в Xcode.
#   2. Выбери Runner → Build Phases → Link Binary With Libraries.
#   3. Нажми «+» → Add Other → Add Files.
#   4. Укажи apps/mobile/ios/Frameworks/libhitech_bpm_ffi.a.
#   5. Убедись, что в Build Settings → Library Search Paths добавлен
#      $(PROJECT_DIR)/Frameworks.
#   6. В Signing & Capabilities выбери свой Apple Developer Team.

set -euo pipefail

if [[ "$(id -u)" == "0" ]]; then
  echo "ОШИБКА: не запускай этот скрипт через sudo/root."
  echo "       Иначе Cargo создаст root-owned артефакты в target, и обычная сборка потом получит Permission denied."
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-release}"
TARGET="aarch64-apple-ios"
OUTPUT_DIR="$REPO_ROOT/apps/mobile/ios/Frameworks"
LIB_NAME="libhitech_bpm_ffi.a"

echo "==> Репозиторий: $REPO_ROOT"
echo "==> Профиль: $PROFILE  Таргет: $TARGET"

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

# --- Добавить iOS таргет если не установлен ---
if ! "$RUSTUP" target list --toolchain "$RUST_TOOLCHAIN" --installed 2>/dev/null | grep -q "^${TARGET}$"; then
  echo "==> Добавляю Rust таргет $TARGET..."
  "$RUSTUP" target add --toolchain "$RUST_TOOLCHAIN" "$TARGET"
fi

if ! "${RUSTC_CMD[@]}" --print target-libdir --target "$TARGET" >/dev/null 2>&1; then
  echo "ОШИБКА: rustc из toolchain '$RUST_TOOLCHAIN' не видит стандартную библиотеку для $TARGET."
  echo "       Проверь установку: $RUSTUP target add --toolchain $RUST_TOOLCHAIN $TARGET"
  exit 1
fi

# --- Собрать ---
echo "==> Компилирую core/ffi для $TARGET ($PROFILE)..."
cd "$REPO_ROOT"

if [[ "$PROFILE" == "release" ]]; then
  "${CARGO_CMD[@]}" build --release --target "$TARGET" -p hitech-bpm-ffi
  SRC="$CARGO_TARGET_DIR/$TARGET/release/$LIB_NAME"
else
  "${CARGO_CMD[@]}" build --target "$TARGET" -p hitech-bpm-ffi
  SRC="$CARGO_TARGET_DIR/$TARGET/debug/$LIB_NAME"
fi

# --- Скопировать в iOS-проект ---
mkdir -p "$OUTPUT_DIR"
cp "$SRC" "$OUTPUT_DIR/$LIB_NAME"

echo ""
echo "==> Готово: $OUTPUT_DIR/$LIB_NAME"
echo "    Размер: $(du -sh "$OUTPUT_DIR/$LIB_NAME" | cut -f1)"
echo ""
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│  Следующие шаги (однократно, если ещё не сделано):             │"
echo "│                                                                 │"
echo "│  1. Открой apps/mobile/ios/Runner.xcworkspace в Xcode          │"
echo "│  2. Runner → Build Phases → Link Binary With Libraries         │"
echo "│     Нажми «+» → Add Other → Add Files                         │"
echo "│     Выбери: apps/mobile/ios/Frameworks/libhitech_bpm_ffi.a     │"
echo "│  3. Build Settings → Library Search Paths → добавь:           │"
echo "│     \$(PROJECT_DIR)/Frameworks                                  │"
echo "│  4. Signing & Capabilities → Team → выбери свой Apple ID       │"
echo "│  5. Подключи iPhone кабелем, нажми «Доверять» на телефоне      │"
echo "│  6. flutter run --release (из apps/mobile/)                    │"
echo "└─────────────────────────────────────────────────────────────────┘"
