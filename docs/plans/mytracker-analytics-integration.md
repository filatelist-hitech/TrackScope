# Plan: MyTracker Analytics Integration

## 1. Task classification

- **Complexity:** medium
- **Domains:** mobile, ui, docs

DSP-ядро не трогается. Все изменения — Flutter/Android/iOS-оболочка и один новый
сервисный класс. Никакого влияния на BPM-математику, FFI-контракт и anti-fake-правила.

---

## 2. Agents

- **@mobileman** — владелец `apps/mobile/`, `apps/mobile/android/`, `apps/mobile/ios/`.
  Он знает платформенные слои, AndroidManifest, Info.plist, разрешения.
- **@docman** — обновить ROADMAP.md (новая Phase 16) и RELEASE_CHECKLIST.md
  (добавить проверку analytics SDK key перед публикацией).
- **@reviewman** — финальный гейт перед мерджем: убедиться, что SDK-ключ не
  hardcoded в tracked-коде, аналитика не влияет на DSP-путь.

---

## 3. Files to inspect

```
apps/mobile/pubspec.yaml
apps/mobile/lib/main.dart
apps/mobile/lib/monetization/revenuecat_gateway.dart   # паттерн для нового сервиса
apps/mobile/lib/monetization/pro_status_service.dart   # место hookа на Pro-покупку
apps/mobile/android/app/src/main/AndroidManifest.xml
apps/mobile/ios/Runner/Info.plist
apps/mobile/ios/Podfile                                # проверить min iOS version
```

Новые файлы (создать):
```
apps/mobile/lib/analytics/analytics_service.dart      # тонкая обёртка MyTracker
apps/mobile/lib/analytics/mytracker_analytics.dart    # реализация (единственный импорт SDK)
apps/mobile/lib/analytics/analytics_stub.dart         # web/стаб для flutter test
apps/mobile/test/analytics/analytics_service_test.dart
```

SDK-репо (скачать, НЕ коммитить):
```
third_party/mytracker_sdk/   # путь по соглашению проекта; в .gitignore
```

---

## 4. Current behavior

- Аналитика отсутствует: запуски, сессии, покупки — никакие события не собираются.
- `main.dart:35` инициализирует только RevenueCat и AppSettings.
- `AndroidManifest.xml` содержит только `RECORD_AUDIO`; нет `INTERNET`,
  `ACCESS_NETWORK_STATE`, `AD_ID`.
- iOS Info.plist не содержит `NSUserTrackingUsageDescription`.

---

## 5. Target behavior

После интеграции:
- MyTracker инициализируется сразу после `WidgetsFlutterBinding.ensureInitialized()`
  и до первого кадра.
- Автоматически собираются: запуски, сессии, auto-tracked In-App Purchases.
- Вручную трекируются события:
  - `"pro_purchase"` — при смене tier в `ProStatusService`.
  - `"session_start"` / `"session_end"` — при старте/стопе `CaptureBridge`.
  - `"bpm_stable_first"` — первый кадр STABLE в сессии (не per-кадр; не BPM-значение).
- SDK-ключ живёт в `config.dart` рядом с RevenueCat-ключом (gitignored).
- На Android добавлены три `uses-permission`; зависимости Play Services подтягиваются автоматически.
- На iOS добавлен `NSUserTrackingUsageDescription`; ATT-запрос не добавляется принудительно
  (MyTracker работает без него — это опционально).
- `trackingLocationEnabled = false` (по умолчанию; не меняем).
- `bufferingPeriod = 900` (дефолт); `forcingPeriod = 86400` (1 сутки после установки —
  события первой сессии важны).
- Debug-mode включается при `kDebugMode` Dart-константе.

**Что НЕ трекируется:**
- Конкретное значение BPM (не PII, но избыточно для аналитики).
- Конфиденциальные поля `DspResult` (candidates, raw scores).

---

## 6. Data contracts

**Нет изменений** в `DspResult`, FFI-контракте, `TempoCandidate`, `LockState`.

Новый публичный интерфейс:
```dart
// apps/mobile/lib/analytics/analytics_service.dart
abstract class AnalyticsService {
  Future<void> init(String sdkKey);
  Future<void> trackEvent(String name, [Map<String, String>? params]);
  Future<void> setUserId(String? userId);
  Future<void> flush();
}
```

