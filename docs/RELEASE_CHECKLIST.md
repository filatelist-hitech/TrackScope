# Релизный чеклист

Статус обновлён 2026-05-30.

## DSP ✅

- ✅ BPM вычисляется из аудио/онсетных данных (параболическая интерполяция, автокорреляция).
- ✅ Уверенность считается из evidence (onset clarity, peak prominence, harmonic support, SNR, stability).
- ✅ Raw- и нормализованные кандидаты сохранены; half/double-time всегда видны.
- ✅ Hitech-нормализация покрыта тестами (100→200, 400→200).
- ✅ Тишина и шум-без-сигнала не дают `STABLE` (проверено на 15/15 синтетических фикстурах).
- ✅ Клиппинг детектируется и подавляет BPM; мягкий клиппинг ограничивает уверенность ниже `STABLE`.
- ✅ Диапазон 155–230 BPM (расширен с 170–230 в Phase 8.2).
- ✅ Re-lock после смены трека ≤ 3 сек (adaptive window + tempo jump detector).
- ✅ Нет `unwrap()` / `expect()` / `println!` в production DSP-коде.

## Mobile — iOS ✅

- ✅ Разрешение микрофона: grant / soft deny / permanent deny + OpenAppSettings.
- ✅ NSMicrophoneUsageDescription задан в Info.plist.
- ✅ Статическая `.a` слинкована через Xcode (`-force_load`).
- ✅ Подтверждён запуск на iPhone 11 (2026-05-26).
- ✅ Flutter не считает BPM (только рендер DSP-контракта).
- ✅ Debug screen показывает кандидатов с relation-метаданными.

## Mobile — Android ⚠️

- ✅ `RECORD_AUDIO` permission в AndroidManifest.xml.
- ✅ `DynamicLibrary.open('libhitech_bpm_ffi.so')` в engine.dart.
- ✅ `build.gradle.kts` настроен на условное подписание через `key.properties`.
- ✅ `scripts/build_android_native.sh` создан (кросс-компиляция Rust → .so для arm64/armv7/x86_64).
- ✅ Rust Android targets добавлены (aarch64, armv7, x86_64).
- ⚠️ `key.properties` не создан — нужно создать из шаблона и сгенерировать keystore.
- ⚠️ Android NDK не установлен — нужно установить через Android Studio SDK Manager.
- ⚠️ `jniLibs/` не заполнен — запустить `bash scripts/build_android_native.sh` после установки NDK.
- ⚠️ APK не собирался и не тестировался на устройстве/эмуляторе — первый запуск предстоит.

## Тесты ✅

- ✅ Синтетические BPM-тесты: 155, 170, 180, 190, 200, 220 BPM — все PASS (±1 BPM).
- ✅ Half-time и double-time ловушки покрыты (raw кандидат виден, normalized побеждает).
- ✅ Тишина, белый шум, розовый шум — `NOISE_ONLY`/`SEARCHING`, никогда не `STABLE`.
- ✅ Клиппинг микрофона (severe + recoverable), брейкдаун, плотный hitech-басс покрыты.
- ✅ 43 Rust-теста (offline_contract + stability + streaming + FFI) — все PASS.
- ✅ 21 Python-тест — PASS.
- ✅ 46 Flutter-тестов (widget + unit) — PASS.
- ✅ Offline-lab CLI: 15/15 фикстур PASS.
- ✅ Parity Python↔Rust: 21/21 реальных фикстур PASS (max Δ 0.40 BPM).
- ✅ `flutter analyze` — 0 ошибок.
- ⚠️ `cargo clippy -- -D warnings` — 3 lint-ошибки в core/dsp/src/lib.rs (строки 403, 1132, 1404).

## Документация ✅

- ✅ Архитектура актуальна (`docs/ARCHITECTURE.md`).
- ✅ DSP-алгоритм актуален (`docs/DSP_ALGORITHM.md`, Phase 8 regression fix).
- ✅ QA-матрица актуальна (21 реальная фикстура, Phase 8.2 аудит).
- ✅ Roadmap актуален (Phase 4–8.2 задокументированы).
- ✅ CHANGELOG актуален.
- ✅ MOBILE_AUDIO.md актуален (iOS pipeline задокументирован).
- ✅ ANDROID_TEST_PLAN.md создан.
- ⚠️ Platform latency table для Android — не измерена (нет физического устройства).

---

## Android Release: пошаговый чеклист

Выполнить последовательно:

```
[ ] 1. Установить Android Studio:
       brew install --cask android-studio

[ ] 2. В SDK Manager установить:
       - Android SDK Platform 35
       - NDK (Side by side) версия 27.x

[ ] 3. Задать переменные окружения (добавить в ~/.zshrc):
       export ANDROID_HOME="$HOME/Library/Android/sdk"
       export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$(ls $ANDROID_HOME/ndk | sort -V | tail -1)"

[ ] 4. Собрать нативные .so файлы:
       bash scripts/build_android_native.sh
       → проверить: ls apps/mobile/android/app/src/main/jniLibs/*/libhitech_bpm_ffi.so

[ ] 5. Собрать debug APK:
       cd apps/mobile && flutter build apk --debug
       → build/app/outputs/flutter-apk/app-debug.apk

[ ] 6. Создать AVD в Android Studio и запустить в эмуляторе:
       flutter emulators --launch <id>
       flutter run --debug

[ ] 7. Приёмочные проверки в эмуляторе:
       - Приложение запускается без краша
       - Permission диалог появляется
       - Silence → SEARCHING/NOISE_ONLY (не STABLE) ← anti-fake check!
       - Debug screen показывает кандидатов

[ ] 8. Создать keystore для release:
       keytool -genkey -v -keystore apps/mobile/android/android-release.jks \
         -keyalg RSA -keysize 2048 -validity 10000 -alias hitech-bpm

[ ] 9. Создать key.properties:
       cp apps/mobile/android/key.properties.template \
          apps/mobile/android/key.properties
       # Заполнить пароли (НЕ коммитить)

[ ] 10. Release APK:
        cd apps/mobile && flutter build apk --release
        → build/app/outputs/flutter-apk/app-release.apk

[ ] 11. Установить release APK на устройство/эмулятор и повторить п.7
```
