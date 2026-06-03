# apps/mobile — TrackScope

Flutter-оболочка мобильного приложения **TrackScope**.

Владеет: разрешениями микрофона, нативным аудио-мостом (FFI → Rust DSP), рендером живого результата, отладочным экраном, историей сессий. **Никакой BPM-математики внутри** — только рендер DSP-контракта.

Dart-пакет: `TrackScope` (pubspec.yaml `name: TrackScope`).

## Текущее состояние (v1.1.0 — Phase 12 + Phase 2.1/2.2/2.3)

### Навигация (`lib/navigation/app_navigator.dart`)

`AppNavigator` через `IndexedStack`: три вкладки — **Радар / История / Настройки**.  
`CaptureBridge` создаётся один раз в `_CapturePipeline` и не пересоздаётся при смене вкладок.

### Radar tab — главный экран (`lib/ui/main_screen.dart`)

| Зона | Flex | Содержимое |
|---|---|---|
| Waveform | 22 % | `WaveformPainter` (осциллограф, ambient glow + beat-reactive pulse, краснеет при клиппинге) |
| Live spectrum | 35 % | `LiveSpectrumPainter` (FFT-кривая log-X, gradient fill, peak hold) |
| Glassmorphism-карточка | 43 % | BPM Hero 72 px · ConfidenceBar 7 px · бейдж Lock State · уровень входа · лучший кандидат · ×½/×2 · клиппинг · шум · **Энергия / Тональность** |

**Zone labels** «WAVEFORM» / «LIVE SPECTRUM» — Flutter-виджеты над панелями.  
**ListeningIndicator** «● слушаю» (accent) при активном захвате.  
**Break button** → `CaptureBridge.resetEngine()` — сброс DSP+smoother без остановки захвата.  
Нет скролла в info-карте; `ЭНЕРГИЯ` и `ТОНАЛЬНОСТЬ` видимы при любом состоянии.

### Design System v2 (`lib/theme/`)

| Токен | Значение |
|---|---|
| Background | `#050807` |
| Accent | `#00DFB0` |
| Font | IBM Plex Mono (через `google_fonts`) |
| ConfidenceBar | 7 px, red < 30 %, yellow 30–70 %, teal > 70 % |
| BPM Hero | 72 px, 3 режима: idle / detecting / unstable |

Дизайн-токены: `lib/theme/app_colors.dart` + `lib/theme/app_text_styles.dart`.  
`AppTheme` (`design_tokens.dart`) — thin-proxy на эти классы.

### Type scale v2.2

| Роль | px |
|---|---|
| micro | 11 |
| caption | 12 |
| title | 13 |
| body | 14 |
| subhead | 15 |
| value | 18 |
| bpmHero | 72 |

### Экраны

- **`MainScreen`** (`lib/ui/main_screen.dart`) — Radar tab (визуализации + info-карта).
- **`SignalAnalyzerScreen`** (`lib/screens/signal_analyzer_screen.dart`) — Pro-only, push из Radar и Settings: BPM-кандидаты со score bar, качество сигнала, тайминги, DspDebug-метрики, **FFT Spectrum** (LiveSpectrumPainter 90 px сверху), секция **ЭНЕРГИЯ**.
- **`HistoryScreen`** (`lib/history/`) — Pro-only (tab), группировка по дням, confidence bar.
- **`SettingsScreen`** (`lib/screens/settings_screen.dart`) — 5 секций, SharedPreferences, WakelockPlus.
- **`PaywallScreen`** (`lib/monetization/paywall_screen.dart`) — FREE / PRO table, CTA, Roadmap card.

### Состояния захвата (метки + цвета)

| `LockState` | Метка | Цвет |
|---|---|---|
| `STABLE` | стабильно | `#00C853` (зелёный) |
| `LOCKING` | захват | `#FFB300` (янтарный) |
| `UNSTABLE` | нестабильно | `#FFB300` (янтарный) |
| `BREAKDOWN` | брейк | `#00DFB0` (accent teal) |
| `CLIPPED_MIC` | перегруз | `#FF4444` (красный) |
| `NOISE_ONLY` | только шум | `#9B59B6` (фиолетовый) |
| `SEARCHING` | поиск | тёмный нейтральный |

