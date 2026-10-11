// Exercises the SDK's runtime event association and real report transport.
// ignore_for_file: invalid_use_of_internal_member
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/restage_measurement.dart'
    show attachPurchaseExposure;
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_store_bridge/restage_store_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Initialize the plugin facade without replacing the injected fake platform.
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  InAppPurchase.instance;
  debugDefaultTargetPlatformOverride = null;
  late List<Map<String, dynamic>> reports;
  late List<ProductDetails> selected;
  late List<PurchaseDetails> confirmed;
  late int restores;
  late int reportStatus;
  late Future<PurchaseDetails?> Function(ProductDetails) buy;
  late Future<void> Function() restore;
  late Future<void> Function(http.Request)? beforeReport;
  final first = _product();
  final second = _product(price: r'$9.99');
  late Map<String, ProductDetails> packages;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
    Restage.configure(analyticsEnabled: true, measurementEnabled: true);
    reports = [];
    selected = [];
    confirmed = [];
    restores = 0;
    reportStatus = 200;
    beforeReport = null;
    packages = {'first': first, 'second': second};
    buy = (product) async {
      selected.add(product);
      return _result(product.id);
    };
    restore = () async => restores++;
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://example.test',
      apiKey: 'public-test-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/sdk/v1/measurement/purchases');
        await beforeReport?.call(request);
        reports.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          '{"accepted":true,"replayed":false}',
          reportStatus,
        );
      }),
    );
  });
  tearDown(Restage.debugReset);

  Future<void> Function(RestageEvent) custom({
    FutureOr<void> Function(PurchaseDetails)? onPurchase,
    FutureOr<void> Function(Object, StackTrace)? onError,
  }) => inAppPurchaseCustomEventHandler(
    packages: packages,
    purchase: (product) => buy(product),
    restore: () => restore(),
    onPurchase: onPurchase ?? confirmed.add,
    onError: onError,
  );

  test(
    'display preserves ordered offers and literal free price without terms',
    () {
      final data = inAppPurchaseOfferingData(
        identifier: 'holiday',
        packages: packages,
      );
      expect(data, {
        'identifier': 'holiday',
        'packages': [
          {
            'identifier': 'first',
            'productIdentifier': 'pro',
            'priceString': r'$0.00',
            'currencyCode': 'USD',
          },
          {
            'identifier': 'second',
            'productIdentifier': 'pro',
            'priceString': r'$9.99',
            'currencyCode': 'USD',
          },
        ],
      });
      packages.clear();
      expect((data['packages']! as List), hasLength(2));
      expect(jsonDecode(jsonEncode(data)), isA<Map<String, dynamic>>());
      expect(
        inAppPurchaseOfferingData(
          identifier: 'empty',
          packages: {},
        )['packages'],
        isEmpty,
      );
    },
  );

  test(
    'custom snapshots map and selects exact object for same SKU offers',
    () async {
      final handler = custom();
      packages['second'] = first;
      packages.clear();
      await handler(_purchase('second'));
      expect(selected.single, same(second));
      expect(confirmed.single.productID, 'pro');
      expect(reports.single['packageIdentifier'], 'second');
    },
  );

  test('original exposure survives replacement exposure and dismissal', () async {
    final pending = Completer<PurchaseDetails?>();
    buy = (_) => pending.future;
    var flushed = false;
    final event = _purchase(
      'second',
      nonce: 'a',
      flush: () async => flushed = true,
    );
    final handling = custom()(event);
    // A refreshed/dismissed mount does not replace the original event's exposure.
    final refreshed = _purchase('first', nonce: 'c');
    expect(refreshed, isNot(same(event)));
    await custom()(
      const PaywallDismissed(
        paywallId: 'upgrade',
        reason: DismissReason.userClose,
        timeOnPaywall: Duration(seconds: 1),
      ),
    );
    pending.complete(_result('pro'));
    await handling;
    expect(flushed, isTrue);
    expect(reports.single['exposure']['captureSessionNonce'], 'a' * 43);
    expect(reports.single['productIdentifier'], 'pro');
    expect(
      reports.single.keys,
      unorderedEquals([
        'exposure',
        'eventId',
        'packageIdentifier',
        'productIdentifier',
        'reportedOccurredAtMicros',
      ]),
    );
    expect(jsonEncode(reports), isNot(contains('private-transaction')));
    expect(jsonEncode(reports), isNot(contains('private-receipt')));
  });

  test(
    'same event suppresses reporting while distinct app-correlated events report',
    () async {
      final handler = custom();
      final event = _purchase('first');
      await handler(event);
      await handler(event);
      expect(reports, hasLength(1));
      await handler(_purchase('first'));
      expect(reports, hasLength(2));
      expect(selected, hasLength(3));
      expect(confirmed, hasLength(3));
    },
  );

  test(
    'missing empty non-string and unknown keys refuse before purchase',
    () async {
      final handler = custom();
      for (final id in <Object?>[null, '', 1, 'unknown']) {
        await expectLater(handler(_purchase(id)), throwsArgumentError);
      }
      await expectLater(
        handler(
          const PaywallCustomEvent(
            paywallId: 'upgrade',
            eventName: 'in_app_purchase.purchase',
            args: {},
          ),
        ),
        throwsArgumentError,
      );
      expect(selected, isEmpty);
      expect(confirmed, isEmpty);
      expect(reports, isEmpty);
    },
  );

  test(
    'wrong product and every unconfirmed status refuse callbacks and reporting',
    () async {
      final handler = custom();
      buy = (_) async => _result('wrong');
      await expectLater(handler(_purchase('first')), throwsStateError);
      for (final status in PurchaseStatus.values.where(
        (s) => s != PurchaseStatus.purchased,
      )) {
        buy = (_) async => _result('pro', status: status);
        await expectLater(handler(_purchase('first')), throwsStateError);
      }
      expect(confirmed, isEmpty);
      expect(reports, isEmpty);
    },
  );

  test('null and restore invoke neither confirmation nor reporting', () async {
    buy = (_) async => null;
    final handler = custom();
    await handler(_purchase('first'));
    await handler(_restore());
    expect(restores, 1);
    expect(confirmed, isEmpty);
    expect(reports, isEmpty);
  });

  test(
    'selection validation purchase and restore failures route to onError',
    () async {
      final errors = <Object>[];
      final failure = StateError('purchase failed');
      final handler = custom(onError: (e, _) => errors.add(e));
      await handler(_purchase('unknown'));
      buy = (_) async => _result('wrong');
      await handler(_purchase('first'));
      buy = (_) async => throw failure;
      await handler(_purchase('first'));
      restore = () async => throw failure;
      await handler(_restore());
      expect(errors, [
        isArgumentError,
        isStateError,
        same(failure),
        same(failure),
      ]);
      expect(confirmed, isEmpty);
      expect(reports, isEmpty);
    },
  );

  test('purchase and restore failures propagate without onError', () async {
    final failure = StateError('native failed');
    buy = (_) async => throw failure;
    restore = () async => throw failure;
    final handler = custom();
    await expectLater(handler(_purchase('first')), throwsA(same(failure)));
    await expectLater(handler(_restore()), throwsA(same(failure)));
  });

  test(
    'reporting failure preserves success and does not route to onError',
    () async {
      reportStatus = 503;
      final errors = <Object>[];
      await custom(onError: (e, _) => errors.add(e))(_purchase('first'));
      expect(confirmed, hasLength(1));
      expect(reports, hasLength(1));
      expect(errors, isEmpty);
    },
  );

  for (final reset in [true, false]) {
    test(
      '${reset ? 'reset' : 'consent disabled'} during checkout prevents reporting',
      () async {
        final pending = Completer<PurchaseDetails?>();
        buy = (_) => pending.future;
        final handling = custom()(_purchase('first'));
        if (reset) {
          Restage.reset();
        } else {
          Restage.configure(measurementEnabled: false);
        }
        pending.complete(_result('pro'));
        await handling;
        expect(confirmed, hasLength(1));
        expect(reports, isEmpty);
      },
    );
  }

  test(
    'callback error propagates separately after confirmed report is observed',
    () async {
      final release = Completer<void>();
      final started = Completer<void>();
      beforeReport = (_) async {
        started.complete();
        await release.future;
      };
      final failure = StateError('observer failed');
      final errors = <Object>[];
      var prepared = false;
      var settled = false;
      final event = _purchase('first', flush: () async => prepared = true);
      final handling = custom(
        onPurchase: (_) {
          expect(prepared, isTrue);
          throw failure;
        },
        onError: (e, _) => errors.add(e),
      )(event);
      final observed = expectLater(
        handling,
        throwsA(same(failure)),
      ).then((_) => settled = true);
      await started.future;
      expect(settled, isFalse);
      expect(errors, isEmpty);
      release.complete();
      await observed;
      expect(reports, hasLength(1));
    },
  );

  test(
    'unrelated and reserved Commerce events are ignored by both handlers',
    () async {
      final platform = _EventPlatform();
      InAppPurchasePlatform.instance = platform;
      final controller = InAppPurchaseController(
        verifyPurchase: (_) async => true,
        deliverPurchase: (_) async {},
        onError: (e, s) => fail('$e\n$s'),
      );
      try {
        for (final handler in [
          custom(),
          inAppPurchaseEventHandler(packages: packages, controller: controller),
        ]) {
          for (final name in [
            'purchase',
            'restore',
            'continue',
            'revenuecat.purchase',
            'commerce.purchase',
          ]) {
            await handler(
              PaywallCustomEvent(
                paywallId: 'upgrade',
                eventName: name,
                args: {},
              ),
            );
          }
          await handler(const PaywallViewed(paywallId: 'upgrade'));
        }
        expect(selected, isEmpty);
        expect(restores, 0);
        expect(platform.selected, isEmpty);
        expect(platform.restores, 0);
        expect(reports, isEmpty);
      } finally {
        await controller.dispose();
        await platform.close();
      }
    },
  );

  test(
    'default snapshots exact products, routes refusal/errors, and never reports backlog',
    () async {
      final platform = _EventPlatform();
      InAppPurchasePlatform.instance = platform;
      final delivered = Completer<void>();
      final dispatch = Completer<bool>();
      platform.dispatch = () => dispatch.future;
      final errors = <Object>[];
      final controller = InAppPurchaseController(
        verifyPurchase: (_) async => true,
        deliverPurchase: (_) async => delivered.complete(),
        onError: (e, s) => fail('$e\n$s'),
      );
      final handler = inAppPurchaseEventHandler(
        packages: packages,
        controller: controller,
        onError: (e, _) => errors.add(e),
      );
      packages.clear();
      try {
        final handling = handler(_purchase('second'));
        await Future<void>.delayed(Duration.zero);
        expect(platform.selected.single, same(second));
        platform.updates.add([_appleBacklog()]);
        await delivered.future;
        expect(reports, isEmpty);
        dispatch.complete(true);
        await handling;
        expect(reports, isEmpty);
        platform.dispatch = () async => false;
        await handler(_purchase('first'));
        expect(errors.single, isStateError);
        await handler(_purchase(null));
        expect(errors.last, isArgumentError);
        await handler(_restore());
        expect(platform.restores, 1);
        final nativeError = StateError('store failed');
        platform.dispatch = () async => throw nativeError;
        await handler(_purchase('first'));
        expect(errors.last, same(nativeError));
        platform.restoreError = nativeError;
        await handler(_restore());
        expect(errors.last, same(nativeError));
        final propagating = inAppPurchaseEventHandler(
          packages: {'first': first},
          controller: controller,
        );
        await expectLater(
          propagating(_purchase('first')),
          throwsA(same(nativeError)),
        );
        platform.dispatch = () async => false;
        await expectLater(propagating(_purchase('first')), throwsStateError);
        expect(reports, isEmpty);
      } finally {
        await controller.dispose();
        await platform.close();
      }
    },
  );
}

