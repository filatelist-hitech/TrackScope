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
- ✅ `jniLibs/` заполнен: arm64-v8a, armeabi-v7a, x86_64 (Phase 9 завершено).
- ✅ Display name обновлён: `TrackScope` (strings.xml + Info.plist).
- ✅ Версия обновлена: `1.1.0+2` (pubspec.yaml).
- ⚠️ `key.properties` — создать из шаблона и заполнить пароли перед release-сборкой (не коммитить).
- ⚠️ APK/AAB не публиковались в RuStore — первая публикация предстоит (см. раздел RuStore ниже).

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

---

## Публикация в RuStore: пошаговое руководство

### Подготовка (один раз)

1. **Аккаунт разработчика** — зарегистрируйся на [rustore.ru/developers](https://rustore.ru/developers). Потребуется юридическое лицо или ИП; физлица принимаются через самозанятость.

2. **Подписанный APK или AAB.** Для RuStore рекомендуется AAB:
   ```sh
   cd apps/mobile
   flutter build appbundle --release
   # → build/app/outputs/bundle/release/app-release.aab
   ```
   Тот же `key.properties` и keystore из шага 8 выше.

3. **Иконка приложения:** 512×512 px PNG (без прозрачности — RuStore не принимает PNG с альфа-каналом на главном месте). Подготовь из исходника иконки:
   ```sh
   sips -z 512 512 <source_icon_1024.png> --out rustore_icon_512.png
   ```

4. **Скриншоты:** минимум 2 скриншота (1080×1920 или 1440×2560). Формат PNG или JPG.

5. **Описание:** краткое (до 80 символов) и полное (до 4000 символов) на русском языке.

6. **Политика конфиденциальности:** обязательна для приложений с микрофоном. Загрузить на хостинг и указать URL.

7. **Категория:** «Музыка и аудио».

### Загрузка первого релиза

```
[ ] 1. Войди в RuStore Console → «Мои приложения» → «Добавить приложение».

[ ] 2. Задай applicationId: com.hitech.bpmradar (или текущий — не менять после первой загрузки!).

[ ] 3. Загрузи APK / AAB. RuStore проверит:
       - applicationId
       - versionCode (должен быть > предыдущего; первый = 2)
       - подпись (keystore должен совпадать во всех последующих релизах)

[ ] 4. Заполни метаданные (название TrackScope, описание, скриншоты, иконка 512px).

[ ] 5. Укажи URL политики конфиденциальности.

[ ] 6. Раздел «Разрешения»: объясни, зачем нужен RECORD_AUDIO. Пример:
       "Приложение использует микрофон для анализа аудио и определения темпа музыки в реальном времени."

[ ] 7. Отправь на модерацию. Срок: 1–3 рабочих дня.
```

### Обновление (каждый следующий релиз)

```
[ ] 1. Увеличь версию в pubspec.yaml:
       version: 1.1.0+2  →  version: 1.2.0+3  (или 1.1.1+3 для хотфиксов)
       Правило: +N (versionCode) ОБЯЗАН расти монотонно. Никогда не уменьшать.

[ ] 2. Собери AAB:
       flutter build appbundle --release

[ ] 3. RuStore Console → приложение → «Версии» → «Добавить версию» → загрузи новый AAB.

[ ] 4. Заполни «Что нового» (changelog на русском).

[ ] 5. Отправь на модерацию.
```

### Критичные правила (нарушение = отказ)

- `applicationId` **НИКОГДА не менять** после первой публикации. TrackScope — только display name.
- Keystore файл **хранить в безопасном месте навсегда**. Потеря = невозможность обновлений.
- `versionCode` (`+N` в pubspec) строго возрастает. Пропуски допустимы, откат — нет.
- Каждый релиз с микрофонным разрешением может проходить ручную проверку — готовь скриншоты с работающим детектором.

### Переменная версии

Текущее состояние после Phase 9:
```yaml
# apps/mobile/pubspec.yaml
version: 1.1.0+2
# versionName = 1.1.0 (показывается пользователю)
# versionCode = 2    (проверяется RuStore; первый залитый = 1)
```
