import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/analytics/analytics_service.dart';

void main() {
  group('StubAnalytics', () {
    late StubAnalytics stub;

    setUp(() => stub = StubAnalytics());

    test('init() does not throw', () async {
      await expectLater(stub.init('test_key'), completes);
    });

    test('trackEvent() with params does not throw', () async {
      await expectLater(
        stub.trackEvent('ev', {'k': 'v', 'n': '42'}),
        completes,
      );
    });

    test('trackEvent() with null params does not throw', () async {
      await expectLater(stub.trackEvent('ev', null), completes);
    });

    test('trackEvent() without params does not throw', () async {
      await expectLater(stub.trackEvent('ev'), completes);
    });

    test('setUserId() with value does not throw', () async {
      await expectLater(stub.setUserId('user_123'), completes);
    });

    test('setUserId() with null does not throw', () async {
      await expectLater(stub.setUserId(null), completes);
    });

    test('flush() does not throw', () async {
      await expectLater(stub.flush(), completes);
    });

    test('implements AnalyticsService contract', () {
      expect(stub, isA<AnalyticsService>());
    });
  });
}
