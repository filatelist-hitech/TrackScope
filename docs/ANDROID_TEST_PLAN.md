# Android тест-план

Тест-план для проверки trackscope на Android — с физическим устройством и без него (эмулятор AVD).

## Предварительные требования

1. `scripts/build_android_native.sh` выполнен → `jniLibs/arm64-v8a/libhitech_bpm_ffi.so` существует.
2. `flutter build apk --debug` завершился без ошибок.
3. Android Studio установлен (для AVD Manager).

---

## Часть 1: Тестирование в эмуляторе (без физического устройства)

### 1.1 Создать AVD

**Через Android Studio (рекомендуется):**
```
Android Studio → More Actions → Virtual Device Manager → Create Device
  Device: Pixel 7
  System Image: API 35, ABI: arm64-v8a (на Apple Silicon Mac)
  Имя: pixel_7_api35
```

**Через командную строку:**
```sh
# Посмотреть доступные образы
sdkmanager --list | grep "system-images;android-35;google_apis;arm64-v8a"

# Установить образ
sdkmanager "system-images;android-35;google_apis;arm64-v8a"

# Создать AVD
avdmanager create avd -n pixel_7_api35 \
  -k "system-images;android-35;google_apis;arm64-v8a" \
  -d "pixel_7"
```

### 1.2 Запустить эмулятор и установить APK

```sh
# Посмотреть доступные эмуляторы
flutter emulators

# Запустить эмулятор
flutter emulators --launch pixel_7_api35

# Подождать ~30 секунд, затем запустить приложение
cd apps/mobile
flutter run --debug
```

### 1.3 Сценарии приёмки в эмуляторе

| # | Сценарий | Ожидаемый результат | Anti-fake проверка |
|---|---|---|---|
| 1 | Запуск приложения | Экран BPM показывает `—` и badge «поиск» | `primary_bpm == null` на старте |
| 2 | Запрос разрешения микрофона | Системный диалог появляется | Без разрешения → `PermissionDeniedScreen` |
| 3 | Выдать разрешение | Приложение переходит к захвату | |
| 4 | Тишина в эмуляторе | `SEARCHING` или `NOISE_ONLY`, BPM = `—` | Никакого `STABLE` без сигнала ✓ |
| 5 | Открыть Debug screen | Список кандидатов виден | half_time/double_time кандидаты в списке |
| 6 | Отказать в разрешении | `PermissionDeniedScreen` с кнопкой «Открыть настройки» | |
| 7 | Повернуть устройство | Приложение не крашится, состояние сохраняется | |
| 8 | Свернуть и развернуть | Захват микрофона возобновляется | |

### 1.4 Ограничения эмулятора

- Виртуальный микрофон AVD получает звук с хоста Mac **только если** при запуске эмулятора задана опция `-audio none` не задана. По умолчанию аудио-вход проброшен через хост.
- Но качество захвата в AVD низкое: детектор, скорее всего, будет в `SEARCHING` / `NOISE_ONLY` без реального музыкального сигнала — это **ожидаемое поведение**, не баг.
- Для теста реального детектирования BPM нужно физическое Android-устройство.

---

## Часть 2: Аудио-инъекция через ADB (опциональный тест DSP без устройства)

AVD поддерживает виртуальный аудио-вход. Можно подать синтетический PCM-файл через ADB:

```sh
# Сгенерировать тестовый 200 BPM WAV (Python, 10 секунд)
python3 -c "
import wave, struct, math, array
sr = 44100
dur = 10
bpm = 200
spb = int(sr * 60 / bpm)
samples = []
for i in range(sr * dur):
    v = int(32767 * math.sin(2 * math.pi * 440 * i / sr))
    if i % spb < int(spb * 0.05):
        v = 32767
    samples.append(v)
with wave.open('/tmp/test_200bpm.wav', 'w') as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr)
    f.writeframes(array.array('h', samples).tobytes())
print('OK')
"

# Push файл на эмулятор и воспроизвести
adb push /tmp/test_200bpm.wav /sdcard/test_200bpm.wav

# Эмулятор → Settings → Sound → поставить файл как рингтон / использовать медиаплеер
# Это не прямая инъекция в микрофон, но проверяет что DSP работает
```

**Прямая инъекция в микрофон эмулятора** доступна через QEMU audio pipe, но сложна в настройке. Проще протестировать на физическом устройстве.

---

## Часть 3: Тестирование на физическом Android-устройстве

Как только появится Android-устройство:

### 3.1 Подключение

```sh
# Включить Developer Options на устройстве:
# Settings → About Phone → Build Number (нажать 7 раз)
# Settings → Developer Options → USB Debugging → On

# Подключить USB кабель к Mac, выбрать "Allow" на устройстве
adb devices  # должен показать device

# Запустить
cd apps/mobile && flutter run --release
```

