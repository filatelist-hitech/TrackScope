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

# --- Добавить iOS таргет если не установлен ---
if ! "$RUSTUP" target list --installed 2>/dev/null | grep -q "$TARGET"; then
  echo "==> Добавляю Rust таргет $TARGET..."
  "$RUSTUP" target add "$TARGET"
fi

# --- Определить путь к тулчейну rustup ---
# На Mac с Homebrew-Rust в PATH нужно явно ставить тулчейн-bin первым,
# иначе cargo возьмёт Homebrew-rustc, у которого нет iOS-таргета.
TOOLCHAIN_BIN="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin"
if [[ ! -d "$TOOLCHAIN_BIN" ]]; then
  echo "ОШИБКА: тулчейн stable-aarch64-apple-darwin не найден в ~/.rustup."
  echo "Запусти: $RUSTUP toolchain install stable"
  exit 1
fi
echo "==> toolchain bin: $TOOLCHAIN_BIN"

# --- Собрать ---
echo "==> Компилирую core/ffi для $TARGET ($PROFILE)..."
cd "$REPO_ROOT"

BUILD_ENV="PATH=$TOOLCHAIN_BIN:$PATH RUSTUP_TOOLCHAIN=stable"

if [[ "$PROFILE" == "release" ]]; then
  env PATH="$TOOLCHAIN_BIN:$PATH" RUSTUP_TOOLCHAIN=stable \
    "$RUSTUP" run stable cargo build --release --target "$TARGET" -p hitech-bpm-ffi
  SRC="$REPO_ROOT/target/$TARGET/release/$LIB_NAME"
else
  env PATH="$TOOLCHAIN_BIN:$PATH" RUSTUP_TOOLCHAIN=stable \
    "$RUSTUP" run stable cargo build --target "$TARGET" -p hitech-bpm-ffi
  SRC="$REPO_ROOT/target/$TARGET/debug/$LIB_NAME"
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
