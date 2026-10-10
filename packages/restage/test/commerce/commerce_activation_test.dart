import 'package:flutter_test/flutter_test.dart';
import 'package:restage/commerce.dart';
import 'package:restage/restage.dart' show Restage;

void main() {
  setUp(Restage.debugReset);
  tearDown(Restage.debugReset);

  test('activation installs one application store adapter', () {
    final facade = Restage.commerce;
    final adapter = _TestStoreAdapter();

    Restage.activateCommerce(adapter);

    expect(Restage.commerce, same(facade));
    expect(Restage.debugCommerceStoreAdapter, same(adapter));

    Restage.activateCommerce(adapter);

    expect(
      () => Restage.activateCommerce(_TestStoreAdapter()),
      throwsStateError,
    );
  });

  test('debug reset makes store activation opt-in again', () {
    Restage.activateCommerce(_TestStoreAdapter());

    Restage.debugReset();

    expect(Restage.debugCommerceStoreAdapter, isNull);
  });

  test('activation makes the known commerce capability available', () async {
    final request = CommerceAvailabilityRequest(
      CommerceCapabilityCode.purchase,
      offerId: CommerceOfferId('offer.monthly'),
    );

    final before = await Restage.commerce.availability(request);
    Restage.activateCommerce(_TestStoreAdapter());
    final after = await Restage.commerce.availability(request);

    expect(before.available, isFalse);
    expect(before.failureCode, CommerceFailureCode.notActivated);
    expect(after.available, isTrue);
    expect(after.failureCode, isNull);
  });
}

final class _TestStoreAdapter implements CommerceStoreAdapter {
  @override
  CommerceStore get store => CommerceStore.appStore;

  @override
  Stream<CommerceStoreTransaction> get transactions =>
      const Stream<CommerceStoreTransaction>.empty();

  @override
  Future<void> completeTransaction(
      CommerceStoreTransaction transaction) async {}

  @override
  Future<List<CommerceStoreProduct>> queryProducts(
    Set<String> storeProductIds,
  ) async =>
      const <CommerceStoreProduct>[];

  @override
  Future<List<CommerceStoreTransaction>> queryOwnedTransactions() async =>
      const <CommerceStoreTransaction>[];

  @override
  Future<void> restore() async {}

  @override
  Future<bool> startPurchase(CommerceStorePurchasable purchasable) async =>
      false;
}
