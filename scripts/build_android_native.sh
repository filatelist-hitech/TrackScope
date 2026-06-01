#!/usr/bin/env bash
# Собирает libhitech_bpm_ffi.so для Android (arm64-v8a, armeabi-v7a, x86_64)
# и кладёт файлы в apps/mobile/android/app/src/main/jniLibs/<abi>/ —
# откуда Gradle подберёт их при сборке APK.
#
# Использование:
#   bash scripts/build_android_native.sh          # release (дефолт)
#   bash scripts/build_android_native.sh debug    # debug
#
# Предварительные требования:
#   1. Android NDK установлен через Android Studio SDK Manager
#      (SDK Manager → SDK Tools → NDK (Side by side))
#   2. rustup установлен: https://rustup.rs
#   3. Rust Android таргеты добавлены:
#        rustup target add aarch64-linux-android
#        rustup target add armv7-linux-androideabi
#        rustup target add x86_64-linux-android
#   4. Переменная ANDROID_NDK_HOME указывает на директорию NDK, например:
#        export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/28.2.13676358"
#      ВАЖНО: путь должен указывать на директорию с source.properties,
#      НЕ на вложенную android-ndk-r28c/ папку внутри неё.
#      Если переменная не задана, скрипт ищет последнюю версию NDK автоматически.
#   5. JAVA_HOME должен указывать на JDK 17+, например Android Studio bundled JDK:
#        export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

set -euo pipefail

if [[ "$(id -u)" == "0" ]]; then
  echo "ОШИБКА: не запускай этот скрипт через sudo/root."
  echo "       Иначе Cargo создаст root-owned артефакты в target, и обычная сборка потом получит Permission denied."
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-release}"
JNI_LIBS_DIR="$REPO_ROOT/apps/mobile/android/app/src/main/jniLibs"

echo "==> Репозиторий: $REPO_ROOT"
echo "==> Профиль: $PROFILE"

# ─── Найти NDK ────────────────────────────────────────────────────────────────
NDK_HOME="${ANDROID_NDK_HOME:-}"

if [[ -z "$NDK_HOME" ]]; then
  ANDROID_SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  NDK_ROOT="$ANDROID_SDK/ndk"
  if [[ -d "$NDK_ROOT" ]] && [[ -n "$(ls -A "$NDK_ROOT" 2>/dev/null)" ]]; then
    # Взять последнюю установленную версию NDK
    NDK_HOME="$NDK_ROOT/$(ls "$NDK_ROOT" | sort -V | tail -1)"
  fi
fi

if [[ -z "$NDK_HOME" ]] || [[ ! -d "$NDK_HOME" ]]; then
  echo ""
  echo "ОШИБКА: Android NDK не найден."
  echo ""
  echo "Установи NDK через Android Studio:"
  echo "  1. Открой Android Studio"
  echo "  2. SDK Manager → SDK Tools → NDK (Side by side) → Apply"
  echo "  3. Либо задай переменную окружения:"
  echo "       export ANDROID_NDK_HOME=\"\$HOME/Library/Android/sdk/ndk/<версия>\""
  echo ""
  exit 1
fi

echo "==> NDK: $NDK_HOME"

# На macOS тулчейн NDK расположен в darwin-x86_64 (работает и на M1/M2 через Rosetta)
NDK_TOOLCHAIN="$NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin"
if [[ ! -d "$NDK_TOOLCHAIN" ]]; then
  echo "ОШИБКА: NDK toolchain не найден: $NDK_TOOLCHAIN"
  exit 1
fi
echo "==> NDK toolchain: $NDK_TOOLCHAIN"

# ─── Найти rustup ────────────────────────────────────────────────────────────
RUSTUP=""
for candidate in \
    "$(command -v rustup 2>/dev/null)" \
    "$HOME/.cargo/bin/rustup" \
    "/opt/homebrew/bin/rustup" \
    "/opt/homebrew/Cellar/rustup/1.29.0_1/bin/rustup"; do
  if [[ -x "$candidate" ]]; then
    RUSTUP="$candidate"
    break
  fi
done

if [[ -z "$RUSTUP" ]]; then
  echo "ОШИБКА: rustup не найден. Установи: brew install rustup && rustup-init"
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

# Скрипт ниже копирует .so из repo-local target, поэтому не даём глобальному
# ~/.cargo/config.toml перенаправить build.target-dir за пределы репозитория.
export CARGO_TARGET_DIR="$REPO_ROOT/target/android-native"
export RUSTC="$RUSTC_BIN"
echo "==> Cargo target dir: $CARGO_TARGET_DIR"

if [[ -e "$CARGO_TARGET_DIR" && ! -w "$CARGO_TARGET_DIR" ]]; then
  echo "ОШИБКА: Cargo target dir существует, но недоступен для записи: $CARGO_TARGET_DIR"
  echo "       Обычно это значит, что предыдущая сборка запускалась через sudo."
  echo "       Починка: sudo rm -rf \"$CARGO_TARGET_DIR\""
  exit 1
fi
mkdir -p "$CARGO_TARGET_DIR"

# ─── Проверить и установить таргеты ─────────────────────────────────────────
TARGETS=(
  "aarch64-linux-android"
  "armv7-linux-androideabi"
  "x86_64-linux-android"
)

