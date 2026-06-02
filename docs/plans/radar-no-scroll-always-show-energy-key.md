# Plan: Radar tab — no scroll, energy/key always visible

## 1. Task classification

- **complexity:** low
- **domains:** ui

---

## 2. Agents

Задача чисто UI — ни DSP-ядро, ни FFI, ни QA-контракты не затрагиваются.
Субагенты не требуются; опциональный постпроверочный прогон `@uiman` для визуальной оценки.

---

## 3. Files to inspect

| Файл | Причина |
|---|---|
| `apps/mobile/lib/ui/main_screen.dart` | Вся Radar-страница — единственный изменяемый файл |
| `apps/mobile/test/widget_test.dart` | Тесты для energy/key условного рендера → нужно обновить |

---

## 4. Current behavior

**Evidence из кода:**

1. **Скролл есть** — `_GlassmorphismCard` (строки 381–397) оборачивает `_InfoTableContent` в `SingleChildScrollView(physics: ClampingScrollPhysics())`. Пользователь может скроллить карточку.

2. **Energy и Key рендерятся условно** — строки 544–567:
   ```dart
   if (hasEnergy || hasKey) ...[
     const SizedBox(height: 6),
     Row(
       children: [
         Expanded(child: hasEnergy ? _EnergyCell(...) : const SizedBox()),
         Expanded(child: hasKey   ? _StatCell(...)  : const SizedBox()),
       ],
     ),
   ],
   ```
   Если оба `null` — вся строка не рендерится. Если один из них `null` — его половина занята пустым `SizedBox`.

3. **Layout-бюджет** — Waveform 120 px fixed + LiveSpectrum Expanded(22) + InfoCard Expanded(43). Внутри карточки 7 Row-блоков + BPM hero (≈100 px) + ConfidenceBar + Break button.

---

## 5. Target behavior

1. **Нет скролла** — `SingleChildScrollView` удалён; содержимое карточки умещается без переполнения.
2. **Energy и Key показываются всегда** — строка «ЭНЕРГИЯ / ТОНАЛЬНОСТЬ» рендерится независимо от наличия данных; при `null` показывается `—` (пустая клетка-заглушка той же высоты).
3. Вертикальные отступы (`SizedBox(height: 6/8)`) и высота BPM hero сжимаются ровно настолько, чтобы весь контент влезал на экран iPhone SE (375×667 pt) без скролла.

---

## 6. Data contracts

Без изменений. `DspResult`, `EnergyResult`, `KeyResult`, FFI-граница — не трогаются.
Только логика условного рендера в `_InfoTableContent`.

---

## 7. Implementation steps

### Шаг 1 — Убрать `SingleChildScrollView`, заменить на `Column` / `IntrinsicHeight`

В `_GlassmorphismCard.build` (строки 381–397):
```dart
// БЫЛО:
child: SingleChildScrollView(
  physics: const ClampingScrollPhysics(),
  child: _InfoTableContent(...)
),

// СТАНЕТ:
child: _InfoTableContent(...)
```

### Шаг 2 — Сделать energy/key строку всегда видимой

В `_InfoTableContent.build` заменить блок `if (hasEnergy || hasKey)`:

```dart
// БЫЛО:
if (hasEnergy || hasKey) ...[
  const SizedBox(height: 6),
  Row(
    children: [
      Expanded(child: hasEnergy ? _EnergyCell(...) : const SizedBox()),
      Expanded(child: hasKey   ? _StatCell(...)  : const SizedBox()),
    ],
  ),
],

// СТАНЕТ:
const SizedBox(height: 6),
Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Expanded(
      child: hasEnergy
          ? _EnergyCell(energyResult: energyResult)
          : _StatCell(label: 'ЭНЕРГИЯ', value: '—'),
    ),
    const SizedBox(width: 18),
    Expanded(
      child: hasKey
          ? _StatCell(label: 'ТОНАЛЬНОСТЬ', value: kResult!.camelot ?? '—', centered: true)
          : _StatCell(label: 'ТОНАЛЬНОСТЬ', value: '—', centered: true),
    ),
  ],
),
```