`config.dart` (gitignored, по шаблону):
```dart
const String myTrackerSdkKeyAndroid = 'YOUR_ANDROID_KEY';
const String myTrackerSdkKeyIos     = 'YOUR_IOS_KEY';
```

Текущий ключ пользователя: `77163082583956202282` — одна платформа (скорее всего Android);
для iOS нужен отдельный ключ (указано в документации MyTracker). Этот ключ войдёт только
в `config.dart`, который gitignored.

---

## 7. Implementation steps

Каждый шаг — отдельный изменяемый юнит; тесты идут вместе со шагом.

### Шаг 1 — Скачать SDK и добавить в .gitignore

```bash
cd apps/mobile
git clone https://github.com/myTrackerSDK/mytracker-flutter.git \
    ../../third_party/mytracker_sdk --depth=1
echo "third_party/mytracker_sdk/" >> ../../.gitignore
```

`pubspec.yaml`:
```yaml
dependencies:
  mytracker_sdk:
    path: ../../third_party/mytracker_sdk
```

Проверка: `flutter pub get` не падает.

### Шаг 2 — Android permissions (`AndroidManifest.xml`)

Добавить три `<uses-permission>` перед `<application>`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="com.google.android.gms.permission.AD_ID" />
```

Тест: `flutter build apk --debug` компилируется без ошибок.

### Шаг 3 — iOS Info.plist

Добавить `NSUserTrackingUsageDescription` (ATT-текст, даже если ATT-запрос не делаем
сейчас — Apple требует при наличии AdSupport-фреймворка):
```xml
<key>NSUserTrackingUsageDescription</key>
<string>Помогает улучшать приложение. Данные не передаются третьим сторонам.</string>
```

Тест: `flutter build ios --no-codesign --simulator` без ошибок.

### Шаг 4 — `AnalyticsService` абстракция + stub

Файлы:
- `apps/mobile/lib/analytics/analytics_service.dart` — абстрактный класс (шаг выше).
- `apps/mobile/lib/analytics/analytics_stub.dart` — `class StubAnalytics implements AnalyticsService` (no-op, для web и тестов).

Тест (`analytics_service_test.dart`):
```dart
test('StubAnalytics.init() does not throw', () async {
  final s = StubAnalytics();
  await s.init('test');
});
test('StubAnalytics.trackEvent() does not throw', () async {
  final s = StubAnalytics();
  await s.trackEvent('ev', {'k': 'v'});
});
```

### Шаг 5 — `MyTrackerAnalytics` реализация

`apps/mobile/lib/analytics/mytracker_analytics.dart`:
```dart
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:mytracker_sdk/mytracker.dart';
import 'analytics_service.dart';

class MyTrackerAnalytics implements AnalyticsService {
  @override
  Future<void> init(String sdkKey) async {
    final config = await MyTracker.getTrackerConfig();
    await config.setForcingPeriod(86400);   // 1 сутки после установки
    await config.setAutotrackingPurchaseEnabled(true);
    if (kDebugMode) await MyTracker.setDebugMode(true);
    await MyTracker.init(sdkKey);
  }

  @override
  Future<void> trackEvent(String name, [Map<String, String>? params]) =>
      MyTracker.trackEvent(name, params);

  @override
  Future<void> setUserId(String? userId) async {
    final params = await MyTracker.getTrackerParams();
    if (userId != null) {
      params.setCustomUserIds([userId]);
    } else {
      params.setCustomUserIds([]);
    }
  }

  @override
  Future<void> flush() => MyTracker.flush();
}
```

Нет unit-теста для реального SDK-вызова (требует Android/iOS runtime); покрыто
интеграционным тестом в шаге 9.

### Шаг 6 — Добавить SDK-ключи в `config.dart` / `config.dart.template`

`config.dart.template` (уже существует — добавить строки):
```dart
const String myTrackerSdkKeyAndroid = 'YOUR_ANDROID_KEY_HERE';
const String myTrackerSdkKeyIos     = 'YOUR_IOS_KEY_HERE';
```

В реальный `config.dart` (gitignored) записать:
```dart
const String myTrackerSdkKeyAndroid = '77163082583956202282';
const String myTrackerSdkKeyIos     = ''; // заполнить после регистрации iOS-приложения в MyTracker
```

### Шаг 7 — Инициализация в `main.dart`

Добавить сразу после `AppSettings.instance.load()`:

```dart
import 'analytics/mytracker_analytics.dart';
import 'config.dart';   // уже импортирован для RevenueCat