### 3.2 Сценарии приёмки на реальном устройстве

| # | Сценарий | Ожидаемый результат | Критерий приёмки |
|---|---|---|---|
| 1 | Тишина (устройство в тихой комнате) | `SEARCHING` / `NOISE_ONLY`, BPM = `—` | Никогда не `STABLE` ✓ |
| 2 | Белый шум (онлайн генератор) | `NOISE_ONLY` | confidence < 0.5 |
| 3 | Hitech трек 180–220 BPM с колонки | `LOCKING` → `STABLE` ≤ 12 сек | BPM ±4 от реального |
| 4 | Тот же трек на расстоянии ~30 см | `STABLE`, BPM ±2–4 | Phase 4 target |
| 5 | Рука перекрывает микрофон | `CLIPPED_MIC` или `NOISE_ONLY` | |
| 6 | Трек → пауза (брейкдаун) | Выход из `STABLE` | confidence падает |
| 7 | Half-time трек (100 BPM) | Кандидат 200 BPM с `normalized_from_half` | raw 100 виден в debug |
| 8 | Переключить трек (другой BPM) | Re-lock ≤ 3 секунды | Phase 4 требование |

### 3.3 Release APK на реальном устройстве

```sh
# Подписанный release APK
cd apps/mobile
flutter build apk --release

# Установить вручную
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## Часть 4: Чеклист перед финальным APK

```
[ ] bash scripts/build_android_native.sh  → jniLibs/*.so созданы
[ ] flutter analyze                        → 0 ошибок  
[ ] flutter test                           → все тесты PASS
[ ] cargo test --workspace                 → все тесты PASS
[ ] flutter build apk --debug             → app-debug.apk создан
[ ] app-debug.apk запускается в AVD
[ ] Permission flow работает (grant / deny)
[ ] Silence в AVD → SEARCHING/NOISE_ONLY (не STABLE)
[ ] Debug screen показывает кандидатов
[ ] flutter build apk --release           → app-release.apk создан (нужен key.properties)
[ ] app-release.apk подписан (не debug-ключом)
```

---

## Типичные ошибки и решения

### ❌ `NDK at ... did not have a source.properties file`

**Причина:** NDK распакован с лишним уровнем вложенности (`ndk/28.x/android-ndk-r28c/` вместо `ndk/28.x/`).

**Решение:**
```sh
NDK_VERSION="28.2.13676358"  # замени на свою версию
NDK_DIR="$HOME/Library/Android/sdk/ndk/$NDK_VERSION"

# Переместить содержимое вложенной папки на уровень выше
mv "$NDK_DIR"/android-ndk-r28c/* "$NDK_DIR/"
rmdir "$NDK_DIR/android-ndk-r28c"

# Проверить
cat "$NDK_DIR/source.properties"
```

Обновить `ANDROID_NDK_HOME`:
```sh
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/28.2.13676358"  # без подпапки
```

---

### ❌ `TLS handshake failed` / Maven download error при Gradle build

**Причина:** Gradle запускается с Java 1.8 (`/usr/bin/java`). Gradle 9.x требует Java 17+.

**Решение:** Добавить в `~/.zshrc`:
```sh
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
```

Проверить: `$JAVA_HOME/bin/java -version` → должна быть 17+ или 21.

Зафиксировать для Flutter: `flutter config --jdk-dir="$JAVA_HOME"`

---

### ❌ `Cannot lock execution history cache` (Gradle daemon lock)

**Причина:** Предыдущий упавший build оставил файловый лок. Часто возникает при смене JDK.

**Решение:**
```sh
pkill -f "gradle" 2>/dev/null
rm -f apps/mobile/android/.gradle/9.1.0/executionHistory/*.lock 2>/dev/null
# Повторить сборку
flutter build apk --debug
```

---

### ❌ `NoSuchFileException: gradle-1.0.0.jar` при `flutter run`

**Причина:** Gradle transform cache повреждён (частичная загрузка Flutter plugin jar).

**Решение:** Очистить transform cache:
```sh
rm -rf ~/.gradle/caches/9.1.0/transforms/
# Повторить flutter run — Gradle перекачает и перекеширует jar
```

---

## Известные ограничения

- AVD не воспроизводит реальный BPM-детектор полноценно — только функциональные тесты (запуск, разрешения, UI, anti-fake silence check).
- Для production-проверки точности ±2–4 BPM нужно физическое устройство с живым аудио.
- `package:record` на Android требует `minSdk ≥ 21`; текущая конфигурация использует `flutter.minSdkVersion` (обычно 21).
- На некоторых Android-устройствах задержка аудио-буфера выше, чем на iOS (40–120 мс vs 10–30 мс) — это влияет на время первого захвата.
