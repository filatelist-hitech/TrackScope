# Build Guide — trackscope

Полное руководство по сборке, тестированию и деплою приложения.

---

## Быстрый старт (TL;DR)

```sh
# Установить в ~/.zshrc:
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

# Android: оба APK
bash scripts/release.sh android

# iOS PRO → на iPhone
bash scripts/release.sh ios-pro

# Если что-то сломалось:
bash scripts/release.sh clean
bash scripts/release.sh clean-gradle  # только если NoSuchFileException gradle-1.0.0.jar
```

---

## Предварительные требования

### macOS инструменты

| Инструмент | Версия | Установка |
|---|---|---|
| Xcode | 15+ | App Store |
| Android Studio | latest | `brew install --cask android-studio` |
| Flutter | 3.44+ | `brew install flutter` |
| rustup | latest | `brew install rustup && rustup-init` |
| CocoaPods | 1.14+ | `brew install cocoapods` |

### Android SDK компоненты (через SDK Manager в Android Studio)

- Android SDK Platform 35
- Android SDK Build-Tools 36
- Android NDK (Side by side) **28.2.13676358** ← конкретная версия

### Rust Android targets

```sh
rustup target add aarch64-linux-android    # arm64 (современные телефоны)
rustup target add armv7-linux-androideabi  # armv7 (опционально)
rustup target add x86_64-linux-android    # x86_64 эмулятор на Intel Mac
```

### Переменные окружения (~/.zshrc)

```sh
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

# Применить:
source ~/.zshrc
```

**ВАЖНО:** `JAVA_HOME` обязателен. Системная `/usr/bin/java` = Java 1.8 → TLS ошибки в Gradle.

---

## Android

### Сборка

```sh
# Подготовка (один раз):
bash scripts/build_android_native.sh     # Rust → .so для всех ABI

# Оба APK:
bash scripts/release.sh android
# → apps/mobile/build/app/outputs/flutter-apk/app-release-free.apk (52 MB)
# → apps/mobile/build/app/outputs/flutter-apk/app-release-pro.apk  (52 MB)

# Повторная сборка без Rust (быстро):
SKIP_NATIVE=1 bash scripts/release.sh android
```

### Структура APK

| Файл | Тип | Подпись | dart-define |
|---|---|---|---|
| `app-release-free.apk` | Free (170–230 BPM) | debug key* | — |
| `app-release-pro.apk` | PRO (155–230 BPM) | debug key* | `FORCE_PRO=true` |
| `app-debug.apk` | Debug | debug key | — |

\* Для Google Play нужен release keystore. Пока — debug-signed, достаточно для sideload.

### Создание release keystore (для Play Store)

```sh
keytool -genkey -v \
  -keystore apps/mobile/android/android-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias hitech-bpm

# Заполнить key.properties из шаблона:
cp apps/mobile/android/key.properties.template apps/mobile/android/key.properties
# Отредактировать key.properties с реальными паролями
```

### Эмулятор AVD

```sh
# Запустить Pixel 7 (создать через AVD Manager в Android Studio):
flutter emulators --launch Pixel_7

# Установить APK:
adb install apps/mobile/build/app/outputs/flutter-apk/app-debug.apk

# Или запустить с hot-reload:
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
cd apps/mobile && flutter run -d emulator-5554
```

### Известные проблемы Android

