// ProStatusService unit tests — fake gateway injection, isPro toggles,
// empty-key initialize stays Free.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:TrackScope/monetization/purchases_gateway.dart';
import 'package:TrackScope/monetization/pro_status_service.dart';

/// Fake gateway for testing — controllable isPro state.
class _FakeGateway implements PurchasesGateway {
  _FakeGateway({this.startPro = false});

  final bool startPro;
  bool _isPro = false;
  final _proChangedCtrl = StreamController<bool>.broadcast();

  @override
  Future<void> configure({required String iosKey, required String androidKey}) async {
    _isPro = startPro;
  }

  @override
  Future<bool> getIsPro() async => _isPro;

  @override
  Future<PurchaseResult> purchaseLifetime() async {
    _isPro = true;
    _proChangedCtrl.add(true);
    return PurchaseResult.success;
  }

  @override
  Future<PurchaseResult> purchaseAnnual() async {
    _isPro = true;
    _proChangedCtrl.add(true);
    return PurchaseResult.success;
  }

  @override
  Future<PurchaseResult> restore() async {
    _isPro = startPro;
    _proChangedCtrl.add(_isPro);
    return PurchaseResult.success;
  }

  @override
  Stream<bool> get onProChanged => _proChangedCtrl.stream;

  void dispose() => _proChangedCtrl.close();
}

void main() {
  group('ProStatusService', () {
    test('default instance starts as Free (not initialized)', () {
      final service = ProStatusService.forTesting(_FakeGateway());
      expect(service.isPro, isFalse);
      expect(service.initialized, isFalse);
    });

    test('initialize() reads isPro from gateway', () async {
      final gateway = _FakeGateway(startPro: true);
      final service = ProStatusService.forTesting(gateway);

      await service.initialize(iosKey: 'test', androidKey: 'test');

      expect(service.isPro, isTrue);
      expect(service.initialized, isTrue);

      gateway.dispose();
    });

    test('initialize() stays Free when gateway reports not pro', () async {
      final gateway = _FakeGateway(startPro: false);
      final service = ProStatusService.forTesting(gateway);

      await service.initialize(iosKey: 'test', androidKey: 'test');

      expect(service.isPro, isFalse);
      expect(service.initialized, isTrue);

      gateway.dispose();
    });

    test('purchaseLifetime() updates isPro', () async {
      final gateway = _FakeGateway(startPro: false);
      final service = ProStatusService.forTesting(gateway);

      await service.initialize(iosKey: 'test', androidKey: 'test');
      expect(service.isPro, isFalse);

      final result = await service.purchaseLifetime();
      expect(result, PurchaseResult.success);
      expect(service.isPro, isTrue);

      gateway.dispose();
    });

    test('initialize() is idempotent', () async {
      final gateway = _FakeGateway(startPro: false);
      final service = ProStatusService.forTesting(gateway);

      await service.initialize(iosKey: 'test', androidKey: 'test');
      await service.initialize(iosKey: 'test', androidKey: 'test');

      expect(service.initialized, isTrue);

      gateway.dispose();
    });
  });
}
