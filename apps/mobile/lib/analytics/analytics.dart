import 'package:flutter/foundation.dart' show kIsWeb;
import 'analytics_service.dart';

/// Глобальная точка доступа к аналитическому сервису.
///
/// Инициализируется в `main()` один раз через [Analytics.configure].
/// По умолчанию (и на вебе) — [StubAnalytics] (no-op).
class Analytics {
  Analytics._();

  static AnalyticsService _instance = StubAnalytics();

  /// Текущая реализация. Использовать везде в приложении.
  static AnalyticsService get instance => _instance;

  /// Установить реализацию и инициализировать.
  ///
  /// Вызывается из `main()` до первого кадра.
  /// Если [sdkKey] пуст или [kIsWeb] — остаётся stub.
  static Future<void> configure(AnalyticsService service, String sdkKey) async {
    if (kIsWeb || sdkKey.isEmpty) return;
    _instance = service;
    await _instance.init(sdkKey);
  }

  /// Заменить реализацию (для тестов).
  static void overrideForTest(AnalyticsService service) {
    _instance = service;
  }
}
