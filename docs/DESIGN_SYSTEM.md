# Design System v2.1 — trackscope

Verified on 2026-06-02. Источник истины — файлы в `apps/mobile/lib/theme/`.

---

## 1. Принципы

**DSP-first.** UI только рендерит `DspResult`, полученный от Rust DSP-ядра. Никакой BPM-математики в Dart-коде. Все BPM-числа, уверенность и состояния захвата поступают из `DspResult` через `CaptureBridge`.

**Dark-only тема.** Светлого режима нет и не планируется. Фоны — глубокий почти-чёрный с зелёным подтоном.

**Единственный шрифт — IBM Plex Mono.** Весь текст в приложении: числа, метки, кнопки, заголовки. Никаких `GoogleFonts.ibmPlexMono()` вне `AppTextStyles`.

**Токены обязательны.** Все цвета — через `AppColors`, все стили текста — через `AppTextStyles`, все отступы и радиусы — через `AppSpacing`. Магические числа в виджетах недопустимы.

---

## 2. Цвета (Color tokens)

Источник: `apps/mobile/lib/theme/app_colors.dart`

### Фоны

| Token | Hex | Использование |
|---|---|---|
| `AppColors.background` | `#050807` | Фон всех экранов |
| `AppColors.surface` | `#0C1410` | Карточки, группы (sa-grp, s-grp) |
| `AppColors.surface2` | `#0D1712` | Вложенные карточки (history-grp) |

### Акцент

| Token | Hex | Использование |
|---|---|---|
| `AppColors.accent` | `#00DFB0` | BPM hero STABLE, confidence >70%, активные элементы |
| `AppColors.accentDim` | `#00DFB0` 10% alpha | Glow-подложки, лёгкие заливки |

### Семантические цвета

| Token | Hex | Использование |
|---|---|---|
| `AppColors.amber` | `#C8A020` | Границы/фон UNSTABLE |
| `AppColors.amberText` | `#FFE090` | Текст BPM в состоянии UNSTABLE |
| `AppColors.amberBg` | `#C8A020` 12% alpha | Заливка badge UNSTABLE |
| `AppColors.danger` | `#E04040` | Confidence <30%, клиппинг |
| `AppColors.yellow` | `#E0B020` | Confidence 30–70% |

### Текст

| Token | Hex | Использование |
|---|---|---|
| `AppColors.textPrimary` | `#C8DCD8` | Основной читаемый текст |
| `AppColors.textSecondary` | `#3A6858` | Значения stats, body-текст |
| `AppColors.textMuted` | `#1A3028` | Метки, zone labels, вспомогательный текст |

### Границы и пустые состояния

| Token | Hex | Использование |
|---|---|---|
| `AppColors.border` | `#182820` | Внешние границы карточек |
| `AppColors.borderFaint` | `#0F1712` | Делители внутри групп |
| `AppColors.bpmEmpty` | `#1E3530` | Текст `— — —` до первого захвата |

### Динамические хелперы

