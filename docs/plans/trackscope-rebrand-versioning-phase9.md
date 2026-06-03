# Plan: TrackScope rebrand + versioning + Phase 9 closure

## 1. Task classification

- complexity: **medium**
- domains: mobile, docs, ui

## 2. Agents

- **@docman** — обновить ROADMAP.md (Phase 9 ЗАВЕРШЕНО), ARCHITECTURE.md (namespace), CLAUDE.md (app name)
- Остальное реализуется напрямую (нет DSP-изменений, нет FFI)

## 3. Files to inspect

```
apps/mobile/pubspec.yaml                                    ← version + name
apps/mobile/android/app/build.gradle.kts                   ← applicationId, namespace, versionCode
apps/mobile/android/app/src/main/res/values/strings.xml    ← app_name
apps/mobile/android/app/src/main/AndroidManifest.xml       ← label reference
apps/mobile/ios/Runner/Info.plist                           ← CFBundleDisplayName, CFBundleName
apps/mobile/android/app/src/main/res/mipmap-*/ic_launcher* ← иконки (заменить)
scripts/build_android_native.sh                             ← проверить корректность
apps/mobile/android/app/src/main/jniLibs/                  ← убедиться что .so заполнены
docs/ROADMAP.md                                             ← Phase 9 статус
CLAUDE.md                                                   ← упоминания trackscope (не менять имя пакета)
```

## 4. Current behavior

- `pubspec.yaml`: `name: hitech_bpm_radar`, `version: 1.0.0+1`
- Android `applicationId`: `dev.hitech.bpmradar.hitech_bpm_radar`
- `strings.xml`: `TrackScope`
- iOS `CFBundleDisplayName`: `TrackScope`
- `jniLibs/` содержит папки arm64-v8a / armeabi-v7a / x86_64 (заполнены после сборки)
- ROADMAP Phase 9 помечена как «В ПРОЦЕССЕ», хотя устройство и эмулятор проверены
- `version: 1.0.0+1` — `+1` это versionCode; каждый APK в RuStore требует уникального (возрастающего) versionCode

## 5. Target behavior

- Отображаемое имя приложения: **TrackScope**
- Dart package name: **trackscope** (или оставить hitech_bpm_radar — см. риски)
- `applicationId`: **dev.trackscope.app** (опционально, если не менять пакет)
- Иконка приложения заменена на новую (radar + waveform, темный фон, зелёный акцент)
- `version: 1.0.0+2` → следующий APK; схема: `X.Y.Z+N` где `N` = versionCode (монотонно растёт)
- ROADMAP Phase 9 → ЗАВЕРШЕНО
- `build_android_native.sh` верифицирован: jniLibs заполнены

## 6. Data contracts

Никаких изменений DSP-контракта. Только метаданные сборки и ресурсы.

## 7. Implementation steps

### Шаг 1 — Верификация Phase 9 (build script + jniLibs)

```bash
ls apps/mobile/android/app/src/main/jniLibs/arm64-v8a/
# Ожидаем: libhitech_bpm_ffi.so
```

Если .so присутствуют — Phase 9 фактически завершена. Обновить ROADMAP.

### Шаг 2 — Иконка приложения

Иконка предоставлена пользователем (PNG 1024×1024, тёмный фон, radar + waveform, зелёный).

Сгенерировать из неё все mipmap-размеры:
- mipmap-mdpi: 48×48
- mipmap-hdpi: 72×72
- mipmap-xhdpi: 96×96
- mipmap-xxhdpi: 144×144
- mipmap-xxxhdpi: 192×192

**Инструмент:** `flutter pub run flutter_launcher_icons` (если добавить пакет) ИЛИ ручная генерация через `sips` (встроен в macOS).

Команда sips для каждого размера:
```bash
sips -z 48 48 icon_src.png --out mipmap-mdpi/ic_launcher.png
sips -z 72 72 icon_src.png --out mipmap-hdpi/ic_launcher.png
# ... и т.д.
```

Также нужен iOS AppIcon.appiconset (множество размеров, Contents.json).

### Шаг 3 — Переименование: отображаемое имя

**Минимальный вариант** (рекомендую): менять только display name, не трогая package name/applicationId.

Причины НЕ менять applicationId:
- Смена applicationId = новое приложение в RuStore/App Store (потеря рейтинга, покупок)
- Dart package name в коде используется только внутри

Изменения:
- `strings.xml`: `TrackScope` → `TrackScope`
- `ios/Runner/Info.plist`: `CFBundleDisplayName` → `TrackScope`
- `pubspec.yaml`: `description:` поле (не name) → описание TrackScope

### Шаг 4 — Схема версионирования

Flutter `pubspec.yaml` `version` format: `X.Y.Z+N`
- `X.Y.Z` = `versionName` (человекочитаемая, для пользователей)
- `N` = `versionCode` (целое число, должно монотонно расти при каждом APK в RuStore)

**Текущий**: `1.0.0+1` → versionCode=1 (уже загружен)

**Следующий APK**: нужно `version: 1.0.0+2` (или `1.1.0+2` если хочется отразить переименование)

**Рекомендуемая схема**:
```
pubspec.yaml:  version: 1.1.0+2
# При каждой сборке для публикации: +N монотонно растёт
# Major.Minor.Patch = смысловые изменения
```

`build.gradle.kts` уже использует `flutter.versionCode` и `flutter.versionName` — читает из pubspec.yaml. Ничего менять в gradle не надо.

### Шаг 5 — Обновить ROADMAP + документацию

- `docs/ROADMAP.md`: Phase 9 → **ЗАВЕРШЕНО** с финальными критериями выхода
- `CLAUDE.md`: упоминание "hitech bpm radar" в заголовке → "TrackScope (trackscope)"

## 8. Tests

```bash
# После замены иконок и переименования:
flutter analyze                          # 0 errors
flutter test                             # все зелёные

# Сборка APK для проверки:
cd apps/mobile && flutter build apk --debug
# → app-debug.apk должен собраться

# Верификация jniLibs:
ls apps/mobile/android/app/src/main/jniLibs/arm64-v8a/libhitech_bpm_ffi.so
```

## 9. Risks

| Риск | Вероятность | Fallback |
|---|---|---|
| sips не умеет adaptive icons (Android 8+) | средняя | Создать ic_launcher_foreground.png + ic_launcher_background.xml отдельно; для базового ic_launcher.png sips достаточно |
| iOS AppIcon.appiconset требует много размеров | низкая | flutter_launcher_icons пакет автоматизирует; или вручную через sips + Contents.json |
| Смена applicationId потребует новой записи в RuStore | высокая | НЕ менять applicationId — только display name |
| versionCode уже = 1 в RuStore | подтверждено | Установить `version: 1.1.0+2` в pubspec.yaml |

## 10. Done when

- [ ] `jniLibs/arm64-v8a/libhitech_bpm_ffi.so` существует (Phase 9 verify)
- [ ] Приложение отображается как «TrackScope» в лаунчере Android/iOS
- [ ] Иконка обновлена во всех mipmap densities
- [ ] `pubspec.yaml` version = `1.1.0+2` (versionCode=2 > предыдущего)
- [ ] `flutter analyze` → 0 errors
- [ ] `flutter test` → все зелёные
- [ ] `flutter build apk --debug` собирается без ошибок
- [ ] ROADMAP Phase 9 → ЗАВЕРШЕНО
- [ ] applicationId НЕ изменён (сохраняет магазинную идентичность)