### DSP-результат в UI

Radar-экран подписан только на `CaptureBridge.results` (stream `DspResult`).  
`BpmSmoother`: медиана N=5 + EMA confidence α=0.2 + гистерезис STABLE K=3.  
`BpmDisplay`: EMA α=0.2, snap при первом STABLE-кадре. В non-STABLE → «—».

**Новые поля v2:**
- `key_result` → тональность + Camelot (напр. "8A") в Radar info-карте и Signal Analyzer.
- `energy_result` → уровень 1–10 в Radar info-карте и Signal Analyzer.

### Визуализация (`lib/viz/`)

- **`VizController`** (`ChangeNotifier`) — единственный `compute()` за hop питает три потребителя.
- **`WaveformPainter`** — осциллограф: ambient glow (alpha=38, blur=4.0) + beat-reactive pulse.
- **`LiveSpectrumPainter`** — smooth-кривая `quadraticBezierTo`, gradient fill, peak hold decay ×0.90.
- **`SpectrogramPainter`** — скроллящаяся тепловая карта 200×128 бинов (сохранён, не используется на главном экране).
- Все компоненты в `RepaintBoundary`.

### Монетизация (`lib/monetization/`)

| Фича | Free | Pro |
|---|---|---|
| BPM Range | 170–230 | 155–230 + 6 жанров |
| Genre Presets | 3 | 7 + Custom |
| Key / Energy | ✓ | ✓ |
| Signal Analyzer | ✕ → paywall | ✓ |
| History | 30 сек | 24 ч |
| Export CSV/JSON | ✕ → paywall | ✓ |
| Setlist Tracker | ✕ → paywall | ✓ |

RevenueCat API-ключи — через `--dart-define` или `lib/monetization/config.dart` (gitignored).  
Локальный Pro-тест без покупки: `flutter run --dart-define=FORCE_PRO=true`.

## Сборка и тесты

```sh
# Из корня репозитория:
/opt/homebrew/opt/rust/bin/cargo test --workspace   # 116 Rust-тестов
python3 -m unittest discover core/tests
python3 tools/offline-lab/offline_lab.py report

# Из apps/mobile/:
flutter pub get
flutter analyze          # 0 errors
flutter test             # 193/194 pass (1 skip: dsp_engine_test — нет .dylib)
```

## Сборка нативных библиотек

```sh
# Android (.so для 3 ABI):
bash scripts/build_android_native.sh
# → apps/mobile/android/app/src/main/jniLibs/<abi>/libhitech_bpm_ffi.so

# iOS (.a статика):
bash scripts/build_ios_native.sh
# → apps/mobile/ios/Frameworks/libhitech_bpm_ffi.a

# Release APK:
cd apps/mobile && flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk (54.7 MB)
```

## Регенерация FFI-биндингов

`lib/dsp/bindings.dart` закоммичен. Перегенерировать после изменения C-хедера:

```sh
# из apps/mobile/
flutter pub run ffigen --config pubspec.yaml
```

## Известные ограничения

- `dsp_engine_test.dart` требует `libhitech_bpm_ffi.dylib` — пропускается на macOS без него (pre-existing).
- `snr_estimate_db` на чистых синтетических пульсах может оставаться `null` — ожидаемое поведение.
- iOS-симулятор не поддерживает захват микрофона — тестировать на реальном устройстве.
- `BackdropFilter` (glassmorphism card) несёт GPU-стоимость на слабых устройствах.
- `onset_density` в `EnergyAnalyzer` максируется (~400 Hz для всех не-тихих сигналов) — диапазон уровней фактически 3–10 вместо 1–10; планируется fix в Phase 2.2.2.
