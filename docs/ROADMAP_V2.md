# TrackScope — v2 Roadmap

## Vision

«Стать стандартным companion-приложением для psy-DJ: realtime BPM + harmonic mixing (Camelot) + energy arc + setlist logging — всё on-device, 100% offline.»

---

## Competitive Positioning

| Функция | **TrackScope** | liveBPM | Mixed In Key | Tunebat | KeyMatch |
|---|---|---|---|---|---|
| Realtime BPM (микрофон) | ✅ | ✅ | ❌ (файлы) | ❌ (файлы) | ❌ |
| Psy-optimized (155–230) | ✅ | Частично | ❌ | ❌ | ❌ |
| Key detection | ✅ realtime | ❌ | ✅ (офлайн) | ✅ (офлайн) | ✅ |
| Realtime key (live mic) | ✅ realtime | ❌ | ❌ | ❌ | ❌ |
| Energy level | ✅ realtime | ❌ | ✅ (офлайн) | ❌ | ❌ |
| Setlist tracker | ✅ | ❌ | ❌ | ❌ | ❌ |
| 100% offline / on-device | ✅ | ✅ | ✅ | ❌ | ❌ |
| Mobile (iOS + Android) | ✅ | ✅ | ❌ (desktop) | ❌ (web) | iOS только |
| Multi-genre presets | ✅ | ❌ | ❌ | ❌ | ❌ |
| Apple Watch | 🔜 v2 | ❌ | ❌ | ❌ | ❌ |

**Ключевое конкурентное преимущество:** единственное приложение, совмещающее realtime BPM-захват (оптимизированный под hitech/psy) с планируемым realtime Camelot key detection — всё через микрофон, без загрузки файлов.

---

## Phase 1 — Quick Wins (v1.1, ~2 недели)

### P1.1 Multi-Genre BPM Presets

| | |
|---|---|
| **Описание** | 7 жанровых пресетов с разными BPM-диапазонами и порогами нормализации |
| **Ценность** | DnB/Techno DJ не хочет получать range 155–230; каждый жанр имеет свои half/double пороги |
| **Tier** | Free: HitechPsy + Psytrance + Darkpsy; Pro: всё + Custom(min, max) |
| **Сложность** | M (Rust enum + Flutter picker) |
| **Домен** | DSP + Flutter |
| **Статус** | ✅ реализовано (`core/dsp/src/genre_preset.rs` + Dart picker) |

Пресеты: HitechPsy (155–230), Psytrance (130–160), Darkpsy (145–180), DrumAndBass (160–185), Techno (125–145), Hardstyle (138–160), Hardcore (155–185), Custom (Pro).

### P1.2 Setlist Tracker MVP

| | |
|---|---|
| **Описание** | Запись BPM-снапшотов во время сета с экспортом CSV/JSON |
| **Ценность** | DJ может после сета проанализировать BPM-кривую своего выступления |
| **Tier** | Pro |
| **Сложность** | M (Flutter + существующий export) |
| **Домен** | Flutter |
| **Статус** | ✅ реализовано (`lib/features/setlist/`) |

Дедупликация: новая запись только при delta BPM > 0.5 или delta time > 5 сек. Phase 2: добавить `camelotKey` и `energyLevel`.

### P1.3 14-Day Pro Trial

| | |
|---|---|
| **Описание** | 14-дневный бесплатный триал на Annual подписке ($3.99/yr) |
| **Ценность** | Конверсия 42.5% при triал 17–32 дней (RevenueCat 2026 данные) |
| **Tier** | — (механика монетизации) |
| **Сложность** | S (RevenueCat Dashboard + UI badge) |
| **Домен** | Flutter / монетизация |
| **Статус** | ✅ реализовано (PaywallScreen обновлён) |

Бейдж «14 дней бесплатно» в Annual кнопке. Конфигурация trial — в RevenueCat Dashboard (не в коде).

### P1.4 Paywall 2.0: Coming Soon v2

| | |
|---|---|
| **Описание** | Обновлённая таблица сравнения с v2 фичами (10 строк) |
| **Ценность** | Показывает roadmap при апселле → снижает отток пользователей, ожидающих v2 |
| **Tier** | — |
| **Сложность** | S |
| **Домен** | Flutter |
| **Статус** | ✅ реализовано |

Новые «Скоро»-строки: Key + Camelot, Energy Level, Apple Watch, Lock-screen Widget.

---

