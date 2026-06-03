# Plan: info-card-no-scroll — убрать скролл главного экрана

**complexity: low** — план в 5 строк, без полного шаблона.

## Суть

`SingleChildScrollView` в `_GlassmorphismCard` позволяет пользователю случайно
прокручивать карточку вверх-вниз. Левый скриншот подтверждает: **все строки
помещаются** (lock chips «ПОИСК|ЗАХВАТ|НЕСТ» видны) — скролл не нужен.

## Исправление

`apps/mobile/lib/ui/main_screen.dart` → `_GlassmorphismCard.build()`:
- Убрать `ScrollConfiguration(_NoGlowScrollBehavior)` + `SingleChildScrollView`
- Вернуть `clipBehavior: Clip.hardEdge` + `OverflowBox(alignment: topCenter, maxHeight: infinity)`
- Убрать класс `_NoGlowScrollBehavior` из конца файла
- Оставить уже уменьшённые отступы (padding 16/6/16/4, SizedBox 3dp)

## Done when

- `flutter test` → 219+/220 pass
- `flutter analyze` → 0 errors
- На эмуляторе главный экран не скролится
- ЭНЕРГИЯ и ТОНАЛЬНОСТЬ видны без скролла