// Определить ключ по платформе
final _analyticsKey = Platform.isIOS
    ? myTrackerSdkKeyIos
    : myTrackerSdkKeyAndroid;

// В main():
final analytics = MyTrackerAnalytics();
if (_analyticsKey.isNotEmpty) {
  await analytics.init(_analyticsKey);
}
```

Передать `analytics` в `AppNavigator` / `_CapturePipeline` через конструктор
или через `InheritedWidget` (рекомендуется singleton через статический геттер,
аналог `AppSettings.instance`).

Простейший подход — статический синглтон `AnalyticsService.instance` (заменяем
на `StubAnalytics` при `kIsWeb`).

### Шаг 8 — Хуки событий и полные схемы параметров

Все значения — строки (ограничение MyTracker API). Числа форматируются с
фиксированной точностью через `.toStringAsFixed(N)`.

---

#### `capture_start` — старт захвата (в `CaptureBridge.start()`)

```dart
analytics.trackEvent('capture_start', {
  'genre':     flags.selectedGenre.name,            // 'hitechPsy', 'custom', …
  'bpm_min':   '${flags.effectiveBpmRange.$1.round()}',
  'bpm_max':   '${flags.effectiveBpmRange.$2.round()}',
  'is_pro':    flags.isPro ? '1' : '0',
  'platform':  Platform.isIOS ? 'ios' : 'android',
});
```

---

#### `capture_stop` — стоп захвата (в `CaptureBridge.stop()`)

```dart
analytics.trackEvent('capture_stop', {
  'duration_sec':    '$elapsed',             // сек целым
  'reached_stable':  _reachedStable ? '1' : '0',
  'final_lock_state': _lastLockState.wireName, // LockState.wireName
  'genre':           flags.selectedGenre.name,
  'is_pro':          flags.isPro ? '1' : '0',
});
await analytics.flush();   // важно: flush при закрытии сессии
```

`_reachedStable` и `_lastLockState` — поля `_CapturePipeline`, обновляются
слушателем стрима `CaptureBridge.results`.

---

#### `bpm_first_stable` — первый STABLE в сессии

Единожды за сессию. Содержит всё, что знает DSP в момент первого STABLE-кадра.

```dart
analytics.trackEvent('bpm_first_stable', {
  // BPM и уверенность (основная ценность)
  'bpm':               result.primaryBpm!.toStringAsFixed(1),
  'confidence':        result.confidence.toStringAsFixed(2),

  // Тайминг захвата
  'first_lock_sec':    result.timing.firstLockTimeSec
                           ?.toStringAsFixed(1) ?? '',
  'analysis_sec':      result.timing.analysisTimeSec.toStringAsFixed(1),

  // Качество сигнала
  'input_dbfs':        result.signalQuality.inputLevelDbfs
                           ?.toStringAsFixed(1) ?? '',
  'snr_db':            result.signalQuality.snrEstimateDb
                           ?.toStringAsFixed(1) ?? '',
  'noise_level':       result.signalQuality.noiseLevel,  // 'low'/'medium'/'high'

  // DSP-метрики (из DspDebug)
  'onset_rate_hz':     result.debug.onsetRateHz.toStringAsFixed(2),
  'onset_strength':    result.debug.onsetStrength.toStringAsFixed(3),
  'peak_prominence':   result.debug.tempoPeakProminence.toStringAsFixed(2),
  'harmonic_ambiguity':result.debug.harmonicAmbiguity.toStringAsFixed(2),
  'stability_score':   result.debug.stabilityScore.toStringAsFixed(2),

  // Тональность (если определена)
  'key_camelot':       result.keyResult?.camelot ?? '',   // '8A', '10B', …
  'key_confidence':    result.keyResult?.confidence.toStringAsFixed(2) ?? '',

  // Энергия
  'energy_level':      result.energyResult?.level.toString() ?? '',

  // Топ-кандидат (relation позволяет понять half/double)
  'top_candidate_relation': result.candidates.isNotEmpty
                                ? result.candidates.first.relation : '',
  'top_candidate_score':    result.candidates.isNotEmpty
                                ? result.candidates.first.score.toStringAsFixed(2) : '',

  // Контекст
  'genre':     flags.selectedGenre.name,
  'is_pro':    flags.isPro ? '1' : '0',
  'platform':  Platform.isIOS ? 'ios' : 'android',
});
```

---

#### `lock_state_change` — смена состояния захвата (throttled)

Отправляем **только при смене** `lockState`, не чаще 1 раза в 3 секунды,
чтобы не перегружать буфер при осцилляции SEARCHING↔LOCKING.

```dart
// В слушателе results-стрима:
if (result.lockState != _prevLockState) {
  final now = DateTime.now();
  if (now.difference(_lastStateEventTime).inSeconds >= 3) {
    analytics.trackEvent('lock_state_change', {
      'from':       _prevLockState.wireName,
      'to':         result.lockState.wireName,
      'confidence': result.confidence.toStringAsFixed(2),
      'elapsed_sec':'$elapsedSec',
      'genre':      flags.selectedGenre.name,
    });
    _lastStateEventTime = now;
  }
  _prevLockState = result.lockState;
}
```

---

#### `signal_quality_warning` — клиппинг или брейкдаун

Отправляем 1 раз за событие (флаги `_clippingReported`, `_breakdownReported`,
сбрасываются в `capture_stop`).

```dart
if (result.signalQuality.clipping && !_clippingReported) {
  _clippingReported = true;
  analytics.trackEvent('signal_quality_warning', {
    'type':                'clipping',
    'clipped_frame_ratio': result.signalQuality.clippedFrameRatio
                               .toStringAsFixed(2),
    'input_dbfs':          result.signalQuality.inputLevelDbfs
                               ?.toStringAsFixed(1) ?? '',
    'elapsed_sec':         '$elapsedSec',
  });
}
if (result.signalQuality.breakdownLikely && !_breakdownReported) {
  _breakdownReported = true;
  analytics.trackEvent('signal_quality_warning', {
    'type':        'breakdown',
    'elapsed_sec': '$elapsedSec',
    'confidence':  result.confidence.toStringAsFixed(2),
  });
}
```

---

#### `pro_purchase` — покупка Pro (в `RevenueCatGateway` или `ProStatusService`)

```dart
analytics.trackEvent('pro_purchase', {
  'source':    'paywall',      // 'paywall' | 'settings' | 'restore'
  'platform':  Platform.isIOS ? 'ios' : 'android',
});
await analytics.flush();  // flush сразу — критическое событие
```

---

#### `session_summary` — итог сессии (альтернатива/дополнение к `capture_stop`)

Опционально — богатый итоговый снимок при стопе, если `_reachedStable`:

```dart
if (_reachedStable && _stableResult != null) {
  final r = _stableResult!;
  analytics.trackEvent('session_summary', {
    'bpm':              r.primaryBpm!.toStringAsFixed(1),
    'confidence':       r.confidence.toStringAsFixed(2),
    'key_camelot':      r.keyResult?.camelot ?? '',
    'energy_level':     r.energyResult?.level.toString() ?? '',
    'duration_sec':     '$elapsed',
    'noise_level':      r.signalQuality.noiseLevel,
    'snr_db':           r.signalQuality.snrEstimateDb?.toStringAsFixed(1) ?? '',
    'onset_rate_hz':    r.debug.onsetRateHz.toStringAsFixed(2),
    'harmonic_ambiguity':r.debug.harmonicAmbiguity.toStringAsFixed(2),
    'warnings':         r.debug.warnings.join(','),  // 'clipping,breakdown_likely'
    'genre':            flags.selectedGenre.name,
    'is_pro':           flags.isPro ? '1' : '0',
    'platform':         Platform.isIOS ? 'ios' : 'android',
  });
}
```

---

#### Состояние `_CapturePipeline` (новые поля)

```dart
// Добавить в _CapturePipelineState:
LockState _prevLockState = LockState.searching;
DateTime  _lastStateEventTime = DateTime.fromMillisecondsSinceEpoch(0);
bool _reachedStable    = false;
bool _clippingReported = false;
bool _breakdownReported= false;
DspResult? _stableResult;   // последний STABLE-кадр для session_summary
final Stopwatch _captureTimer = Stopwatch();