ProductDetails _product({String price = r'$0.00'}) => ProductDetails(
  id: 'pro',
  title: 'Pro',
  description: 'Pro access',
  price: price,
  rawPrice: price == r'$0.00' ? 0 : 9.99,
  currencyCode: 'USD',
);

PurchaseDetails _result(
  String id, {
  PurchaseStatus status = PurchaseStatus.purchased,
}) => PurchaseDetails(
  purchaseID: 'private-transaction',
  productID: id,
  verificationData: PurchaseVerificationData(
    localVerificationData: 'private-receipt',
    serverVerificationData: 'private-receipt',
    source: 'custom',
  ),
  transactionDate: '1',
  status: status,
);

SK2PurchaseDetails _appleBacklog() => SK2PurchaseDetails(
  purchaseID: 'backlog-transaction',
  productID: 'pro',
  verificationData: PurchaseVerificationData(
    localVerificationData: 'receipt',
    serverVerificationData: 'receipt',
    source: 'app_store',
  ),
  transactionDate: '1',
  status: PurchaseStatus.purchased,
);

PaywallCustomEvent _restore() => const PaywallCustomEvent(
  paywallId: 'upgrade',
  eventName: 'in_app_purchase.restore',
  args: {},
);

PaywallCustomEvent _purchase(
  Object? id, {
  String nonce = 'a',
  Future<void> Function()? flush,
}) {
  final event = PaywallCustomEvent(
    paywallId: 'upgrade',
    eventName: 'in_app_purchase.purchase',
    args: {'packageIdentifier': id},
  );
  attachPurchaseExposure(
    event,
    prepare: () async {
      await flush?.call();
      return (
        captureSessionNonce: nonce * 43,
        publicationBindingReference: _binding(),
      );
    },
  );
  return event;
}

MeasurementPublicationBindingReferenceV1 _binding() {
  final digest = CanonicalDigest('b' * 64);
  return MeasurementPublicationBindingReferenceV1(
    publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
      authorityId: MeasurementPublicationAuthorityId('test.authority'),
      externalPublicationAuthorityRef: 'mpa1.${'A' * 32}',
      candidateReference: MeasurementPublicationCandidateReferenceV1(
        candidateDigest: digest,
        selectedPublicationManifestDigest: digest,
        declaredArtifactBytesDigest: digest,
        assembledPublicationUploadDigest: digest,
        measurementPublicationDraftDigest: digest,
      ),
      immutablePublicationDigest: digest,
      declaredArtifactBytesDigest: digest,
    ),
    bindingDigest: digest,
  );
}

final class _EventPlatform extends InAppPurchasePlatform {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final selected = <ProductDetails>[];
  Future<bool> Function() dispatch = () async => true;
  int restores = 0;
  Object? restoreError;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) {
    selected.add(purchaseParam.productDetails);
    return dispatch();
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restores++;
    if (restoreError case final error?) throw error;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}

  Future<void> close() => updates.close();
}
