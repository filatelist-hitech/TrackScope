---
name: flutter-ui-audit
description: Полный аудит Flutter UI на соответствие HTML-прототипу. Генерирует parity-score, token-consistency-score, инвентарь хардкодных визуальных значений и таблицу расхождений. Запускай ПЕРЕД любой дизайн-миграцией.
allowed-tools: [Read, Grep, Glob, Bash]
---

# Flutter UI Audit

Выполняй последовательно. Не изменяй код — только диагностика.

## 1. Прочитать source of truth

```
apps/mobile/design/BPM Radar Prototype v2.html
apps/mobile/lib/theme/app_colors.dart
apps/mobile/lib/theme/app_text_styles.dart
```

Извлечь из HTML: все цвета, размеры шрифтов, отступы, радиусы, анимации.

## 2. Найти хардкодные цвета

```sh
grep -rn "Color(0x\|Color.fromARGB\|Color.fromRGBO\|Colors\.\|const Color" \
  apps/mobile/lib/ --include="*.dart" \
  | grep -v "app_colors.dart\|app_text_styles.dart\|design_tokens.dart\|//\|test/" \
  | sort
```

## 3. Найти хардкодную типографику

```sh
grep -rn "fontSize:\|fontWeight:\|letterSpacing:\|fontFamily:\|FontWeight\." \
  apps/mobile/lib/ --include="*.dart" \
  | grep -v "app_text_styles.dart\|design_tokens.dart\|//\|test/" \
  | sort
```

## 4. Найти хардкодные отступы и радиусы

```sh
grep -rn "BorderRadius\.\|EdgeInsets\.\|padding:\|margin:\|borderRadius:" \
  apps/mobile/lib/ --include="*.dart" \
  | grep -v "app_colors.dart\|app_text_styles.dart\|//\|test/" \
  | grep -E "[0-9]" | sort
```

## 5. Найти хардкодные анимации

```sh
grep -rn "Duration(\|milliseconds:\|seconds:\|Curves\." \
  apps/mobile/lib/ --include="*.dart" \
  | grep -v "//\|test/" | sort
```

## 6. Проверить BPM Hero

Прочитать `apps/mobile/lib/widgets/bpm_hero_display.dart`.
Проверить: fontSize=72, fontWeight=w600, letterSpacing=-0.04, activeColor=#00DFB0,
unstableColor=#FFE090, emptyColor=#1E3530, placeholder="— — —".

## 7. Проверить ConfidenceBar

Прочитать `apps/mobile/lib/widgets/confidence_bar.dart`.
Проверить: height=8, borderRadius=4, animation 400ms width transition,
low=red, medium=yellow/amber, high=teal.

## 8. Проверить Tab Bar

Прочитать `apps/mobile/lib/widgets/app_tab_bar.dart`.
Проверить: topBorder=#0F1712, bg=#050807, label=9px w500 uppercase ls:0.1em.

## 9. Проверить Waveform

Прочитать `apps/mobile/lib/viz/waveform_painter.dart`.
Проверить: height≈120, primaryColor=#00DFB0, ambient glow, beat-reactive pulse.

## 10. Подсчитать метрики

```
design_parity_score = (matched_elements / total_prototype_elements) * 100
token_consistency_score = (token_uses / (token_uses + hardcoded_uses)) * 100
hardcoded_visual_values = count from steps 2–5
```

## 11. Сгенерировать отчёт

Сохранить в `docs/plans/ui-audit-<DATE>.md`:

```markdown
# UI Audit Report — <DATE>

## Metrics
| Metric | Value |
|---|---|
| design_parity_score | X% |
| token_consistency_score | X% |
| hardcoded_visual_values | N |

## Mismatch Inventory
| Prototype Element | File | Status | Current | Expected |
|---|---|---|---|---|
| BPM Hero | | Match/Partial/Miss | | |
| ConfidenceBar | | | | |
| Waveform | | | | |
| Tab Bar | | | | |
| Cards | | | | |
| Typography | | | | |
| Colors | | | | |
| Spacing | | | | |
| Animations | | | | |

## Hardcoded Values (top priority fixes)
| File:line | Type | Value | Token |
|---|---|---|---|

## Recommended migration order
1. ...
```
