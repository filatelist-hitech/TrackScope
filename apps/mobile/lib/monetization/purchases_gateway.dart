// Абстрактная граница для RevenueCat SDK — тестовый шов.
//
// Реальная имплементация (`revenuecat_gateway.dart`) — единственный файл,
// импортирующий `purchases_flutter`. Тесты и `ProStatusService` зависят
// только от этого интерфейса, что позволяет инжектить fake-реализацию
// без SDK-зависимости.

abstract class PurchasesGateway {
  /// Инициализировать SDK с ключами для iOS/Android. Если оба ключа пусты,
  /// реализация может остаться no-op (Free tier работает без SDK).
  Future<void> configure({
    required String iosKey,
    required String androidKey,
  });

  /// Текущий статус Pro (проверяет entitlement 'pro').
  Future<bool> getIsPro();

  /// Купить Lifetime пакет ($rc_lifetime).
  Future<PurchaseResult> purchaseLifetime();

  /// Купить Annual пакет ($rc_annual).
  Future<PurchaseResult> purchaseAnnual();

  /// Восстановить покупки.
  Future<PurchaseResult> restore();

  /// Подписаться на изменения Pro-статуса (entitlement 'pro' появился/исчез).
  Stream<bool> get onProChanged;
}

enum PurchaseResult {
  success,
  cancelled,
  error,
}
