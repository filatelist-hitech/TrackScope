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
#        export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/27.2.12479018"
#      Если переменная не задана, скрипт ищет последнюю версию NDK автоматически.

set -euo pipefail

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

# ─── Проверить и установить таргеты ─────────────────────────────────────────
TARGETS=(
  "aarch64-linux-android"
  "armv7-linux-androideabi"
  "x86_64-linux-android"
)

for target in "${TARGETS[@]}"; do
  if ! "$RUSTUP" target list --installed 2>/dev/null | grep -q "^${target}$"; then
    echo "==> Добавляю Rust таргет $target..."
    "$RUSTUP" target add "$target"
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
      cargo build --release --target "$rust_target" -p hitech-bpm-ffi
    SO_SRC="$REPO_ROOT/target/$rust_target/release/libhitech_bpm_ffi.so"
  else
    env "$LINKER_VAR=$LINKER" \
      cargo build --target "$rust_target" -p hitech-bpm-ffi
    SO_SRC="$REPO_ROOT/target/$rust_target/debug/libhitech_bpm_ffi.so"
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
