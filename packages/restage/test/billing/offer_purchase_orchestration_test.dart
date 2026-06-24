import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records purchase / purchaseWithOffer calls and returns canned outcomes.
class _RecordingOfferGateway implements OfferCapableBillingGateway {
  final List<({String productId, String? basePlanId})> plainPurchases =
      <({String productId, String? basePlanId})>[];
  final List<({String productId, SignedNativeOffer offer, String token})>
      offerPurchases =
      <({String productId, SignedNativeOffer offer, String token})>[];

  @override
  Future<PurchaseOutcome> purchase(String productId,
      {String? basePlanId}) async {
    plainPurchases.add((productId: productId, basePlanId: basePlanId));
    return PurchaseOutcome.succeeded(
      productId: productId,
      transactionId: 'plain',
      verificationData: 'v',
      priceMicros: 1,
      currency: 'USD',
    );
  }

  @override
  Future<PurchaseOutcome> purchaseWithOffer({
    required String productId,
    required SignedNativeOffer offer,
    required String appAccountToken,
  }) async {
    offerPurchases
        .add((productId: productId, offer: offer, token: appAccountToken));
    return PurchaseOutcome.succeeded(
      productId: productId,
      transactionId: 'offer',
      verificationData: 'v',
      priceMicros: 1,
      currency: 'USD',
    );
  }

  @override
  Future<RestoreOutcome> restore() async => RestoreOutcome.noPurchases();
}

/// A plain (non-offer-capable) gateway.
class _PlainGateway implements BillingGateway {
  bool purchaseCalled = false;
  String? lastBasePlanId;
  @override
  Future<PurchaseOutcome> purchase(String productId,
      {String? basePlanId}) async {
    purchaseCalled = true;
    lastBasePlanId = basePlanId;
    return PurchaseOutcome.succeeded(
      productId: productId,
      transactionId: 'plain',
      verificationData: 'v',
      priceMicros: 1,
      currency: 'USD',
    );
  }

  @override
  Future<RestoreOutcome> restore() async => RestoreOutcome.noPurchases();
}

/// Captures the mint request and returns a configurable response.
class _SpyOfferClient extends RestageRpcClient {
  _SpyOfferClient({this.response})
      : super(
          baseUrl: 'https://offers.test',
          apiKey: 'k',
          httpClient: MockClient((_) async => http.Response('', 200)),
        );

  OfferSignatureResponse? response;
  final List<OfferSignatureRequest> mintCalls = <OfferSignatureRequest>[];

  @override
  Future<OfferSignatureResponse?> mintOfferSignature(
    OfferSignatureRequest request,
  ) async {
    mintCalls.add(request);
    return response;
  }
}

OfferSignatureResponse _legacyResponse() => const OfferSignatureResponse(
      scheme: OfferSignatureScheme.legacy,
      keyIdentifier: 'KEY123',
      nonce: 'a3f1c2d4-0000-4000-8000-000000000001',
      timestampMs: 1718312345678,
      signatureBase64: 'MEUCIQ...base64der...==',
    );