### Шаг 3 — Сжать вертикальные отступы

Уменьшить `SizedBox` между секциями с 6–8 px до 4–5 px, Break button padding с `vertical: 8` до `vertical: 5`, padding карточки с `fromLTRB(16,10,16,8)` до `fromLTRB(14,8,14,6)`.

Конкретные изменения (все в `main_screen.dart`):
- Строка 375 (`padding: const EdgeInsets.fromLTRB(0, 2, 0, 6)`) → `fromLTRB(0, 2, 0, 4)`
- Строка 374 (`padding: const EdgeInsets.fromLTRB(16, 10, 16, 8)`) → `fromLTRB(14, 8, 14, 6)`
- `SizedBox(height: 8)` после Break button → `SizedBox(height: 4)`
- `SizedBox(height: 6)` между Row 1/2/3 → `SizedBox(height: 4)`
- `SizedBox(height: 8)` перед `_ModeChips` → `SizedBox(height: 4)`
- `_BreakButtonInline` padding `vertical: 8` → `vertical: 5`

### Шаг 4 — Уменьшить LiveSpectrum при нужде

Если на iPhone SE всё ещё не влезает — уменьшить `flex: 22` у LiveSpectrum до `flex: 16`
и `flex: 43` у карточки до `flex: 37`.
(Проверить после шага 3 через `flutter test`.)

### Шаг 5 — Обновить тесты в `widget_test.dart`

Тесты `energy_row_hidden_when_null` и `key_row_hidden_when_null` (строки — проверить в файле) проверяли **отсутствие** виджета. После изменения они должны проверять наличие заглушки `—` вместо отсутствия. Переименовать и обновить assertions:

```dart
// БЫЛО: проверяем что _EnergyCell отсутствует
// СТАНЕТ: проверяем что текст '—' присутствует под лейблом 'ЭНЕРГИЯ'
```

---

## 8. Tests

| Тест | Команда |
|---|---|
| Flutter widget тесты (regression) | `flutter test` |
| Flutter analyze | `flutter analyze` |

**Тест-кейсы к обновлению в `widget_test.dart`:**
- `energy_row_hidden_when_energy_result_is_null` → переименовать + проверить заглушку `—`
- `key_row_hidden_when_key_result_is_null` → переименовать + проверить заглушку `—`
- `key_row_hidden_when_confidence_below_threshold` → проверить заглушку `—`
- Добавить: `energy_always_visible_even_when_null` — найти текст `'ЭНЕРГИЯ'` на экране
- Добавить: `key_always_visible_even_when_null` — найти текст `'ТОНАЛЬНОСТЬ'` на экране

---

## 9. Risks

| Риск | Вероятность | Митигация |
|---|---|---|
| Overflow на малых экранах (iPhone SE 375×667) | средняя | Уменьшить flex LiveSpectrum + отступы (шаг 3–4); при необходимости убрать зоновые лейблы WAVEFORM/LIVE SPECTRUM или сделать их совсем мелкими |
| Тесты ожидают `findsNothing` для energy/key → упадут | высокая | Явно обновлены в шаге 5 |
| Удаление `ClampingScrollPhysics` вызывает jank на `AnimatedSwitcher` | низкая | Этот `AnimatedSwitcher` ограничен `ValueKey(hasValue)` (строка 808), не перерисовывает при каждом BPM-тике; скролл был добавлен именно как band-aid от jank → его удаление безопасно |

---

## 10. Done when

- `flutter test` → все тесты зелёные (195+5 новых = 200)
- `flutter analyze` → 0 errors
- Энергия и тональность всегда отображаются в info-карточке, даже без сигнала (значение `—`)
- На Radar tab нет `SingleChildScrollView` → скролл невозможен
- Вертикальное содержимое умещается на условном iPhone SE (375×667) без RenderFlex overflow
