# Plan: v2 Phase 1 UI Wiring

## 1. Task classification

- **complexity:** medium
- **domains:** ui, mobile

---

## 2. Agents

- **@mobileman** — Flutter wiring (AppNavigator, main.dart), FeatureFlags, new SetlistScreen.
- **@qaman** (spot-check) — убедиться, что новые виджет-тесты покрывают SetlistScreen.

DSP, Rust, parity — **не затрагиваются**.

---

## 3. Files to inspect

| Файл | Почему |
|---|---|
| `apps/mobile/lib/monetization/feature_flags.dart` | Добавить `canAccessSetlist` |
| `apps/mobile/lib/features/setlist/setlist_service.dart` | API (уже готов) |
| `apps/mobile/lib/features/setlist/setlist_entry.dart` | CSV/JSON export shape |
| `apps/mobile/lib/main.dart` | `_CapturePipelineState` — добавить ownership |
| `apps/mobile/lib/navigation/app_navigator.dart` | Добавить params + setlist route |
| `apps/mobile/lib/screens/settings_screen.dart` | Добавить onSetlistTap |

---

## 4. Current behavior

- `FeatureFlags` не имеет `canAccessSetlist`.
- `SetlistService` (9 тестов) не инстанциирован в `main.dart`, не подписан на `_bridge.results`.
- `SetlistScreen` не существует — нет файла, нет роута.
- `SettingsScreen` не имеет `onSetlistTap`.

---

## 5. Target behavior

1. **`FeatureFlags.canAccessSetlist`** — `bool get canAccessSetlist => isPro`.
2. **`SetlistScreen`** — Pro-gated push с REC/STOP, таблицей записей, Export CSV + JSON.
3. **`_CapturePipeline` в `main.dart`** — `SetlistService` инстанциирован, подписан на `_bridge.results`, утилизируется в dispose.
4. **`AppNavigator`** — принимает `setlistService`, добавляет `_pushSetlist()`, передаёт в SettingsScreen.
5. **`SettingsScreen`** — строка «Setlist» с Pro-badge + `onSetlistTap`.

---

## 6. Data contracts

### `FeatureFlags` (добавляется)
```dart
bool get canAccessSetlist => isPro;
```

### `AppNavigator` (новые params)
```dart
AppNavigator({
  // existing...
  SetlistService? setlistService,
})
```

### `SettingsScreen` (новый param)
```dart
SettingsScreen({
  // existing...
  VoidCallback? onSetlistTap,
})
```

### `SetlistScreen` (новый экран)
```dart
SetlistScreen({
  required SetlistService service,
  required FeatureFlags flags,
})
```

Изменений в DspResult / Rust FFI — нет.

---

## 7. Implementation steps

1. `FeatureFlags.canAccessSetlist` + тест
2. `SetlistScreen` (новый файл)
3. `SetlistService` ownership в `main.dart`
4. `AppNavigator` params + `_pushSetlist()`
5. `SettingsScreen.onSetlistTap` + строка Setlist

---

## 8. Tests

```sh
flutter test                # все тесты PASS
flutter analyze             # 0 errors
```

---

## 9. Risks

| Риск | Митигация |
|---|---|
| Новые params ломают существующие call-sites | Все новые params — named + nullable |
| `SetlistService` stream subscription leak | `cancel()` в dispose |

---

## 10. Done when

- `flutter analyze` → 0 errors
- `flutter test` → все PASS (baseline 169 + новые)
- `FeatureFlags.canAccessSetlist` существует и тестирован
- `SetlistScreen` рендерится; REC/STOP работают; Free → Paywall
- `SetlistService` подписан на `_bridge.results` в `_CapturePipeline`
- Tap Tempo удалён полностью из кода и документации
