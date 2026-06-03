# Execution Plan: UI Design Audit Fixes (Flutter)

Источник требований: `/Downloads/CLAUDE_DESIGN_AUDIT.md` + `BPM Radar Prototype v2.html`

---

## 1. Task classification

- **complexity**: medium
- **domains**: ui, mobile

DSP-контракт и FFI не затронуты. Только Flutter UI-слой (`apps/mobile/`).

---

## 2. Agents

| Агент | Зачем |
|---|---|
| `@mobileman` | Основной исполнитель: Flutter файлы, Layout, дизайн-токены |
| `@reviewman` | Pre-merge gate: anti-fake check, flutter analyze/test зелёные |

`@dspman`, `@qaman` не нужны — BPM-математика не трогается.

---

## 3. Files to inspect

```
apps/mobile/lib/
  widgets/app_tab_bar.dart          # Issue 8: tab padding/font/icon sizes
  ui/main_screen.dart               # Issues 1,2,3,5: nav centering, gear icon, badge, font
  screens/signal_analyzer_screen.dart # Issues 6,7: SA font sizes + RU translation
  screens/settings_screen.dart      # Issue 9: settings typography
  theme/app_text_styles.dart        # Issue 5: font scale
  navigation/app_navigator.dart     # Issue 10: swipe (если нужно)
  widgets/listening_indicator.dart  # Issue 3: listening badge conflict
apps/mobile/design/
  BPM Radar Prototype.html          # существующий HTML v1 (reference)
  BPM Radar Prototype v2.html       # NEW: скопировать из Downloads (target state)
apps/mobile/test/
  widget_test.dart                  # расширить after fixes
```

---

## 4. Current behavior (evidence)

| # | Файл:строка | Текущее состояние | Проблема |
|---|---|---|---|
| 1 | `main_screen.dart` | flex-layout главной страницы | Элементы не центрированы |
| 2 | `main_screen.dart` | nav с gear-кнопкой | Иконка шестерёнки наезжает на waveform |
| 3 | `main_screen.dart` + `listening_indicator.dart` | Два индикатора: REC badge + "● слушаю" | UX-confusion |
| 4 | `signal_analyzer_screen.dart:63` | `'SIGNAL ANALYZER'` | Не переведено на русский |
| 5 | `app_text_styles.dart` | `szMicro=11`, `szCaption=12` | Мелкий текст на labels |
| 6 | `signal_analyzer_screen.dart` | font sizes SA экрана | Мелкий текст в Signal Analyzer |
| 7 | `signal_analyzer_screen.dart` | `'SIGNAL ANALYZER'`, `'BPM CANDIDATES'` и др. | Не переведены на русский |
| 8 | `app_tab_bar.dart:28` | `padding: EdgeInsets.fromLTRB(0,10,0,16)` | Tab bar мелкий |
|   | `app_tab_bar.dart:90` | `Icon size: 20` | OK, уже 20 |
|   | `app_tab_bar.dart:99` | font size `7` | Слишком мелко (должно быть 9) |
| 9 | `settings_screen.dart` | различные font sizes | Несогласованность typography |
| 10 | `app_navigator.dart` | `IndexedStack` без swipe | Нет свайп-навигации |

---

## 5. Target behavior

| # | Целевое состояние |
|---|---|
| 1 | Все flex-контейнеры: `mainAxisAlignment: center`, `crossAxisAlignment: center`; карточки 375px ширина |
| 2 | Nav: явный gap между элементами; gear icon не перекрывает waveform; padding ≥20px по бокам |
| 3 | Один индикатор: красный REC-badge (мигающий) когда запись активна, IDLE badge когда нет |
| 4 | Все строки на русском: `'АНАЛИЗАТОР СИГНАЛА'`, `'КАНДИДАТЫ BPM'`, `'МЕТРИКИ АЛГОРИТМА'` |
| 5 | font scale: micro 11→11 (OK), caption 12→12 (OK); tab label 7→9; stats labels читаемы |
| 6 | SA: `.sa-lbl` 11px, `.sa-val` 11–12px, `.cand-bpm` 20–22px, `.sa-hdr` 9px; больше padding |
| 7 | Все label'ы в Signal Analyzer на русском |
| 8 | TabBar: `padding: 14px 0 20px`; gap иконка↔текст: 6px; tab-label font: 9; min-height 50px |
| 9 | Settings: унифицировать на AppTextStyles — `.s-hdr` 9px/w500, `.s-lbl` 11px/w400, `.s-val` 10px/w400 |
| 10 | Горизонтальный swipe на `IndexedStack` через `GestureDetector` (δx ≥ 50px, не вертикальный) |

