// Реальная имплементация PurchasesGateway через RevenueCat SDK.
//
// Единственный файл в кодовой базе, импортирующий `purchases_flutter`.
// Все остальные слои (ProStatusService, UI) зависят только от абстракции
// `PurchasesGateway`, что сохраняет web-сборку и тесты чистыми.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'purchases_gateway.dart';

class RevenueCatGateway implements PurchasesGateway {
  final StreamController<bool> _proChangedCtrl =
      StreamController<bool>.broadcast();

  bool _configured = false;

  @override
  Future<void> configure({
    required String iosKey,
    required String androidKey,
  }) async {
    // Если оба ключа пусты, остаёмся в Free tier без SDK-инициализации.
    if (iosKey.isEmpty && androidKey.isEmpty) {
      return;
    }

    final key = Platform.isIOS ? iosKey : androidKey;
    if (key.isEmpty) {
      // Платформа не поддерживается или ключ отсутствует — no-op.
      return;
    }

    await Purchases.configure(PurchasesConfiguration(key));
    _configured = true;

    // Слушаем изменения CustomerInfo для эмита onProChanged.
    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      final isPro = _checkProEntitlement(customerInfo);
      _proChangedCtrl.add(isPro);
    });
  }

  @override
  Future<bool> getIsPro() async {
    if (!_configured) return false;
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return _checkProEntitlement(customerInfo);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PurchaseResult> purchaseLifetime() async {
    return _purchase('\$rc_lifetime');
  }

  @override
  Future<PurchaseResult> purchaseAnnual() async {
    return _purchase('\$rc_annual');
  }

  @override
  Future<PurchaseResult> restore() async {
    if (!_configured) return PurchaseResult.error;
    try {
      final customerInfo = await Purchases.restorePurchases();
      final isPro = _checkProEntitlement(customerInfo);
      _proChangedCtrl.add(isPro);
      return PurchaseResult.success;
    } on PlatformException catch (e) {
      if (e.code == PurchasesErrorCode.purchaseCancelledError.name) {
        return PurchaseResult.cancelled;
      }
      return PurchaseResult.error;
    } catch (_) {
      return PurchaseResult.error;
    }
  }

  @override
  Stream<bool> get onProChanged => _proChangedCtrl.stream;

  Future<PurchaseResult> _purchase(String packageId) async {
    if (!_configured) return PurchaseResult.error;
    try {
      final offerings = await Purchases.getOfferings();
      final package = offerings.current?.availablePackages
          .firstWhere((p) => p.identifier == packageId);
      if (package == null) return PurchaseResult.error;

      final customerInfo = await Purchases.purchasePackage(package);
      final isPro = _checkProEntitlement(customerInfo);
      _proChangedCtrl.add(isPro);
      return PurchaseResult.success;
    } on PlatformException catch (e) {
      if (e.code == PurchasesErrorCode.purchaseCancelledError.name) {
        return PurchaseResult.cancelled;
      }
      return PurchaseResult.error;
    } catch (_) {
      return PurchaseResult.error;
    }
  }

  bool _checkProEntitlement(CustomerInfo info) {
    return info.entitlements.active.containsKey('pro');
  }
}
