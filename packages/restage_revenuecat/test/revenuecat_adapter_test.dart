import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/restage_measurement.dart'
    show attachPurchaseExposure;
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_revenuecat/restage_revenuecat.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('purchases_flutter');
  late List<MethodCall> calls;
  late List<Map<String, dynamic>> reports;
  late List<CustomerInfo> customerInfos;
  late Future<Object?> Function(MethodCall) native;
  late int reportStatus;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
    Restage.configure(analyticsEnabled: true, measurementEnabled: true);
    calls = [];
    reports = [];
    customerInfos = [];
    reportStatus = 200;
    native = (call) async =>
        call.method == 'restorePurchases' ? _customerInfo : _purchaseResult;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return native(call);
    });
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://example.test',
      apiKey: 'public-test-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/sdk/v1/measurement/purchases');
        reports.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
            '{"accepted":true,"replayed":false}', reportStatus);
      }),
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    Restage.debugReset();
  });

  test('offering data preserves package identifiers, prices and offer phases',
      () {
    final offering = _offering([
      _package('annual_49',
          intro: const IntroductoryPrice(
              0, r'$0.00', 'P1W', 1, PeriodUnit.week, 1)),
      _package('annual_59',
          intro: const IntroductoryPrice(
              9.99, r'$9.99', 'P1M', 3, PeriodUnit.month, 1)),
    ]);
    expect(revenueCatOfferingData(offering), {
      'identifier': 'holiday',
      'packages': [
        {
          'identifier': 'annual_49',
          'productIdentifier': 'pro_annual_49',
          'priceString': r'$49.00',
          'currencyCode': 'USD',
          'subscriptionPeriod': 'P1Y',
          'freeTrial': {'priceString': r'$0.00', 'period': 'P1W', 'cycles': 1},
        },
        {
          'identifier': 'annual_59',
          'productIdentifier': 'pro_annual_59',
          'priceString': r'$49.00',
          'currencyCode': 'USD',
          'subscriptionPeriod': 'P1Y',
          'introductoryPrice': {
            'priceString': r'$9.99',
            'period': 'P1M',
            'cycles': 3,
          },
        },
      ],
    });
    expect(jsonDecode(jsonEncode(revenueCatOfferingData(offering))),
        isA<Map<String, dynamic>>());
    expect(revenueCatOfferingData(_offering([]))['packages'], isEmpty);
  });

  test('Android default option supplies its trial and introductory phases', () {
    const trial = PricingPhase(
        Period(PeriodUnit.day, 7, 'P7D'),
        RecurrenceMode.finiteRecurring,
        1,
        Price(r'$0.00', 0, 'USD'),
        OfferPaymentMode.freeTrial);
    const intro = PricingPhase(
        Period(PeriodUnit.month, 1, 'P1M'),
        RecurrenceMode.finiteRecurring,
        2,
        Price(r'$1.99', 1990000, 'USD'),
        OfferPaymentMode.discountedRecurringPayment);
    const option = SubscriptionOption(
        'trial',
        'pro:annual',
        'pro',
        [trial, intro],
        [],
        false,
        Period(PeriodUnit.year, 1, 'P1Y'),
        false,
        null,
        trial,
        intro,
        null,
        null);
    final data =
        revenueCatOfferingData(_offering([_package('annual', option: option)]));
    final row = (data['packages']! as List).single as Map;
    expect(row['freeTrial'],
        {'priceString': r'$0.00', 'period': 'P7D', 'cycles': 1});
    expect(row['introductoryPrice'],
        {'priceString': r'$1.99', 'period': 'P1M', 'cycles': 2});
  });

  test('purchases the selected package and reports its original exposure once',
      () async {
    final purchase = Completer<Object?>();
    native = (_) => purchase.future;
    var flushed = false;
    final event = _purchase('annual_49', flush: () async => flushed = true);
    final handler = revenueCatEventHandler(
      offering: _offering([_package('annual_59'), _package('annual_49')]),
      onCustomerInfo: customerInfos.add,
    );
    final handling = handler(event);
    await Future<void>.delayed(Duration.zero);
    expect(calls.single.method, 'purchasePackage');
    final args = calls.single.arguments as Map;
    expect(args['packageIdentifier'], 'annual_49');
    expect((args['presentedOfferingContext'] as Map)['offeringIdentifier'],
        'holiday');
    expect(reports, isEmpty);
    purchase.complete(_purchaseResult);
    await handling;
    expect(flushed, isTrue);
    expect(customerInfos.single.activeSubscriptions, ['pro_annual_49']);
    expect(reports, hasLength(1));
    expect(reports.single['exposure']['captureSessionNonce'], 'a' * 43);
    expect(reports.single['packageIdentifier'], 'annual_49');
    expect(reports.single['productIdentifier'], 'pro_annual_49');
    expect(
        reports.single.keys,
        unorderedEquals([
          'exposure',
          'eventId',
          'packageIdentifier',
          'productIdentifier',
          'reportedOccurredAtMicros',
        ]));
    expect(jsonEncode(reports), isNot(contains('private-customer')));
    expect(jsonEncode(reports), isNot(contains('private-transaction')));
  });

  test('unknown and malformed identifiers refuse before contacting RevenueCat',
      () async {
    final handler =
        revenueCatEventHandler(offering: _offering([_package('annual')]));
    for (final id in <Object?>['missing', '', null, 1]) {
      await expectLater(handler(_purchase(id)), throwsArgumentError);
    }
    expect(calls, isEmpty);
    expect(reports, isEmpty);
  });

  test('restore forwards customer information without reporting an outcome',
      () async {
    final handler = revenueCatEventHandler(
        offering: _offering([]), onCustomerInfo: customerInfos.add);
    await handler(const PaywallCustomEvent(
        paywallId: 'upgrade', eventName: 'revenuecat.restore', args: {}));
    expect(calls.single.method, 'restorePurchases');
    expect(customerInfos, hasLength(1));
    expect(reports, isEmpty);
  });

  test('failure and cancellation preserve native errors and never report',
      () async {
    final handler = revenueCatEventHandler(
        offering: _offering([_package('annual_49')]),
        onCustomerInfo: customerInfos.add);
    for (final code in [
      PurchasesErrorCode.networkError,
      PurchasesErrorCode.purchaseCancelledError,
      PurchasesErrorCode.paymentPendingError
    ]) {
      native = (_) async => throw PlatformException(code: '${code.index}');
      await expectLater(
          handler(_purchase('annual_49')),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', '${code.index}')));
    }
    expect(customerInfos, isEmpty);
    expect(reports, isEmpty);
  });

  test('onError handles errors without reporting or granting customer info',
      () async {
    final errors = <Object>[];
    final handler = revenueCatEventHandler(
        offering: _offering([]),
        onError: (error, _) => errors.add(error),
        onCustomerInfo: customerInfos.add);
    await handler(_purchase('unknown'));
    expect(errors.single, isArgumentError);
    expect(customerInfos, isEmpty);
    expect(reports, isEmpty);
  });

  test('reporting failure preserves a successful purchase', () async {
    reportStatus = 503;
    final errors = <Object>[];
    final handler = revenueCatEventHandler(
        offering: _offering([_package('annual_49')]),
        onCustomerInfo: customerInfos.add,
        onError: (error, _) => errors.add(error));
    await handler(_purchase('annual_49'));
    expect(customerInfos, hasLength(1));
    expect(errors, isEmpty);
    expect(reports, hasLength(1));
  });

  test('reset during checkout preserves success without reporting', () async {
    final purchase = Completer<Object?>();
    native = (_) => purchase.future;
    final handler = revenueCatEventHandler(
        offering: _offering([_package('annual_49')]),
        onCustomerInfo: customerInfos.add);
    final handling = handler(_purchase('annual_49'));
    await Future<void>.delayed(Duration.zero);
    expect(calls.single.method, 'purchasePackage');
    Restage.reset();
    purchase.complete(_purchaseResult);
    await handling;
    expect(customerInfos, hasLength(1));
    expect(reports, isEmpty);
  });

  test('unrelated and reserved commerce events are ignored', () async {
    final handler = revenueCatEventHandler(offering: _offering([]));
    for (final name in ['purchase', 'restore', 'continue']) {
      await handler(
          PaywallCustomEvent(paywallId: 'upgrade', eventName: name, args: {}));
    }
    await handler(const PaywallViewed(paywallId: 'upgrade'));
    expect(calls, isEmpty);
    expect(reports, isEmpty);
  });
}

