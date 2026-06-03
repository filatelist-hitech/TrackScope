# Plan: Android system insets — tab bar overlapped by system navigation

## 1. Task classification

- **complexity: low**
- **domains: mobile, ui**

Задача low-сложности. Ниже — краткое резюме + шаги имплементации.

---

## Краткое резюме (5 строк)

**Первопричина**: `AppTabBar` (`apps/mobile/lib/widgets/app_tab_bar.dart:32`) имеет хардкодный
`padding: const EdgeInsets.fromLTRB(0, 14, 0, 20)` без учёта `MediaQuery.paddingOf(context).bottom`.
На Android с жестовой/кнопочной навигацией (Flutter 3.44 edge-to-edge) системная полоса перекрывает
таб-бар снизу, скрывая иконки и подписи вкладок.
**Фикс**: одна строка в `app_tab_bar.dart` — заменить константный `EdgeInsets` на динамический с
учётом `MediaQuery.paddingOf(context).bottom`. Дополнительно — проверить pushed-экраны на аналогичный
clipping и поднять версию APK.

---

## 2. Agents

- **@mobileman** — Flutter/FFI граница, Android поведение audio + разрешений; он же понимает edge-to-edge и MediaQuery semantics.
- **@uiman** — виджет `AppTabBar`, Design System v2; Review что токены/отступы согласованы после фикса.
- **@reviewman** — pre-merge gate перед финальной сборкой APK.

DSP/Rust не затронуты; `@dspman` и `@qaman` не нужны.

---

## 3. Files to inspect

| Файл | Причина |
|---|---|
| `apps/mobile/lib/widgets/app_tab_bar.dart` | **PRIMARY BUG** — строка 32, хардкодный bottom padding |
| `apps/mobile/lib/navigation/app_navigator.dart` | Scaffold с `bottomNavigationBar: AppTabBar(...)` — проверить `extendBody` |
| `apps/mobile/lib/history/history_screen.dart` | SafeArea в body — проверить bottom clipping |
| `apps/mobile/lib/screens/signal_analyzer_screen.dart` | Pushed Scaffold без SafeArea — проверить bottom content |
| `apps/mobile/lib/features/setlist/setlist_screen.dart` | Pushed Scaffold без SafeArea — проверить bottom content |
| `apps/mobile/lib/screens/settings_screen.dart` | Scaffold без SafeArea в body — проверить |
| `apps/mobile/android/app/src/main/res/values/styles.xml` | NormalTheme — нет edge-to-edge конфига |
| `apps/mobile/pubspec.yaml` | Версия → bump для RuStore |
| `docs/ROADMAP.md` | Добавить Phase 13: Android insets fix |

---

## 4. Current behavior

```
AppTabBar.build() →
  Container(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 20),  // FIXED bottom
    ...
  )
```

На устройстве из скриншота (3-кнопочная навигация Android, высота системной полосы ≈ 48 dp):
- Tab-bar icons/labels смещены на 28 dp вверх относительно нижнего края системной полосы
- Системная полоса (|||, O, <) рендерится поверх tab-bar
- Лейбл «ИСТОРИЯ» частично перекрыт
- RuStore отклонил сборку 1.1.0(2)

Ещё не проверено: `SignalAnalyzerScreen` и `SetlistScreen` — pushed screens с собственным
`Scaffold(body: Column(...))` без `SafeArea` — могут иметь аналогичный clipping в нижней части.

---

## 5. Target behavior

- Tab-bar иконки и подписи полностью видимы над системной навигацией на любом Android-устройстве
- `AppTabBar` автоматически добавляет `MediaQuery.paddingOf(context).bottom` к нижнему отступу
- Pushed-экраны `SignalAnalyzerScreen` и `SetlistScreen` имеют bottom SafeArea / padding для скроллируемого контента
- `flutter analyze` → 0 ошибок; `flutter test` → все зелёные
- Версия APK поднята; пригодна для повторной подачи в RuStore

---

## 6. Data contracts

Не затронуты:
- `DspResult` — без изменений
- FFI (`core/ffi/`) — без изменений
- Dart DSP-контракт — без изменений

Изменяется только **layout/визуальный слой** — виджет `AppTabBar`.

---

## 7. Implementation steps

### Шаг 1 — Fix `AppTabBar` bottom inset (PRIMARY)

**Файл**: `apps/mobile/lib/widgets/app_tab_bar.dart:32`