void main() {
  setUp(() {
    Restage.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The orchestration branches by store platform; pin Apple by default so the
    // server-mint path is deterministic regardless of the test host. The
    // Android (Google) group overrides this.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('threads ONE account token into both the mint request and the purchase',
      () async {
    final gateway = _RecordingOfferGateway();
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://offers.test',
      billingGateway: gateway,
    );
    Restage.debugRestageRpcClient =
        _SpyOfferClient(response: _legacyResponse());

    final outcome = await Restage.purchaseProduct('pro', offerId: 'winback');

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect(gateway.offerPurchases, hasLength(1));
    expect(gateway.plainPurchases, isEmpty);

    final spy = Restage.debugRestageRpcClient! as _SpyOfferClient;
    final mintToken = spy.mintCalls.single.appAccountToken;
    final purchaseToken = gateway.offerPurchases.single.token;
    expect(mintToken, isNotEmpty);
    expect(purchaseToken, mintToken,
        reason: 'the signature commits to the token, so they must match');

    final offer = gateway.offerPurchases.single.offer as AppleSignedOffer;
    expect(offer.offerId, 'winback');
    expect(offer.keyIdentifier, 'KEY123');
  });

  test('no signature -> offerUnavailable, never a silent full-price purchase',
      () async {
    final gateway = _RecordingOfferGateway();
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://offers.test',
      billingGateway: gateway,
    );
    Restage.debugRestageRpcClient = _SpyOfferClient(); // response: null

    final outcome = await Restage.purchaseProduct('pro', offerId: 'winback');

    expect((outcome as PurchaseOutcomeFailed).errorCode,
        RestageBillingErrorCodes.offerUnavailable);
    expect(gateway.offerPurchases, isEmpty);
    expect(gateway.plainPurchases, isEmpty,
        reason: 'must not fall back to a full-price purchase');
  });

  test('a non-offer-capable gateway -> offerUnavailable', () async {
    final gateway = _PlainGateway();
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://offers.test',
      billingGateway: gateway,
    );

    final outcome = await Restage.purchaseProduct('pro', offerId: 'winback');

    expect((outcome as PurchaseOutcomeFailed).errorCode,
        RestageBillingErrorCodes.offerUnavailable);
    expect(gateway.purchaseCalled, isFalse);
  });

  test('a non-legacy scheme -> offerUnavailable, no offer purchase', () async {
    final gateway = _RecordingOfferGateway();
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://offers.test',
      billingGateway: gateway,
    );
    Restage.debugRestageRpcClient = _SpyOfferClient(
      response: const OfferSignatureResponse(
        scheme: OfferSignatureScheme.jws,
        keyIdentifier: 'K',
        nonce: 'n',
        timestampMs: 1,
        signatureBase64: 's',
      ),
    );

    final outcome = await Restage.purchaseProduct('pro', offerId: 'winback');

    expect((outcome as PurchaseOutcomeFailed).errorCode,
        RestageBillingErrorCodes.offerUnavailable);
    expect(gateway.offerPurchases, isEmpty);
  });

  test('no offerId -> the plain purchase path', () async {
    final gateway = _RecordingOfferGateway();
    Restage.configure(apiKey: 'rs_pk_test', billingGateway: gateway);

    final outcome = await Restage.purchaseProduct('pro');

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect(gateway.plainPurchases, [(productId: 'pro', basePlanId: null)]);
    expect(gateway.offerPurchases, isEmpty);
  });

  test('basePlanId with no offerId routes to the plain path with the base plan',
      () async {
    // Runs under the default iOS platform: the facade threads basePlanId to the
    // gateway unconditionally (the gateway ignores it where base plans don't
    // apply), so cross-platform call sites can pass it without branching.
    final gateway = _RecordingOfferGateway();
    Restage.configure(apiKey: 'rs_pk_test', billingGateway: gateway);

    final outcome = await Restage.purchaseProduct('pro', basePlanId: 'annual');

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect(gateway.plainPurchases, [(productId: 'pro', basePlanId: 'annual')]);
    expect(gateway.offerPurchases, isEmpty,
        reason: 'a base-plan selection is not an offer');
  });

  test('a present-but-empty offerId -> offerUnavailable, never full price',
      () async {
    final gateway = _RecordingOfferGateway();
    Restage.configure(apiKey: 'rs_pk_test', billingGateway: gateway);

    final outcome = await Restage.purchaseProduct('pro', offerId: '');

    expect((outcome as PurchaseOutcomeFailed).errorCode,
        RestageBillingErrorCodes.offerUnavailable);
    expect(gateway.plainPurchases, isEmpty,
        reason:
            'a requested (if malformed) offer must not silently full-price');
    expect(gateway.offerPurchases, isEmpty);
  });

  test('an offer on an unsupported platform -> offerUnavailable, never buys',
      () async {
    final gateway = _RecordingOfferGateway();
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://offers.test',
      billingGateway: gateway,
    );
    Restage.debugRestageRpcClient =
        _SpyOfferClient(response: _legacyResponse());
    // A platform with no native offer transport (e.g. desktop/web).
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final outcome = await Restage.purchaseProduct('pro', offerId: 'winback');

    expect((outcome as PurchaseOutcomeFailed).errorCode,
        RestageBillingErrorCodes.offerUnavailable);
    expect(gateway.offerPurchases, isEmpty);
    expect(gateway.plainPurchases, isEmpty,
        reason: 'an unsupported platform must not silently full-price');
  });

  group('Android (Google offer path)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('builds a GoogleOffer and dispatches it, with NO server mint',
        () async {
      final gateway = _RecordingOfferGateway();
      Restage.configure(
        apiKey: 'rs_pk_test',
        baseUrl: 'https://offers.test',
        billingGateway: gateway,
      );
      // A server client is configured but must NOT be used on Android — Google
      // resolves the offer client-side, no signature mint.
      final spy = _SpyOfferClient(response: _legacyResponse());
      Restage.debugRestageRpcClient = spy;

      final outcome = await Restage.purchaseProduct('pro', offerId: 'winback');

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      expect(gateway.offerPurchases, hasLength(1));
      expect(gateway.plainPurchases, isEmpty);
      final offer = gateway.offerPurchases.single.offer;
      expect(offer, isA<GoogleOffer>());
      expect((offer as GoogleOffer).offerId, 'winback');
      expect(gateway.offerPurchases.single.token, isNotEmpty);
      expect(spy.mintCalls, isEmpty,
          reason: 'Google resolves client-side; never mint a server signature');
    });

    test('offerId + basePlanId scopes the Google offer to that base plan',
        () async {
      final gateway = _RecordingOfferGateway();
      Restage.configure(apiKey: 'rs_pk_test', billingGateway: gateway);

      final outcome = await Restage.purchaseProduct('pro',
          offerId: 'winback', basePlanId: 'annual');

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      expect(gateway.offerPurchases, hasLength(1));
      final offer = gateway.offerPurchases.single.offer as GoogleOffer;
      expect(offer.offerId, 'winback');
      expect(offer.basePlanId, 'annual',
          reason: 'the facade threads basePlanId into the Google offer');
    });

    test('a Google offer purchase needs no configured service URL', () async {
      final gateway = _RecordingOfferGateway();
      // No baseUrl and no entitlement client at all: Google needs no server.
      Restage.configure(apiKey: 'rs_pk_test', billingGateway: gateway);

      final outcome = await Restage.purchaseProduct('pro', offerId: 'winback');

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      expect(gateway.offerPurchases, hasLength(1));
      expect(gateway.offerPurchases.single.offer, isA<GoogleOffer>());
    });

    test('a present-but-empty offerId still fails closed on Android', () async {
      final gateway = _RecordingOfferGateway();
      Restage.configure(apiKey: 'rs_pk_test', billingGateway: gateway);

      final outcome = await Restage.purchaseProduct('pro', offerId: '');

      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.offerUnavailable);
      expect(gateway.offerPurchases, isEmpty);
      expect(gateway.plainPurchases, isEmpty);
    });
  });
}
