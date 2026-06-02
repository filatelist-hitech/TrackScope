---
name: golden-testing
description: Создание и обновление golden-тестов для Flutter виджетов и экранов. Генерирует эталонные PNG-снапшоты, добавляет matchesGoldenFile assertions, обновляет golden файлы после намеренных UI изменений. Запускай после дизайн-миграции для фиксации визуального состояния.
allowed-tools: [Read, Grep, Glob, Bash, Edit, Write]
---

# Golden Testing

## Что такое golden тесты

`flutter test --update-goldens` генерирует PNG-снапшоты виджетов.
Последующие `flutter test` сравнивают пиксель-в-пиксель с эталоном.
Живут в `apps/mobile/test/goldens/`.

## Шаг 1: Проверить существующее покрытие

```sh
find apps/mobile/test/ -name "*.dart" | xargs grep -l "matchesGoldenFile" 2>/dev/null
ls apps/mobile/test/goldens/ 2>/dev/null || echo "no goldens yet"
```

## Шаг 2: Создать/обновить golden тесты

Для каждого target-компонента создать тест в `apps/mobile/test/`:

```dart
testWidgets('BpmHeroDisplay golden — stable state', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'IBMPlexMono'),
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: BpmHeroDisplay(bpm: 200.0, lockState: LockState.stable),
        ),
      ),
    ),
  );
  await expectLater(
    find.byType(BpmHeroDisplay),
    matchesGoldenFile('goldens/bpm_hero_stable.png'),
  );
});
```

## Target компоненты (приоритет)

| Widget/Screen | Golden file | States to cover |
|---|---|---|
| BpmHeroDisplay | bpm_hero_*.png | stable / unstable / empty |
| ConfidenceBar | confidence_bar_*.png | low / medium / high |
| AppTabBar | tab_bar_*.png | radar / history / settings active |
| SignalAnalyzerScreen | signal_analyzer.png | with mock DspResult |
| HistoryScreen | history_*.png | empty / with data |
| SettingsScreen | settings.png | default state |
| MainScreen InfoCard | info_card_*.png | searching / locking / stable |

## Шаг 3: Сгенерировать эталоны

```sh
cd apps/mobile
flutter test --update-goldens test/golden_test.dart
```

**Только после** намеренного UI-изменения! Не обновлять goldens при неожиданных расхождениях.

## Шаг 4: Верификация

```sh
flutter test test/golden_test.dart
# Все должны быть green — при расхождении выводит diff PNG
```

## Шаг 5: Добавить в CI

В `flutter test` команду включить golden тесты:
```sh
flutter test --reporter=expanded
```

## Правила

- Golden файлы коммитятся в репозиторий (`test/goldens/*.png`)
- Обновлять `--update-goldens` только при намеренных визуальных изменениях
- При случайном расхождении — разобраться в причине, не обновлять слепо
- Использовать `DeviceSize(390, 844)` (iPhone 14) как базовый размер
- Шрифты в тестах должны быть `IBMPlexMono` — загружать через `loadFonts()`