PaywallCustomEvent _purchase(Object? id, {Future<void> Function()? flush}) {
  final event = PaywallCustomEvent(
      paywallId: 'upgrade',
      eventName: 'revenuecat.purchase',
      args: {'packageIdentifier': id});
  attachPurchaseExposure(event, prepare: () async {
    await flush?.call();
    return (
      captureSessionNonce: 'a' * 43,
      publicationBindingReference: _binding()
    );
  });
  return event;
}

Offering _offering(List<Package> packages) =>
    Offering('holiday', 'Holiday prices', const {}, packages);

Package _package(String id,
        {IntroductoryPrice? intro, SubscriptionOption? option}) =>
    Package(
        id,
        PackageType.custom,
        StoreProduct(
            'pro_$id', 'Annual subscription', 'Annual', 49, r'$49.00', 'USD',
            subscriptionPeriod: 'P1Y',
            introductoryPrice: intro,
            defaultOption: option),
        const PresentedOfferingContext('holiday', null, null));

const _customerInfo = <String, Object>{
  'entitlements': {'all': <String, Object>{}, 'active': <String, Object>{}},
  'allPurchaseDates': <String, Object>{},
  'activeSubscriptions': ['pro_annual_49'],
  'allPurchasedProductIdentifiers': ['pro_annual_49'],
  'nonSubscriptionTransactions': <Object>[],
  'firstSeen': '2026-01-01T00:00:00Z',
  'originalAppUserId': 'private-customer',
  'allExpirationDates': <String, Object>{},
  'requestDate': '2026-01-01T00:00:00Z',
};
const _purchaseResult = {
  'customerInfo': _customerInfo,
  'transaction': {
    'transactionIdentifier': 'private-transaction',
    'productIdentifier': 'pro_annual_49',
    'purchaseDate': '2026-01-01T00:00:00Z',
  },
};

MeasurementPublicationBindingReferenceV1 _binding() {
  final digest = CanonicalDigest('b' * 64);
  final binding = MeasurementPublicationBindingReferenceV1(
    publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
        authorityId: MeasurementPublicationAuthorityId('test.authority'),
        externalPublicationAuthorityRef: 'mpa1.${'A' * 32}',
        candidateReference: MeasurementPublicationCandidateReferenceV1(
            candidateDigest: digest,
            selectedPublicationManifestDigest: digest,
            declaredArtifactBytesDigest: digest,
            assembledPublicationUploadDigest: digest,
            measurementPublicationDraftDigest: digest),
        immutablePublicationDigest: digest,
        declaredArtifactBytesDigest: digest),
    bindingDigest: digest,
  );
  return binding;
}
// Exercises the SDK's runtime event association and real report transport.
// ignore_for_file: invalid_use_of_internal_member
