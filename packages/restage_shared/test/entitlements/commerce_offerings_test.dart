import 'dart:convert';

import 'package:restage_shared/commerce.dart';
import 'package:test/test.dart';

void main() {
  test('page preserves package boundaries, store children and nested metadata',
      () {
    final json = <String, dynamic>{
      'catalogRevision': 4,
      'currentOfferId': 'default',
      'offering': {
        'offerId': 'default',
        'metadata': {
          'nested': [
            true,
            null,
            1,
            {'price': 1.5}
          ]
        },
        'packages': [
          {
            'packageId': 'monthly',
            'position': 0,
            'products': [
              {
                'store': 'app_store',
                'storeProductId': 'ios.monthly',
                'productKind': 'autoRenewableSubscription'
              },
              {
                'store': 'play_store',
                'storeProductId': 'android.subscription',
                'productKind': 'autoRenewableSubscription',
                'basePlanId': 'monthly',
                'storeOfferIdentifier': 'intro'
              },
            ]
          },
        ],
      },
      'nextCursor': 'opaque+cursor',
    };
    final page = CommerceOfferingsPage.fromJson(json);
    expect(page.toJson(), json);
    expect(page.offering!.packages.single.products, hasLength(2));
    expect(() => page.offering!.metadata['new'] = true, throwsUnsupportedError);
    expect(() => (page.offering!.metadata['nested']! as List).add(2),
        throwsUnsupportedError);
    expect(
        CommerceOfferingsPage.fromJson(
                jsonDecode(jsonEncode(page.toJson())) as Map<String, dynamic>)
            .toJson(),
        json);
    expect(CommerceOfferingsPage(catalogRevision: 0).toJson(), {
      'catalogRevision': 0,
      'currentOfferId': null,
      'offering': null,
      'nextCursor': null,
    });
    expect(
        CommerceOfferingSummary(offerId: 'empty', packages: [])
            .toJson()['packages'],
        isEmpty);
    for (final revision in [null, -1, '4', 4.0]) {
      expect(
          () => CommerceOfferingsPage.fromJson(
              {...json, 'catalogRevision': revision}),
          throwsArgumentError);
    }
    expect(
        () => CommerceOfferingSummary(
            offerId: 'large', packages: [], metadata: {'value': 'x' * 65536}),
        throwsArgumentError);
  });

  test('offering DTO equality includes every field and ordered children', () {
    final product = CommercePackageProduct(
        store: 'play_store',
        storeProductId: 'sku',
        productKind: 'autoRenewableSubscription',
        basePlanId: 'monthly',
        storeOfferIdentifier: 'intro',
        fulfillmentForm: 'subscription');
    final package = CommercePackageSummary(
        packageId: 'monthly', position: 0, products: [product]);
    final offering = CommerceOfferingSummary(offerId: 'default', packages: [
      package
    ], metadata: {
      'a': [
        {'x': 1, 'y': 2}
      ],
      'b': true
    });
    final page = CommerceOfferingsPage(
        catalogRevision: 1,
        currentOfferId: 'default',
        offering: offering,
        nextCursor: 'next');
    final equal = CommerceOfferingsPage.fromJson(page.toJson());
    expect(equal, page);
    expect(equal.hashCode, page.hashCode);
    final reorderedMetadata =
        CommerceOfferingSummary(offerId: 'default', packages: [
      package
    ], metadata: {
      'b': true,
      'a': [
        {'y': 2, 'x': 1}
      ]
    });
    expect(reorderedMetadata, offering);
    expect(reorderedMetadata.hashCode, offering.hashCode);
    for (final change in <String, Object?>{
      'store': 'app_store',
      'storeProductId': 'other',
      'productKind': 'future',
      'basePlanId': 'annual',
      'storeOfferIdentifier': 'other',
      'fulfillmentForm': 'nonConsumable'
    }.entries) {
      expect(
          CommercePackageProduct.fromJson(
              {...product.toJson(), change.key: change.value}),
          isNot(product));
    }
    for (final change in <String, Object?>{
      'packageId': 'annual',
      'position': 1,
      'products': []
    }.entries) {
      expect(
          CommercePackageSummary.fromJson(
              {...package.toJson(), change.key: change.value}),
          isNot(package));
    }
    for (final change in <String, Object?>{
      'offerId': 'other',
      'metadata': {'b': false},
      'packages': []
    }.entries) {
      expect(
          CommerceOfferingSummary.fromJson(
              {...offering.toJson(), change.key: change.value}),
          isNot(offering));
    }
    for (final change in <String, Object?>{
      'catalogRevision': 2,
      'currentOfferId': 'other',
      'nextCursor': 'other',
      'offering': null
    }.entries) {
      expect(
          CommerceOfferingsPage.fromJson(
              {...page.toJson(), change.key: change.value}),
          isNot(page));
    }
    final other = CommercePackageProduct.fromJson(
        {...product.toJson(), 'basePlanId': 'annual'});
    expect(
        CommercePackageSummary(
            packageId: 'monthly', position: 0, products: [product, other]),
        isNot(CommercePackageSummary(
            packageId: 'monthly', position: 0, products: [other, product])));
    final otherPackage = CommercePackageSummary(
        packageId: 'annual', position: 1, products: [product]);
    expect(
        CommerceOfferingSummary(
            offerId: 'default', packages: [package, otherPackage]),
        isNot(CommerceOfferingSummary(
            offerId: 'default', packages: [otherPackage, package])));
    expect(
        CommerceOfferingSummary(offerId: 'default', packages: [], metadata: {
          'values': [1, 2]
        }),
        isNot(CommerceOfferingSummary(
            offerId: 'default',
            packages: [],
            metadata: {
              'values': [2, 1]
            })));
    for (final value in [null, -1, '0', 0.0, false]) {
      expect(
          () => CommercePackageSummary.fromJson(
              {...package.toJson(), 'position': value}),
          throwsArgumentError);
    }
    expect(
        () => CommercePackageSummary.fromJson(
            {...package.toJson()}..remove('position')),
        throwsArgumentError);
    final exact = {
      'value': 'x' * (65536 - utf8.encode(jsonEncode({'value': ''})).length)
    };
    expect(
        () => CommerceOfferingSummary(
            offerId: 'default', packages: [], metadata: exact),
        returnsNormally);
  });

  test('package selection is strict, optional and part of intent identity', () {
    final base = CommerceIntentRequest(
      intentId: '550e8400-e29b-41d4-a716-446655440000',
      offerId: 'default',
      store: 'play_store',
      appAnonymousToken: '550e8400-e29b-41d4-a716-446655440001',
    );
    final selected = CommerceIntentRequest.fromJson(
        {...base.toJson(), 'packageSelection': 'annual'});
    expect(selected.packageSelection, 'annual');
    expect(selected.toJson()['packageSelection'], 'annual');
    expect(CommerceIntentRequest.fromJson(selected.toJson()), selected);
    expect(selected, isNot(base));
    expect(base.toJson(), isNot(contains('packageSelection')));
    for (final invalid in ['', 'Annual', 'store/sku', 1]) {
      expect(
          () => CommerceIntentRequest.fromJson(
              {...base.toJson(), 'packageSelection': invalid}),
          throwsArgumentError);
    }
  });

  test('current projections require explicit revision independently of outcome',
      () {
    final state = CommercePurchaserStateResponse(
        status: 'current',
        entitlements: [],
        retrievedAt: DateTime.utc(2026),
        catalogRevision: 9);
    final purchase = CommerceVerifiedPurchase(
        storeTransactionId: 'one',
        productId: 'sku',
        providerEnvironment: 'production',
        kind: 'oneTimePurchase',
        outcome: 'revoked',
        outcomeOrder: 2,
        catalogRevision: 9,
        entitlements: []);
    expect(CommercePurchaserStateResponse.fromJson(state.toJson()), state);
    expect(CommerceVerifiedPurchase.fromJson(purchase.toJson()), purchase);
    expect(CommercePurchaserStateResponse.fromJson(state.toJson()).hashCode,
        state.hashCode);
    expect(CommerceVerifiedPurchase.fromJson(purchase.toJson()).hashCode,
        purchase.hashCode);
    for (final invalid in [null, -1, '9']) {
      expect(
          () => CommercePurchaserStateResponse.fromJson(
              {...state.toJson(), 'catalogRevision': invalid}),
          throwsArgumentError);
      expect(
          () => CommerceVerifiedPurchase.fromJson(
              {...purchase.toJson(), 'catalogRevision': invalid}),
          throwsArgumentError);
    }
  });
}