**Anti-fake правила (не нарушать):**
- Никакого BPM в UI-слое
- half/double кандидаты всегда видимы
- STABLE только по DSP-evidence

---

## 6. Data contracts

Изменения касаются **только отображения**, не контрактов:
- `DspResult` — не меняется
- `CaptureBridge` — не меняется
- `AppColors`, `AppTextStyles` — только добавление/изменение констант

---

## 7. Implementation steps

### Шаг 1: Скопировать HTML v2 прототип в `apps/mobile/design/`
```sh
cp "/Users/filatelist/Downloads/BPM Radar Prototype v2.html" \
   "/Users/filatelist/Documents/it/trackscope/apps/mobile/design/BPM Radar Prototype v2.html"
```
Тест: файл появился в репо, `flutter analyze` зелёный (HTML не компилируется Flutter).

### Шаг 2: Tab Bar — issue #8
Файл: `apps/mobile/lib/widgets/app_tab_bar.dart`
- `padding: EdgeInsets.fromLTRB(0, 14, 0, 20)` (было `10,16`)
- tab label font: `9` (было `7`)
- gap SizedBox: `height: 6` (было `4`)
- добавить `constraints: BoxConstraints(minHeight: 50)` на `_TabItem`

Тест: `flutter test test/widget_test.dart` должен проходить.

### Шаг 3: Signal Analyzer локализация — issues #4, #7
Файл: `apps/mobile/lib/screens/signal_analyzer_screen.dart`
- AppBar title: `'SIGNAL ANALYZER'` → `'АНАЛИЗАТОР СИГНАЛА'`
- Section headers: `'FFT SPECTRUM'` → `'СПЕКТР FFT'`, `'BPM CANDIDATES'` → `'КАНДИДАТЫ BPM'`, `'ALGORITHM METRICS'` → `'МЕТРИКИ АЛГОРИТМА'`
- Все остальные EN-строки → RU

Тест: `grep -r 'SIGNAL ANALYZER\|BPM CANDIDATES\|ALGORITHM METRICS\|FFT SPECTRUM' apps/mobile/lib/` должен дать 0 строк.

### Шаг 4: Signal Analyzer font sizes — issue #6
Файл: `apps/mobile/lib/screens/signal_analyzer_screen.dart`
- `.sa-lbl` (candidate labels): 9→11px
- `.sa-val` (metric values): 9→11px
- `.cand-bpm` (BPM числа): 17→20px
- `.sa-hdr` (section headers): 7→9px
- Padding строк: `11px 16px` (было `9px 14px`)

Тест: визуально в preview; `flutter analyze` зелёный.

### Шаг 5: Nav — issues #1, #2
Файл: `apps/mobile/lib/ui/main_screen.dart`
- Nav: добавить `mainAxisAlignment: MainAxisAlignment.spaceBetween`
- Gear icon: уменьшить до 14×14 или зафиксировать gap
- Nav padding: минимум `EdgeInsets.symmetric(horizontal: 20)`
- Карточки: `width: double.infinity` с `CrossAxisAlignment.center`

Тест: `flutter test` зелёный, визуальная проверка в preview.

### Шаг 6: REC/IDLE badge — issue #3
Файл: `apps/mobile/lib/ui/main_screen.dart` + `listening_indicator.dart`
- Удалить двойной индикатор (ListeningIndicator как отдельный виджет)
- Один toggle: красный `● REC` (мигание) когда `isCapturing`, тёмно-зелёный `IDLE` когда нет
- `ListeningIndicator` объединить с REC-badge или сделать conditional

