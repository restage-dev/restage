import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  setUp(Restage.debugReset);

  test('no products, no gateway, no priceQueries: no commerce context', () {
    Restage.configure(apiKey: 'rs_pk_test');

    expect(
      Restage.hasCommerceContext(priceQueries: const {}),
      isFalse,
    );
  });

  test('a registered product alone signals commerce context', () {
    Restage.configure(
      apiKey: 'rs_pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
    );

    expect(
      Restage.hasCommerceContext(priceQueries: const {}),
      isTrue,
    );
  });

  test('an explicit billingGateway alone signals commerce context', () {
    Restage.configure(
      apiKey: 'rs_pk_test',
      billingGateway: const _FakeBillingGateway(),
    );

    expect(
      Restage.hasCommerceContext(priceQueries: const {}),
      isTrue,
    );
  });

  test('a non-empty priceQueries map alone signals commerce context', () {
    Restage.configure(apiKey: 'rs_pk_test');

    expect(
      Restage.hasCommerceContext(
        priceQueries: const {
          'pro_monthly': PriceInfo(
            localizedPrice: r'$9.99',
            priceMicros: 9990000,
            currency: 'USD',
            title: 'Pro Monthly',
            description: '',
          ),
        },
      ),
      isTrue,
    );
  });

  test(
      'a gateway present without going through the explicit configure() '
      'argument does NOT signal commerce context', () {
    Restage.configure(apiKey: 'rs_pk_test');
    // `Restage.billingGateway`'s lazy getter (and configure's own bundled
    // auto-install branch) install a gateway with no plugin override, which
    // eagerly touches the platform `in_app_purchase` channel and is not
    // unit-testable without a platform mock. `debugBillingGateway` installs a
    // gateway the same way — present in `_billingGateway` — without going
    // through `configure(billingGateway:)`, isolating exactly the fact this
    // test cares about: presence in the field alone must never flip the
    // predicate, only the explicit argument path does (the trap the private
    // `_hostSuppliedBillingGateway` flag exists to avoid).
    Restage.debugBillingGateway = const _FakeBillingGateway();

    expect(
      Restage.hasCommerceContext(priceQueries: const {}),
      isFalse,
    );
  });

  test('debugReset clears the explicit-billingGateway flag', () {
    Restage.configure(
      apiKey: 'rs_pk_test',
      billingGateway: const _FakeBillingGateway(),
    );
    expect(Restage.hasCommerceContext(priceQueries: const {}), isTrue);

    Restage.debugReset();
    Restage.configure(apiKey: 'rs_pk_test');

    expect(Restage.hasCommerceContext(priceQueries: const {}), isFalse);
  });
}

final class _FakeBillingGateway implements BillingGateway {
  const _FakeBillingGateway();

  @override
  Future<PurchaseOutcome> purchase(String productId, {String? basePlanId}) =>
      throw UnimplementedError();

  @override
  Future<RestoreOutcome> restore() => throw UnimplementedError();
}
