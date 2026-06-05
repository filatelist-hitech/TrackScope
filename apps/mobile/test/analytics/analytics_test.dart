import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/analytics/analytics.dart';
import 'package:TrackScope/analytics/analytics_service.dart';

class _RecordingAnalytics implements AnalyticsService {
  final List<(String, Map<String, String>?)> events = [];
  bool initCalled = false;
  String? lastUserId;
  int flushCount = 0;

  @override
  Future<void> init(String sdkKey) async => initCalled = true;

  @override
  Future<void> trackEvent(String name, [Map<String, String>? params]) async =>
      events.add((name, params));

  @override
  Future<void> setUserId(String? userId) async => lastUserId = userId;

  @override
  Future<void> flush() async => flushCount++;
}

void main() {
  group('Analytics singleton', () {
    setUp(() => Analytics.overrideForTest(StubAnalytics()));
    tearDown(() => Analytics.overrideForTest(StubAnalytics()));

    test('default instance is StubAnalytics', () {
      expect(Analytics.instance, isA<StubAnalytics>());
    });

    test('configure() with empty key stays stub', () async {
      final rec = _RecordingAnalytics();
      await Analytics.configure(rec, '');
      expect(Analytics.instance, isA<StubAnalytics>());
      expect(rec.initCalled, isFalse);
    });

    test('overrideForTest() replaces instance', () {
      final rec = _RecordingAnalytics();
      Analytics.overrideForTest(rec);
      expect(Analytics.instance, same(rec));
    });

    test('trackEvent() via instance reaches recording analytics', () async {
      final rec = _RecordingAnalytics();
      Analytics.overrideForTest(rec);
      await Analytics.instance.trackEvent('test_event', {'k': 'v'});
      expect(rec.events, hasLength(1));
      expect(rec.events.first.$1, 'test_event');
      expect(rec.events.first.$2, {'k': 'v'});
    });

    test('flush() via instance reaches recording analytics', () async {
      final rec = _RecordingAnalytics();
      Analytics.overrideForTest(rec);
      await Analytics.instance.flush();
      expect(rec.flushCount, 1);
    });

    test('setUserId() via instance reaches recording analytics', () async {
      final rec = _RecordingAnalytics();
      Analytics.overrideForTest(rec);
      await Analytics.instance.setUserId('u1');
      expect(rec.lastUserId, 'u1');
    });
  });
}