Тест: `flutter test` зелёный; проверить что `ListeningIndicator` виджет-тест не сломан.

### Шаг 7: Settings typography — issue #9
Файл: `apps/mobile/lib/screens/settings_screen.dart`
- `.s-hdr`: `AppTextStyles.mono(9, FontWeight.w500, Color(0xFF7AB8AA), letterSpacing: 0.14*9)`
- `.s-lbl`: `AppTextStyles.mono(11, FontWeight.w400, AppColors.textSecondary)`
- `.s-val`: `AppTextStyles.mono(10, FontWeight.w400, AppColors.textMuted)`
- Унифицировать все вхождения

Тест: `flutter analyze` 0 errors.

### Шаг 8: Swipe navigation — issue #10
Файл: `apps/mobile/lib/navigation/app_navigator.dart`
- Обернуть `IndexedStack` в `GestureDetector`
- `onHorizontalDragEnd`: если `velocity.pixelsPerSecond.dx.abs() > 300` или `details.primaryVelocity`:
  - влево → следующая вкладка (если есть)
  - вправо → предыдущая вкладка (если есть)
- Pro-gate на history вкладке сохранить

Тест: `flutter test` зелёный; `GestureDetector` не ломает existing tab tests.

### Шаг 9: flutter test + analyze финальный прогон
```sh
cd apps/mobile && flutter analyze && flutter test
```
Все тесты зелёные.

---

## 8. Tests

```sh
# Основной прогон (обязателен перед PR):
cd apps/mobile
flutter analyze                                  # 0 errors, 0 warnings
flutter test                                     # все тесты зелёные

# Проверка отсутствия EN строк в UI:
grep -r 'SIGNAL ANALYZER\|BPM CANDIDATES\|ALGORITHM METRICS\|FFT SPECTRUM' \
  apps/mobile/lib/

# Проверка отсутствия hardcoded BPM:
grep -rn 'primary_bpm\s*=\s*[0-9]' apps/mobile/lib/
```

DSP-тесты (не обязательны для этого PR, но не должны регрессировать):
```sh
/opt/homebrew/opt/rust/bin/cargo test --workspace
```

---

## 9. Risks

| Риск | Вероятность | Фолбэк |
|---|---|---|
| Swipe конфликтует с горизонтальным скроллом внутри экранов | Средняя | Ограничить swipe только за пределами scrollable-контента через `GestureDetector.behavior: HitTestBehavior.deferToChild` + минимальный порог velocity |
| ListeningIndicator используется в тестах | Низкая | Сохранить виджет, изменить логику показа |
| Settings screen tests сломаются от font-size изменений | Низкая | Обновить snapshot-тесты; pixel-perfect тесты в проекте не используются |
| HTML v2 в `design/` попадёт в Flutter сборку | Нет | `.dart` файлы Flutter не включают HTML; `.gitignore` не трогается |

---

## 10. Done when

- [ ] `flutter analyze` → 0 errors, 0 warnings
- [ ] `flutter test` → все тесты PASS (≥148/149 как в Phase 12)
- [ ] `grep -r 'SIGNAL ANALYZER\|BPM CANDIDATES\|ALGORITHM METRICS' apps/mobile/lib/` → пусто
- [ ] Tab bar label font ≥ 9px, padding top ≥ 14px
- [ ] Signal Analyzer BPM числа ≥ 20px
- [ ] Nav bar не конфликтует с waveform (визуально в preview)
- [ ] Один badge (REC/IDLE), не два
- [ ] Swipe влево/вправо переключает вкладки
- [ ] `BPM Radar Prototype v2.html` скопирован в `apps/mobile/design/`
- [ ] Нет fake BPM, half/double кандидаты видимы, нет STABLE без evidence

---

*Создан: 2026-06-02. Ветка: `ui_final_testing`. Phase 13 UI polish.*