## Phase 2 — Harmonic Analysis (v2.0, ~2 месяца)

### P2.1 Real-time Key Detection (HPCP + Krumhansl-Schmuckler) — **✅ ЗАВЕРШЕНО** (Phase 2.1, 2026-06-02)

**`core/dsp/src/key_analyzer.rs`** — полная реализация в Rust DSP-движке.

Алгоритм:
1. STFT-фреймы (4096 / hop 2048) → 12-bin HPCP (50–5000 Hz, C4 = 261.63 Hz).
2. Скользящий HPCP-аккумулятор `KEY_WINDOW_SECS = 8.0 с`.
3. Корреляция Пирсона с 24 Krumhansl-Schmuckler профилями (12 мажор + 12 минор).
4. `KeyResult { key, camelot, confidence }` → Dart-слой, Signal Analyzer + Radar info-карта.

Гейты: тишина / CLIPPED_MIC / confidence < 0.25 / batch-путь → `key_result = None`.
Camelot: A minor = "8A", C major = "8B". 12 Rust-тестов PASS. **Tier:** Pro.

### P2.2 Camelot Wheel UI

Визуализация Camelot-колеса — **запланировано** (v2.1).

### P2.3 Energy Level 1–10 — **✅ ЗАВЕРШЕНО** (Phase 2.2, 2026-06-02)

**`core/dsp/src/energy_analyzer.rs`** — полная реализация в Rust DSP-движке.

RMS (40%) + spectral flux (35%) + onset density (25%) → `ceil(sum × 10).clamp(1, 10)`.
Гейты: CLIPPED_MIC / тишина → `energy_result = None`.
Signal Analyzer: секция «ЭНЕРГИЯ N / 10» + прогресс-бар. Radar tab: строка «ЭНЕРГИЯ / ТОНАЛЬНОСТЬ». 5 Rust-тестов PASS. **Tier:** Pro.

### P2.4 Setlist Tracker Full

Добавить `camelotKey` и `energyLevel` в `SetlistEntry`. Экспорт расширяется автоматически. Pro.

### P2.5 Apple Watch / WearOS

watchOS Extension: live BPM + Camelot на запястье без телефона (вибрация при захвате). WearOS companion app. Pro.

### P2.6 Share «Set Energy Card»

Генератор карточки сета: BPM-кривая + ключи + энергетический arc. Готова к публикации в Instagram/TG. Pro.

### P2.7 Revised Pricing Strategy

По итогам RevenueCat 2026: рассмотреть hard paywall (10.7% конверсия vs 2.1% freemium) после v2 launch. Текущая модель остаётся до набора DAU.

---

## Phase 3 — Intelligence (v3.0, ~6 месяцев)

### P3.1 Psy Subgenre Detection

Автоматическое определение субжанра: hitech, darkpsy, forest, full-on, progressive. Комбинация BPM-диапазона + спектрального profiling + энергии. Pro.

### P3.2 Ektoplazm Dataset Integration

Партнёрство с Ektoplazm для расширения тестовой базы из лицензированных треков. QA-матрица из 500+ треков.

### P3.3 SDK/API Licensing (B2B)

Лицензирование DSP-ядра (Rust crate) для профессионального DJ-оборудования, стриминговых платформ. Revenue stream от B2B.

### P3.4 Shazam-for-Hitech

Audio fingerprinting для hitech/psy треков: «что сейчас играет?». Долгосрочный план: требует fingerprint-базы. Рассмотреть после P3.2.

---

## Metrics & Success Criteria

| Метрика | Текущее | v1.1 цель | v2.0 цель |
|---|---|---|---|
| Pro-конверсия | ~2–3% | 5% (+trial) | 8–10% (+key/energy) |
| Monthly DAU | — | 500 | 2000 |
| App Store Rating | — | ≥4.5 | ≥4.7 |
| Crash-free rate | — | >99.5% | >99.5% |
| First lock time (clean) | ≤6 сек | ≤6 сек | ≤4 сек |

---

## What We Are NOT Building

- **Реклама** — privacy-first; никакого трекинга и рекламы.
- **Social feed** — не social app; focus на utility.
- **Streaming integration** (Spotify/Apple Music) — не анализируем файлы; только live mic.
- **Cloud BPM history** — все данные on-device.
- **ML-модели** — детерминированный DSP обеспечивает объяснимость и предсказуемый CPU.
- **Tap-tempo как основной механизм** — DSP-first; tap-tempo только как вспомогательный инструмент.