for target in "${TARGETS[@]}"; do
  if ! "$RUSTUP" target list --toolchain "$RUST_TOOLCHAIN" --installed 2>/dev/null | grep -q "^${target}$"; then
    echo "==> Добавляю Rust таргет $target..."
    "$RUSTUP" target add --toolchain "$RUST_TOOLCHAIN" "$target"
  fi

  if ! "${RUSTC_CMD[@]}" --print target-libdir --target "$target" >/dev/null 2>&1; then
    echo "ОШИБКА: rustc из toolchain '$RUST_TOOLCHAIN' не видит стандартную библиотеку для $target."
    echo "       Проверь установку: $RUSTUP target add --toolchain $RUST_TOOLCHAIN $target"
    exit 1
  fi
done

# ─── Таблица ABI → таргет + имя линкера ──────────────────────────────────────
# Формат: "android_abi|rust_target|ndk_clang_prefix|api_level"
ABI_TABLE=(
  "arm64-v8a|aarch64-linux-android|aarch64-linux-android21-clang|21"
  "armeabi-v7a|armv7-linux-androideabi|armv7a-linux-androideabi21-clang|21"
  "x86_64|x86_64-linux-android|x86_64-linux-android21-clang|21"
)

cd "$REPO_ROOT"

BUILT_ABIS=()
FAILED_ABIS=()

for entry in "${ABI_TABLE[@]}"; do
  IFS="|" read -r abi rust_target clang_prefix api_level <<< "$entry"

  echo ""
  echo "──────────────────────────────────────────────────────────────"
  echo "==> ABI: $abi  Таргет: $rust_target"

  LINKER="$NDK_TOOLCHAIN/$clang_prefix"
  if [[ ! -f "$LINKER" ]]; then
    echo "  ПРЕДУПРЕЖДЕНИЕ: линкер не найден: $LINKER"
    echo "  Пропускаю $abi"
    FAILED_ABIS+=("$abi (линкер не найден)")
    continue
  fi

  # Имя env-переменной для линкера: CARGO_TARGET_<TARGET_UPPER>_LINKER
  # Заменяем - и . на _ и приводим к верхнему регистру
  LINKER_VAR="CARGO_TARGET_$(echo "$rust_target" | tr '[:lower:]-' '[:upper:]_')_LINKER"

  if [[ "$PROFILE" == "release" ]]; then
    env "$LINKER_VAR=$LINKER" \
      "${CARGO_CMD[@]}" build --release --target "$rust_target" -p hitech-bpm-ffi
    SO_SRC="$CARGO_TARGET_DIR/$rust_target/release/libhitech_bpm_ffi.so"
  else
    env "$LINKER_VAR=$LINKER" \
      "${CARGO_CMD[@]}" build --target "$rust_target" -p hitech-bpm-ffi
    SO_SRC="$CARGO_TARGET_DIR/$rust_target/debug/libhitech_bpm_ffi.so"
  fi

  if [[ ! -f "$SO_SRC" ]]; then
    echo "  ОШИБКА: .so не создан: $SO_SRC"
    FAILED_ABIS+=("$abi (cargo build упал)")
    continue
  fi

  # Скопировать в jniLibs
  DST_DIR="$JNI_LIBS_DIR/$abi"
  mkdir -p "$DST_DIR"
  cp "$SO_SRC" "$DST_DIR/libhitech_bpm_ffi.so"

  SIZE="$(du -sh "$DST_DIR/libhitech_bpm_ffi.so" | cut -f1)"
  echo "==> Готово: $DST_DIR/libhitech_bpm_ffi.so  ($SIZE)"
  BUILT_ABIS+=("$abi")
done

# ─── Итог ─────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════"

if [[ ${#BUILT_ABIS[@]} -gt 0 ]]; then
  echo "✓  Собраны ABI: ${BUILT_ABIS[*]}"
fi

if [[ ${#FAILED_ABIS[@]} -gt 0 ]]; then
  echo "✗  Ошибки ABI: ${FAILED_ABIS[*]}"
fi

echo ""
echo "   jniLibs → $JNI_LIBS_DIR"
echo ""

if [[ ${#BUILT_ABIS[@]} -eq 0 ]]; then
  echo "ОШИБКА: ни одного ABI не собрано."
  exit 1
fi

# Если собран хотя бы arm64-v8a, дальше можно собрать APK:
if printf '%s\n' "${BUILT_ABIS[@]}" | grep -q "arm64-v8a"; then
  echo "┌─────────────────────────────────────────────────────────────────┐"
  echo "│  Следующий шаг — сборка APK:                                   │"
  echo "│                                                                 │"
  echo "│  Debug APK (без подписи, для эмулятора):                       │"
  echo "│    cd apps/mobile && flutter build apk --debug                  │"
  echo "│    → build/app/outputs/flutter-apk/app-debug.apk               │"
  echo "│                                                                 │"
  echo "│  Release APK (нужен key.properties):                           │"
  echo "│    cd apps/mobile && flutter build apk --release                │"
  echo "│    → build/app/outputs/flutter-apk/app-release.apk             │"
  echo "│                                                                 │"
  echo "│  Запуск в эмуляторе:                                           │"
  echo "│    flutter emulators --launch <emulator_id>                     │"
  echo "│    flutter run                                                  │"
  echo "└─────────────────────────────────────────────────────────────────┘"
fi
