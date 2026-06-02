---
name: flutter-design-system
description: Миграция хардкодных визуальных значений на токены Design System V2. Обновляет app_colors.dart и app_text_styles.dart, заменяет хардкод в виджетах и painter'ах на ссылки на токены. Запускай ПОСЛЕ flutter-ui-audit, используя его отчёт как список задач.
allowed-tools: [Read, Grep, Glob, Bash, Edit, Write]
---

# Flutter Design System Migration

Запускай после `/flutter-ui-audit`. Используй отчёт из `docs/plans/ui-audit-*.md`.

## Приоритет миграции

1. **Critical** — BPM Hero, ConfidenceBar, Tab Bar (пользователь видит всегда)
2. **High** — CardSystem (MainCard, Surface, GroupCard), Typography roles
3. **Medium** — Spacing, BorderRadius, Animations
4. **Low** — Shadow, Gradient stops

## Шаг 1: Обновить app_colors.dart

Проверить что все canonical цвета из V2 присутствуют:
```dart
// Backgrounds
static const Color background = Color(0xFF050807);
static const Color rootBackground = Color(0xFF07090A);
static const Color cardBackground = Color(0xFF0C1410);
static const Color surfaceBackground = Color(0xFF0D1712);
static const Color trackBackground = Color(0xFF111916);
static const Color divider = Color(0xFF080C09);

// Accents
static const Color accent = Color(0xFF00DFB0);
static const Color warning = Color(0xFFFFE090);
static const Color premium = Color(0xFFE0822A);
static const Color recording = Color(0xFFE04040);

// Text
static const Color primaryText = Color(0xFFC8DCD8);
static const Color secondaryText = Color(0xFF7AB8AA);
static const Color mediumText = Color(0xFF5A8878);
static const Color mutedText = Color(0xFF3A6858);
static const Color disabled = Color(0xFF1E3530);
static const Color deepDisabled = Color(0xFF1A3028);
static const Color border = Color(0xFF1A2D24);
```

Добавить отсутствующие. Не удалять существующие — только добавлять.

## Шаг 2: Обновить app_text_styles.dart

Проверить роли для каждого UI-элемента:
```dart
static const TextStyle bpmHero = TextStyle(
  fontFamily: 'IBMPlexMono',
  fontSize: 72, fontWeight: FontWeight.w600,
  letterSpacing: -0.04 * 72, height: 1.0,
);
static const TextStyle sectionLabel = TextStyle(
  fontFamily: 'IBMPlexMono',
  fontSize: 9, fontWeight: FontWeight.w500,
  letterSpacing: 0.14 * 9,
);
// ... остальные роли
```

## Шаг 3: Заменить хардкод в виджетах

Для каждой находки из audit-отчёта:
1. Прочитать файл
2. Найти хардкодное значение
3. Найти соответствующий токен
4. Edit: заменить значение на `AppColors.tokenName` или `AppTextStyles.roleName`
5. Убедиться что импорт добавлен

## Шаг 4: Обновить CustomPainter'ы

`waveform_painter.dart` и `live_spectrum_painter.dart` часто содержат хардкодные цвета в `paint()`.
Painter'ы не имеют BuildContext — передавать цвета через конструктор из AppColors:

```dart
WaveformColumnPainter({
  required this.primaryColor,   // AppColors.accent
  required this.secondaryColor, // AppColors.warning
})
```

## Шаг 5: Верификация

```sh
# Убедиться что хардкода стало меньше
grep -rn "Color(0x\|Colors\." apps/mobile/lib/ --include="*.dart" \
  | grep -v "app_colors.dart\|design_tokens.dart\|//\|test/" | wc -l

# Тесты
flutter analyze
flutter test
```

## Правила

- Один файл за один Edit — не смешивать несвязанные изменения
- После изменения `app_colors.dart`: проверить что все ссылающиеся файлы компилируются
- Не переименовывать существующие токены — только добавлять новые
- `design_tokens.dart` (legacy Phase 7) остаётся как thin proxy → AppColors/AppTextStyles
