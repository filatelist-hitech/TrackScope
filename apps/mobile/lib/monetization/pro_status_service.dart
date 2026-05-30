// Singleton-сервис, владеющий Pro-статусом пользователя.
//
// Использует `ChangeNotifier` для реактивности UI. Не импортирует
// `purchases_flutter` и `revenuecat_gateway.dart` — зависит только от
// абстракции `PurchasesGateway`, что позволяет инжектить fake-реализацию
// в тестах и сохраняет web-сборку чистой.
//
// Real gateway инжектируется из `main.dart` (mobile) через
// `ProStatusService.instance.configureGateway(...)`.

import 'package:flutter/foundation.dart';

import 'purchases_gateway.dart';

/// No-op gateway that stays in Free tier. Used as default when no real
/// gateway has been injected (e.g. tests, web preview).
class _NoOpGateway implements PurchasesGateway {
  @override
  Future<void> configure({required String iosKey, required String androidKey}) async {}
  @override
  Future<bool> getIsPro() async => false;
  @override
  Future<PurchaseResult> purchaseLifetime() async => PurchaseResult.error;
  @override
  Future<PurchaseResult> purchaseAnnual() async => PurchaseResult.error;
  @override
  Future<PurchaseResult> restore() async => PurchaseResult.error;
  @override
  Stream<bool> get onProChanged => const Stream.empty();
}

class ProStatusService extends ChangeNotifier {
  ProStatusService._({PurchasesGateway? gateway})
      : _gateway = gateway ?? _NoOpGateway();

  static final ProStatusService instance = ProStatusService._();

  /// Для тестов: создать экземпляр с fake-gateway.
  factory ProStatusService.forTesting(PurchasesGateway gateway) {
    return ProStatusService._(gateway: gateway);
  }

  late PurchasesGateway _gateway;
  bool _isPro = false;
  bool _initialized = false;

  bool get isPro => _isPro;
  bool get initialized => _initialized;

  /// Подменить gateway на реальный (RevenueCat). Вызывается из `main.dart`
  /// до `initialize()`. Не используется в тестах и web-сборке.
  void configureGateway(PurchasesGateway gateway) {
    _gateway = gateway;
  }

  /// Инициализировать SDK с ключами. Если оба ключа пусты, остаёмся в Free
  /// tier без SDK-инициализации — Free работает полностью offline/keyless.
  Future<void> initialize({
    required String iosKey,
    required String androidKey,
  }) async {
    if (_initialized) return;

    await _gateway.configure(iosKey: iosKey, androidKey: androidKey);
    _isPro = await _gateway.getIsPro();
    _initialized = true;

    // Подписываемся на изменения Pro-статуса.
    _gateway.onProChanged.listen((isPro) {
      if (_isPro != isPro) {
        _isPro = isPro;
        notifyListeners();
      }
    });

    notifyListeners();
  }

  Future<PurchaseResult> purchaseLifetime() async {
    final result = await _gateway.purchaseLifetime();
    if (result == PurchaseResult.success) {
      _isPro = await _gateway.getIsPro();
      notifyListeners();
    }
    return result;
  }

  Future<PurchaseResult> purchaseAnnual() async {
    final result = await _gateway.purchaseAnnual();
    if (result == PurchaseResult.success) {
      _isPro = await _gateway.getIsPro();
      notifyListeners();
    }
    return result;
  }

  Future<PurchaseResult> restore() async {
    final result = await _gateway.restore();
    if (result == PurchaseResult.success) {
      _isPro = await _gateway.getIsPro();
      notifyListeners();
    }
    return result;
  }
}