`AppColors.confidence(double pct)` — возвращает цвет по порогам уверенности:
- `pct < 30` → `danger` (#E04040)
- `30 ≤ pct < 70` → `yellow` (#E0B020)
- `pct ≥ 70` → `accent` (#00DFB0)

`AppColors.bpmText({required bool hasValue, required bool isUnstable})` — цвет BPM-числа:
- нет значения → `bpmEmpty`
- нестабильно → `amberText`
- иначе → `accent`

---

## 3. Типографика (Type scale)

Источник: `apps/mobile/lib/theme/app_text_styles.dart`

Все стили строятся через `AppTextStyles.mono(size, weight, color)`. Никаких inline `GoogleFonts.ibmPlexMono()`.

### Размерные константы

| Константа | px | Назначение |
|---|---|---|
| `szMicro` | 9 | Zone labels, section headers |
| `szCaption` | 10 | Метки, listening indicator, временны́е метки |
| `szBody` | 12 | Settings rows, stats labels, body-текст |
| `szTitle` | 11 | AppBar subtitle, feature list |
| `szSubhead` | 13 | Signal Analyzer: заголовки метрик |
| `szValue` | 15 | Числовые значения в info card |

### Именованные роли

| Роль | Размер | Weight | Цвет | Flutter-вызов | Использование |
|---|---|---|---|---|---|
| `bpmHero` | 72 px | w600 | accent | `AppTextStyles.bpmHero` | BPM-число в STABLE |
| `bpmHeroWith(color)` | 72 px | w600 | произвольный | `AppTextStyles.bpmHeroWith(c)` | BPM в UNSTABLE (amberText) |
| `bpmEmptyHero` | 58 px | w600 | bpmEmpty | `AppTextStyles.bpmEmptyHero` | `— — —` до захвата |
| `navTitle` | 10 px | w400 | `#7AB8AA` | `AppTextStyles.navTitle` | AppBar letter-spacing 3.0 |
| `sectionLabel` | 9 px | w400 | textMuted | `AppTextStyles.sectionLabel` | Zone labels над панелями |
| `statsValue` | 15 px | w400 | textSecondary | `AppTextStyles.statsValue` | Числа в info card |
| `statsLabel` | 10 px | w400 | textMuted | `AppTextStyles.statsLabel` | Метки под/над значениями |
| `bodyRow` | 12 px | w400 | textSecondary | `AppTextStyles.bodyRow` | Settings rows, body-текст |
| `ctaButton` | 10 px | w600 | Colors.black | `AppTextStyles.ctaButton` | Paywall primary CTA |
| `caption` | 10 px | w400 | textMuted | `AppTextStyles.caption` | Meta-текст |

Letter-spacing BPM hero: −2.5 (bpmHero), −1.5 (bpmEmptyHero).

---

## 4. Отступы (Spacing)

Источник: `apps/mobile/lib/theme/app_spacing.dart`

### Базовые единицы

| Константа | px | Использование |
|---|---|---|
| `AppSpacing.xs` | 4 | Атомарный минимальный gap |
| `AppSpacing.sm` | 8 | Gap между связанными элементами |
| `AppSpacing.md` | 14 | Стандартный gap (stats grid, section gaps) |
| `AppSpacing.lg` | 20 | Section padding, top-level spacing |
| `AppSpacing.xl` | 32 | Page bottom padding, крупные разрывы |

### Layout

| Константа | Значение | Использование |
|---|---|---|
| `AppSpacing.pagePad` | 14 px | Горизонтальный инсет страниц |
| `AppSpacing.cardRadius` | 13 px | Corner radius: sa-grp, hist-grp, s-grp |
| `AppSpacing.chipRadius` | 7 px | Corner radius: chips, badges |
| `AppSpacing.rowPad` | `symmetric(h:14, v:11)` | Внутренний padding строк в group card |
| `AppSpacing.zoneLabelPad` | `LTRB(2, 6, 2, 2)` | Padding zone label над viz-панелями |
| `AppSpacing.sectionHeaderPad` | `LTRB(20, 14, 20, 4)` | Padding section header вне карточек |

### Специальные константы

| Константа | Значение | Использование |
|---|---|---|
| `AppSpacing.confBarHeight` | 7 px | Confidence bar на главном экране Radar |
| `AppSpacing.confBarHeightCompact` | 3 px | Compact bars: History, Signal Analyzer |
| `AppSpacing.statCellGap` | 18 px | Gap между 2-колоночными stat cells |

### Делители

`AppDivider.inGroup` — `#080C09` — делитель между строками внутри group card.
```dart
Divider(height: 1, thickness: 1, color: AppDivider.inGroup)
```

---

## 5. Компоненты (Component rules)

### Group card (sa-grp / s-grp / hist-grp)

Контейнер для группы связанных настроек или данных.

- Фон: `AppColors.surface` (#0C1410) — sa-grp/s-grp; `AppColors.surface2` (#0D1712) — hist-grp.
- Border radius: `AppSpacing.cardRadius` (13 px).
- Между строками: `AppDivider.inGroup` (height: 1, thickness: 1).
- Padding каждой строки: `AppSpacing.rowPad`.
- Когда использовать: группировка ≥2 связанных настроек или элементов истории в одном блоке.

### Section header (s-hdr)

Текстовый заголовок секции — снаружи карточек, не внутри них.

- Стиль: `AppTextStyles.sectionLabel` (9 px, textMuted, letterSpacing 1.4).
- Padding: `AppSpacing.sectionHeaderPad` — `LTRB(20, 14, 20, 4)`.
- Текст — UPPER CASE.

### Zone labels

Метки над viz-панелями (WAVEFORM, LIVE SPECTRUM).

- Стиль: `AppTextStyles.sectionLabel`.
- Padding: `AppSpacing.zoneLabelPad` — `LTRB(2, 6, 2, 2)`.
- Реализуются как Flutter-виджеты (`Text`), НЕ через `canvas.drawText` в painter'е.

### Confidence bar

Горизонтальная полоса уверенности.

| Параметр | Значение |
|---|---|
| Высота (Radar) | `AppSpacing.confBarHeight` = 7 px |
| Высота (compact) | `AppSpacing.confBarHeightCompact` = 3 px |
| Corner radius | 4 px |
| Цвет заливки | `AppColors.confidence(pct)` |
| Фон трека | `#111916` |
| Порог red | pct < 30 → `danger` (#E04040) |
| Порог yellow | 30 ≤ pct < 70 → `yellow` (#E0B020) |
| Порог teal | pct ≥ 70 → `accent` (#00DFB0) |

Рядом с полосой — текст процента в том же цвете, что и заливка.

### Mode chips (IDLE / ACTIVE / UNSTABLE)

Небольшой бейдж состояния рядом с BPM.

- Corner radius: `AppSpacing.chipRadius` (7 px).
- IDLE: текст textMuted, фон borderFaint.
- ACTIVE (STABLE/LOCKING): текст accent, фон accentDim.
- UNSTABLE: текст amberText, фон amberBg.
- Смена состояния — через `AnimatedSwitcher` с `ValueKey<LockState>`.

### Stat cells (2-column grid)

Пары label/value в info card.

- Layout: 2 колонки с gap `AppSpacing.statCellGap` (18 px).
- Label: `AppTextStyles.statsLabel` (10 px, textMuted, letterSpacing 1.0).
- Value: `AppTextStyles.statsValue` (15 px, textSecondary).
- Данные всегда из `DspResult` — не вычислять в виджете.

---

## 6. Правила painter'ов

### WaveformColumnPainter

Источник: `apps/mobile/lib/viz/waveform_painter.dart`

- Каждая колонка — прямоугольник `drawRect` (3 px ширина, 0.5 px gap). Никакого `Path`, никакого `MaskFilter` в штатном пути.
- Цвет колонки интерполируется между `#003D35` (тихие/высокочастотные) и `#00E5CC` (kick/bass-heavy) на основе `WaveformColumn.bassEnergy`.
- **Beat-reactive glow:** параметр `glowIntensity` в диапазоне [0, 1] управляет интенсивностью glow-прохода. Источник — `VizController.beatDecay`. Значение 0.0 означает отсутствие glow.
- Референсная сетка: горизонтальная центральная линия (`#22FFFFFF`), временны́е метки `−5s`/`−2.5s` (`#44AADDCC`), курсор `NOW →` у правого края.
- `shouldRepaint` использует идентичность списка — репейнт только при реальных изменениях данных.
- `RepaintBoundary` устанавливается родительским виджетом `_WaveformView`, не самим painter'ом.
- **Подписи зон (WAVEFORM) — не в canvas.** Только Flutter `Text`-виджеты снаружи painter'а.

### LiveSpectrumPainter

- Спектральная кривая FFT с gradient fill: заливка от x=0 до x=width (полная ширина холста).
- Логарифмическая X-ось: 20–20 000 Гц.
- Peak-hold decay: ×0.90 за кадр.
- **Подписи зон (LIVE SPECTRUM) — не в canvas.** Только Flutter `Text`-виджеты снаружи painter'а.

### Общие правила для всех painter'ов

- Canvas-подписи (`canvas.drawParagraph`, `canvas.drawText`) — только для данных, жёстко связанных с геометрией (временны́е метки на оси, Hz-метки на оси). Zone labels и section headers — всегда Flutter-виджеты.
- Все цвета в painter'ах — именованные `const Color(0x...)` в файле painter'а. Не брать из `AppColors` напрямую (painter'ы компилируются в изолят).

---

## 7. Anti-fake правила в UI (кратко)

Эти правила нормативны и не подлежат смягчению.

**Никакого BPM в Dart-коде.** Ни вычислений, ни хардкодных чисел BPM. Все значения — только из поля `DspResult.primary_bpm`, полученного от Rust.

**half/double кандидаты всегда видимы.** Ячейка `×½ / ×2` на главном экране не скрывается и не убирается. Кандидаты с `relation == half_time` и `relation == double_time` отображаются явно.

**STABLE только при доказательствах из DSP.** UI не может устанавливать визуальное состояние «стабильно» самостоятельно. `BpmSmoother` применяет гистерезис (K=3 не-STABLE кадра), но `CLIPPED_MIC`, `BREAKDOWN` и `NOISE_ONLY` пробрасываются в UI немедленно без задержки.

**`— — —` вместо пустого прямоугольника.** Пока `primary_bpm == null` — отображается `— — —` в стиле `bpmEmptyHero` (58 px, bpmEmpty #1E3530). Никакого белого прямоугольника, никакого «0.0».

**Confidence всегда рядом с BPM.** Отображение BPM без сопровождающей полосы уверенности недопустимо.
