# ADR 004: Setlist Tracker Architecture

## Status: Accepted

## Date: 2026-06-01

## Context

Setlist Tracker должен записывать BPM-снапшоты во время сета DJ. Вопросы:
1. Где хранить записи (in-memory vs persistent)?
2. Как интегрироваться с DspResult stream?
3. Как избежать flood одинаковых записей?

## Decision

**`SetlistService` (ChangeNotifier, in-memory) + subscription к `CaptureBridge.results` stream.**

Архитектура:
```
CaptureBridge.results (Stream<DspResult>)
    ↓ StreamSubscription в SetlistService.onDspResult()
SetlistService._entries (List<SetlistEntry>)
    ↓ exportJson() / exportCsv()
share_plus (IO)
```

**Почему in-memory:**
- Сет DJ ≤ 6–8 часов; при 1 записи/5 сек → ≤ ~6000 записей → ~1 МБ. Приемлемо.
- Persistent storage (SQLite / Hive) добавляет зависимость без ощутимой пользы.
- Pro-ограничение: подписка на stream только когда `FeatureFlags.canAccessSetlist` (Phase 2: добавить в FeatureFlags).

**Дедупликация:**
- delta BPM < 0.5 AND delta time < 5 сек → пропуск. Предотвращает flood при стабильном темпе.

**Phase 2 расширение:**
- Добавить `camelotKey: String?` и `energyLevel: int?` в `SetlistEntry`.
- Добавить `BpmSparklinePainter` на `SetlistScreen`.
- Persistence: опциональный экспорт в `share_plus` → файл на устройстве.

## Consequences

**Позитивные:**
- Простота: `SetlistService` реиспользует существующий `DspResult` контракт без изменений.
- Экспорт реиспользует pattern из `BpmExporter` (уже в `lib/export/`).
- ChangeNotifier → реактивный UI без дополнительных стримов.

**Ограничения:**
- In-memory: данные теряются при перезапуске приложения. Приемлемо для MVP.
- `onDspResult` вызывается из UI-thread (stream подписчик); не блокирует DSP-изолят.

## Файлы

`apps/mobile/lib/features/setlist/setlist_entry.dart`, `setlist_service.dart` (реализовано).
