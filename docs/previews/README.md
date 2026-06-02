# UI Previews

Скриншоты Phase 1 фич (v1.1 scaffolding).

**Статус устройств на момент scaffolding (2026-06-01):**
- Физическое iOS устройство: недоступно (WiFi-ошибка при подключении).
- iOS Simulator: не запущен (нет конфигурации Simulator).
- Android Emulator: не настроен (Android Studio не установлен).

Скриншоты будут добавлены при следующем запуске на реальном устройстве.

## P1.1 Multi-Genre Presets

| Устройство | Скриншот |
|---|---|
| iOS Physical | — |
| iOS Simulator | — |
| Android Emulator | — |

## P1.2 Setlist Tracker

| Устройство | Скриншот |
|---|---|
| iOS Physical | — |
| iOS Simulator | — |
| Android Emulator | — |

## P1.3 + P1.4 Paywall 2.0

| Устройство | Скриншот |
|---|---|
| iOS Physical | — |
| iOS Simulator | — |
| Android Emulator | — |

## Как получить скриншоты

```bash
# Запустить iOS Simulator
open -a Simulator

# Запустить Android Emulator (после установки Android Studio)
emulator -avd <avd_name> &

# Подключить физическое устройство по USB/WiFi
# (WiFi: убедиться что устройство в Developer Mode)

# Снять скриншоты
flutter screenshot -d "iPhone 16 Pro" -o docs/previews/v2_genre_presets_ios_sim.png
flutter screenshot -d 00008030-0011382E21E0C02E -o docs/previews/v2_genre_presets_ios_physical.png
flutter screenshot -d emulator-5554 -o docs/previews/v2_setlist_android.png
```