| Ошибка | Причина | Решение |
|---|---|---|
| `NDK did not have source.properties` | NDK в подпапке | [→ ANDROID_TEST_PLAN.md](ANDROID_TEST_PLAN.md#типичные-ошибки-и-решения) |
| `TLS handshake failed` | Java 1.8 | Добавить JAVA_HOME в ~/.zshrc |
| `Cannot lock execution history` | Daemon lock | `bash scripts/release.sh clean` |
| `NoSuchFileException: gradle-1.0.0.jar` | Стейл transform cache | `bash scripts/release.sh clean-gradle` |
| `instrumentation-hierarchy.bin deserialization` | Gradle 9.x + AGP 9.x баг | Зафиксировано: Gradle 8.11.1 + AGP 8.7.3 |

---

## iOS

### Подготовка нативной библиотеки

```sh
bash scripts/build_ios_native.sh
# Создаёт:
#   apps/mobile/ios/Frameworks/iphoneos/libhitech_bpm_ffi.a       (real device)
#   apps/mobile/ios/Frameworks/iphonesimulator/libhitech_bpm_ffi.a (simulator)
```

**ВАЖНО:** Скрипт использует `rustup`-managed rustc, не Homebrew Rust. Homebrew Rust не имеет sysroot для `aarch64-apple-ios-sim`.

### Деплой на iPhone (wireless)

```sh
# PRO версия на iPhone (UDID: 00008030-0011382E21E0C02E):
bash scripts/release.sh ios-pro

# или вручную:
cd apps/mobile
flutter run --release --dart-define=FORCE_PRO=true -d 00008030-0011382E21E0C02E

# Free версия:
bash scripts/release.sh ios-free

# Сменить iPhone:
IPHONE_ID=<your-udid> bash scripts/release.sh ios-pro
```

Для работы нужно: **Xcode Signing** — открой `apps/mobile/ios/Runner.xcworkspace` → Runner → Signing & Capabilities → Team → выбери Apple ID.

### iOS Simulator

```sh
# Собрать обе библиотеки (device + simulator):
bash scripts/build_ios_native.sh

# Запустить iPhone 13 Pro симулятор:
xcrun simctl boot C3616C95-3F7B-42BD-83B0-207C7B5CCCE2

# Free симулятор:
cd apps/mobile && flutter build ios --simulator --no-codesign

# PRO симулятор:
cd apps/mobile && flutter build ios --simulator --no-codesign --dart-define=FORCE_PRO=true
flutter run -d C3616C95-3F7B-42BD-83B0-207C7B5CCCE2

# Через скрипт:
bash scripts/release.sh simulator
```

### Xcode одноразовая конфигурация (первый раз)

Уже выполнена в `project.pbxproj`:
- `OTHER_LDFLAGS = -force_load $(PROJECT_DIR)/Frameworks/$(PLATFORM_NAME)/libhitech_bpm_ffi.a`
- `LIBRARY_SEARCH_PATHS = $(PROJECT_DIR)/Frameworks/$(PLATFORM_NAME)`

Ручная настройка больше не требуется — `$(PLATFORM_NAME)` автоматически выбирает device vs simulator.

---

## PRO / Free тиры

| Тир | BPM диапазон | dart-define | RevenueCat |
|---|---|---|---|
| Free | 170–230 BPM | — | не нужен |
| PRO (локальный тест) | 155–230 BPM | `FORCE_PRO=true` | не нужен |
| PRO (production) | 155–230 BPM | ключи RevenueCat | нужен |

```sh
# Тест PRO локально (без RevenueCat):
flutter run --dart-define=FORCE_PRO=true

# Production PRO build (с IAP):
flutter build apk --release \
  --dart-define=REVENUECAT_ANDROID_KEY=appl_xxx \
  --dart-define=REVENUECAT_IOS_KEY=appl_xxx
```

---

## Тесты

```sh
# Rust DSP (43 теста)
/opt/homebrew/opt/rust/bin/cargo test --workspace

# Python parity (21 тест)
python3 -m unittest discover core/tests

# Python offline-lab QA (15 синтетических фикстур)
python3 tools/offline-lab/offline_lab.py report

# Flutter widget tests (46 тестов)
cd apps/mobile && flutter test

# Flutter analyze
cd apps/mobile && flutter analyze
```

---

## Структура scripts/

| Скрипт | Назначение |
|---|---|
| `scripts/release.sh` | **Unified release** — android / ios / simulator / clean |
| `scripts/build_android_native.sh` | Rust → `.so` для Android NDK (3 ABI) |
| `scripts/build_ios_native.sh` | Rust → `.a` для iOS (device + simulator) |

---

## Текущие версии (зафиксированы)

| Компонент | Версия |
|---|---|
| Flutter | 3.44.0 |
| Gradle | **8.11.1** (было 9.1.0 → баг) |
| AGP (Android Gradle Plugin) | **8.7.3** (было 9.0.1 → баг) |
| Kotlin | 2.1.21 |
| NDK | 28.2.13676358 |
| JDK | OpenJDK 21 (Android Studio bundled) |
| Target SDK | 36 |
| Min SDK | flutter.minSdkVersion (обычно 21) |

**Не обновляй Gradle до 9.x** — баг с `instrumentation-hierarchy.bin` на cold cache. Жди до тех пор, пока Flutter официально не подтвердит совместимость.