```dart
// БЫЛО:
padding: const EdgeInsets.fromLTRB(0, 14, 0, 20),

// СТАЛО:
padding: EdgeInsets.fromLTRB(0, 14, 0, 20 + MediaQuery.paddingOf(context).bottom),
```

Убедиться, что `build(BuildContext context)` использует `context` для `MediaQuery`.
Метод `build` уже принимает `context` — дополнительного рефакторинга не нужно.

**Тест после шага 1**:
```sh
flutter test
flutter analyze
```

### Шаг 2 — Verify + fix pushed screens

Проверить `SignalAnalyzerScreen` и `SetlistScreen`:
- Оба имеют `Scaffold(appBar: AppBar(...), body: Column(...))` — AppBar закрывает top inset.
- Bottom inset: pushed screens не имеют `bottomNavigationBar`, значит Flutter НЕ убирает
  `MediaQuery.padding.bottom` из body. Если последний элемент скроллируемого списка достигает
  края экрана — он будет перекрыт системной полосой.
- Добавить `bottom: MediaQuery.paddingOf(context).bottom` к последнему padding в скроллируемом
  контенте ИЛИ обернуть scrollable в `SafeArea(top: false)`.

**Тест после шага 2**:
```sh
flutter test
flutter analyze
```

### Шаг 3 — Bump версия для RuStore

**Файл**: `apps/mobile/pubspec.yaml`

```yaml
# БЫЛО:
version: 1.1.0+2

# СТАЛО:
version: 1.2.0+3
```

Правило RuStore: повторная подача требует поднятого `versionCode` (+3) и `versionName` (1.2.0).

**Тест после шага 3**:
```sh
flutter test
```

### Шаг 4 — Обновить документацию

- `docs/ROADMAP.md` — добавить Phase 13: Android insets + version bump.
- `docs/plans/android-system-insets-tab-bar.md` — пометить выполненным.

---

## 8. Tests

| Тест | Команда | Ожидаемый результат |
|---|---|---|
| Dart/Flutter unit + widget | `flutter test` | Все PASS |
| Статический анализ | `flutter analyze` | 0 errors |
| Rust (нет изменений, sanity) | `/opt/homebrew/opt/rust/bin/cargo test --workspace` | Все PASS |
| Offline QA (sanity) | `python3 tools/offline-lab/offline_lab.py report` | Exit 0 |

Ручная верификация (после `flutter build apk --release`):
- Установить APK на Android-устройство с 3-кнопочной навигацией
- Убедиться, что таб-бар полностью виден над системной полосой
- Проверить все три вкладки (Радар / История / Настройки)
- Проверить открытие Signal Analyzer и Setlist — нет отрезанного контента снизу

---

## 9. Risks

| Риск | Вероятность | Mitigation |
|---|---|---|
| На устройствах без системной полосы (gesture nav) `bottomInset=0` → нет регрессии | Н/А | `MediaQuery.paddingOf(context).bottom` = 0 в этом случае, поведение идентично текущему |
| Слишком большой отступ снизу (tall nav bar device) → пустое место под tab-bar | Низкая | `bottom: 20 + inset` — 20px это оригинальный дизайнерский отступ, inset сверху |
| Тесты, которые мокируют `MediaQuery` без `bottom`, начнут падать | Очень низкая | `MediaQuery.paddingOf` fallback = `EdgeInsets.zero` → bottom=0, тест не сломается |
| `pubspec.yaml` version bump — несоответствие Play Store / App Store | Низкая | Bump только для Android (RuStore); iOS build не меняется |

---

## 10. Done when

- [ ] `flutter analyze` → 0 errors
- [ ] `flutter test` → все PASS (не меньше прежнего количества)
- [ ] `/opt/homebrew/opt/rust/bin/cargo test --workspace` → все PASS
- [ ] `python3 tools/offline-lab/offline_lab.py report` → exit 0
- [ ] `AppTabBar` использует `MediaQuery.paddingOf(context).bottom` в bottom padding
- [ ] `apps/mobile/pubspec.yaml` version поднята до `1.2.0+3`
- [ ] На Android с 3-кнопочной навигацией таб-бар полностью виден (ручной тест или скриншот)
- [ ] `docs/ROADMAP.md` обновлён с Phase 13
- [ ] Anti-fake инварианты не нарушены: нет хардкода BPM, нет демо-значений, нет STABLE без evidence
