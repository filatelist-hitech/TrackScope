/// Абстракция аналитического сервиса.
///
/// Единственная продакшен-реализация — [MyTrackerAnalytics] (импортирует
/// mytracker_sdk, компилируется только на Android/iOS). Для веб и тестов
/// используется [StubAnalytics].
abstract class AnalyticsService {
  /// Инициализировать трекер с указанным SDK-ключом.
  Future<void> init(String sdkKey);

  /// Трекнуть произвольное событие с опциональными параметрами.
  /// Максимальная длина name / ключа / значения — 255 символов.
  Future<void> trackEvent(String name, [Map<String, String>? params]);

  /// Установить идентификатор пользователя (передаётся с каждым событием).
  /// Передать [null] чтобы сбросить.
  Future<void> setUserId(String? userId);

  /// Принудительно отправить буферизованные события на сервер.
  Future<void> flush();
}

/// No-op реализация для Flutter Web и unit-тестов.
class StubAnalytics implements AnalyticsService {
  @override
  Future<void> init(String sdkKey) async {}

  @override
  Future<void> trackEvent(String name, [Map<String, String>? params]) async {}

  @override
  Future<void> setUserId(String? userId) async {}

  @override
  Future<void> flush() async {}
}
