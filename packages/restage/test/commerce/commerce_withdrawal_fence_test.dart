import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late final String barrelSource;
  late final String runtimeSource;
  late final String paywallSource;
  late final String eventSource;

  setUpAll(() {
    barrelSource = File('lib/restage.dart').readAsStringSync();
    runtimeSource = File('lib/src/runtime/restage.dart').readAsStringSync();
    paywallSource =
        File('lib/src/runtime/restage_paywall.dart').readAsStringSync();
    eventSource = File('lib/src/events/restage_event.dart').readAsStringSync();
  });

  test('the root barrel does not export withdrawn purchase libraries', () {
    for (final export in [
      "export 'src/authoring/paywall_price_for.dart';",
      "export 'src/authoring/paywall_purchase.dart';",
      "export 'src/billing/billing_gateway.dart';",
      "export 'src/billing/in_app_purchase_gateway.dart'",
      "export 'src/billing/signed_native_offer.dart';",
    ]) {
      expect(barrelSource, isNot(contains(export)));
    }
  });

  test('the root facade has no purchase configuration or operations', () {
    for (final declaration in [
      'List<RestageProduct> products = const []',
      'BillingGateway? billingGateway,',
      'static BillingGateway get billingGateway',
      'static List<RestageProduct> get configuredProducts',
      'static Future<PurchaseOutcome> purchaseProduct(',
      'static Future<void> syncEntitlements() async',
      'static Stream<Set<RestageEntitlement>> get entitlements',
    ]) {
      expect(runtimeSource, isNot(contains(declaration)));
    }
  });

  test('paywall runtime cannot invoke purchase or restore operations', () {
    for (final declaration in [
      'this.priceQueries = const {}',
      'final Map<String, PriceInfo> priceQueries;',
      'Future<void> _runPurchase(',
      'Future<void> _runRestore(',
      'Restage.billingGateway',
      'Restage.purchaseProduct',
    ]) {
      expect(paywallSource, isNot(contains(declaration)));
    }
  });

  test(
      'purchase and entitlement event families are not part of the root event library',
      () {
    expect(eventSource, isNot(contains("part 'conversion_events.dart';")));
    expect(eventSource, isNot(contains("part 'lifecycle_events.dart';")));
    expect(
      eventSource,
      isNot(contains('abstract final class RestageEventNames')),
    );
  });

  test('positive controls prove the source fence reads the intended files', () {
    expect(barrelSource, contains("export 'src/runtime/restage.dart';"));
    expect(runtimeSource, contains('abstract final class Restage'));
    expect(paywallSource, contains('class RestagePaywall'));
    expect(eventSource, contains('sealed class RestageEvent'));
  });
}
