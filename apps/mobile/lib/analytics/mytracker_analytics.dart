// ignore: depend_on_referenced_packages
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:mytracker_sdk/mytracker_sdk.dart';
import 'analytics_service.dart';

/// Продакшен-реализация [AnalyticsService] поверх MyTracker SDK.
///
/// Импортирует `mytracker_sdk` — единственный файл в проекте, который это делает.
/// Все остальные файлы обращаются только к [AnalyticsService] / [Analytics].
class MyTrackerAnalytics implements AnalyticsService {
  @override
  Future<void> init(String sdkKey) async {
    // Отправлять события немедленно в течение суток после установки/обновления.
    await MyTracker.trackerConfig.setForcingPeriod(86400);
    // Геолокация не нужна — не включаем.
    await MyTracker.trackerConfig.setTrackingLocationEnabled(false);
    if (kDebugMode) {
      await MyTracker.setDebugMode(true);
    }
    await MyTracker.init(sdkKey);
  }

  @override
  Future<void> trackEvent(String name, [Map<String, String>? params]) =>
      MyTracker.trackEvent(name, params);

  @override
  Future<void> setUserId(String? userId) async {
    MyTracker.trackerParams.setCustomUserIds(userId != null ? [userId] : []);
  }

  @override
  Future<void> flush() => MyTracker.flush();
}