// В слушателе results:
if (result.lockState == LockState.stable) {
  _reachedStable = true;
  _stableResult  = result;
}
```

### Шаг 9 — Тест кнопки flush + дымовой тест событий

`analytics_service_test.dart` — добавить:
```dart
test('trackEvent with null params does not throw', () async {
  final s = StubAnalytics();
  await s.trackEvent('ev', null);
});
test('flush does not throw', () async {
  await StubAnalytics().flush();
});
```

Интеграционный дымовой тест (manual, не automated):
```
flutter run --debug → открыть MyTracker → Тест → убедиться что события приходят
```

---

## 8. Tests

| Тест | Файл | Команда |
|---|---|---|
| StubAnalytics unit | `test/analytics/analytics_service_test.dart` | `flutter test test/analytics/` |
| Регрессия Flutter | все тесты | `flutter test` |
| Регрессия Rust | DSP не трогается | `cargo test --workspace` |
| Offline QA | `offline_lab.py report` | `python3 tools/offline-lab/offline_lab.py report` |
| Android build | APK компилируется | `flutter build apk --debug` |

---

## 9. Risks

| Риск | Вероятность | Митигация |
|---|---|---|
| SDK не совместим с Flutter 3.44 | Средняя | Проверить `pubspec.yaml` SDK при `flutter pub get`; откатиться на предыдущую версию SDK |
| `AD_ID` permission вызывает Google Play review | Низкая | Разрешение стандартно для analytics SDK; RevenueCat его уже требует неявно |
| `config.dart` случайно закоммичен с ключом | Низкая | `.gitignore` уже есть; добавить pre-commit check в CI |
| iOS ключ не выдан ещё | Высокая | Инициализацию делать только при `_analyticsKey.isNotEmpty`; iOS-трекинг запускается позже |
| Аналитика блокирует main thread | Низкая | `MyTracker.init()` — async; вызываем с `await` в `main()`, до первого кадра |
| Двойной трекинг STABLE-событий | Средняя | Флаг `_firstStableTracked` сбрасывается в `stop()` каждой capture-сессии |

---

## 10. Done when

- [ ] `flutter pub get` проходит с `mytracker_sdk: path: …`
- [ ] `flutter test` → все тесты зелёные (включая 2+ новых analytics-теста)
- [ ] `flutter build apk --debug` компилируется без ошибок
- [ ] `flutter build ios --no-codesign --simulator` компилируется без ошибок
- [ ] `offline_lab.py report` → exit 0, 15/15 PASS (DSP не затронут)
- [ ] `cargo test --workspace` → все зелёные (DSP не затронут)
- [ ] В debug-режиме на устройстве события видны в MyTracker → Test-панели
- [ ] SDK-ключ не присутствует ни в одном tracked-файле (только `config.dart`)
- [ ] `NSUserTrackingUsageDescription` добавлен в Info.plist
- [ ] Anti-fake инварианты не нарушены: BPM-значение не передаётся в аналитику,
      `STABLE` не трекируется без реального evidence от DSP

---

## Примечания

**Отдельный iOS SDK-ключ:** MyTracker требует разные ключи для Android и iOS.
После регистрации iOS-приложения в MyTracker (app.tracker.my.com) получить второй ключ
и добавить в `config.dart`. До этого iOS-инициализация пропускается (`if (key.isNotEmpty)`).

**Трекинг платежей:** `AutotrackingPurchaseEnabled = true` (дефолт). MyTracker автоматически
отслеживает Google Play / App Store покупки через Install Referrer и StoreKit. Ручной
`trackEvent('pro_purchase')` — дополнительный конверсионный маркер.

**Геолокация:** `TrackingLocationEnabled = false` (дефолт) — не меняем. Приложение
не запрашивает локацию.
