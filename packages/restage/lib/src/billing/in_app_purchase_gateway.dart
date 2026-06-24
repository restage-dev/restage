import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:restage_shared/restage_shared.dart' show OfferSignatureScheme;

import '../events/event_enums.dart' show PendingReason;
import 'anonymous_token.dart';
import 'billing_gateway.dart';
import 'signed_native_offer.dart';

/// Basic implementation backed by `package:in_app_purchase`.
///
/// This implementation supports a bounded purchase + restore flow. Renewals,
/// refund detection via transaction-update streams, and Play webhook
/// integration require host or server logic outside this gateway.
///
/// **Operational limits:**
/// - Each [purchase] call subscribes to [InAppPurchase.purchaseStream]
///   for the duration of the call and unsubscribes after the first
///   terminal status. StoreKit "Ask to Buy" / "SCA challenge" flows where
///   `pending` is followed minutes-to-hours later by `purchased` will not
///   surface the eventual approval — only the initial `pending` outcome.
///   Apps that need eventual approval handling should use a long-lived
///   purchase listener.
/// - [restore] uses a wall-clock timeout (default 5s) before declaring
///   "no purchases" because the underlying API does not emit a "done"
///   signal. On slow networks, restored purchases that arrive after the
///   timeout are not included in this call's result. Hosts that require
///   stronger restore completion semantics should layer that signal around
///   the gateway.
/// - **Android subscription base-plan selection.** A Google Play subscription
///   query returns one product entry per base-plan/offer. A plain [purchase]
///   selects the standard base-plan entry (never a discounted offer): with a
///   single base plan it buys that plan, and with **multiple base plans** it
///   fails closed ([RestageBillingErrorCodes.basePlanSelectionRequired]) unless
///   a `basePlanId` is given — it never buys an arbitrary `products.first`. To
///   apply a discounted offer use
///   [OfferCapableBillingGateway.purchaseWithOffer] with a [GoogleOffer]
///   (optionally scoped by `basePlanId`), which resolves the exact eligible
///   offer and fails closed on an ambiguous match. (Apple subscriptions are
///   unaffected; StoreKit selects the product directly and `basePlanId` is
///   ignored.)
final class InAppPurchaseGateway implements OfferCapableBillingGateway {
  /// [plugin] is injectable for tests; defaults to [InAppPurchase.instance].
  /// [restoreTimeout] bounds how long [restore] waits for restored purchases
  /// to arrive on [InAppPurchase.purchaseStream] before returning the
  /// accumulated set; the underlying API does not emit a "done" signal.
  ///
  /// [anonymousTokenProvider] supplies the value stamped onto
  /// `PurchaseParam.applicationUserName` (and `restorePurchases`). The
  /// platform routes this to Apple `appAccountToken` and Google
  /// `obfuscatedAccountId`. The provider's value is validated as a
  /// canonical-form UUID before being passed; non-UUID values are
  /// silently dropped by StoreKit 2, so the guard keeps the SDK honest.
  InAppPurchaseGateway({
    InAppPurchase? plugin,
    Duration restoreTimeout = const Duration(seconds: 5),
    Future<String?> Function()? anonymousTokenProvider,
  })  : _plugin = plugin ?? InAppPurchase.instance,
        _restoreTimeout = restoreTimeout,
        _anonymousTokenProvider = anonymousTokenProvider;

  final InAppPurchase _plugin;
  final Duration _restoreTimeout;
  final Future<String?> Function()? _anonymousTokenProvider;

  @override
  Future<PurchaseOutcome> purchase(String productId, {String? basePlanId}) {
    return _purchaseFlow(
      productId: productId,
      buildParam: (products) async {
        // Resolve the anonymous token BEFORE the stream listener attaches
        // (the builder runs ahead of it). The platform store can re-deliver
        // a queued pending transaction on first listener attach; resolving
        // here closes the window where such a re-delivery could complete a
        // transaction this call never initiated.
        final applicationUserName = await resolveApplicationUserNameForStamping(
            _anonymousTokenProvider);
        // A Google Play subscription query fans out to one entry per
        // base-plan/offer. Select the intended standard base-plan entry — failing
        // closed on ambiguity — rather than an arbitrary `products.first`, which
        // could be a non-default base plan or a discounted offer the user never
        // chose. Apple subscriptions and one-time products resolve to a single
        // entry, so they take the direct path (basePlanId has no meaning there).
        if (_isGoogleSubscriptionQuery(products)) {
          return buildGooglePlayBasePlanParam(
            productId: productId,
            products: products,
            basePlanId: basePlanId,
            applicationUserName: applicationUserName,
          );
        }
        return PurchaseParam(
          productDetails: products.first,
          applicationUserName: applicationUserName,
        );
      },
      classifyBuyError: (_) => RestageBillingErrorCodes.buyFailed,
      unresolvedErrorCode: RestageBillingErrorCodes.basePlanSelectionRequired,
      unresolvedMessage: basePlanId == null
          ? 'This subscription has multiple base plans; specify a basePlanId '
              'to choose one.'
          : 'No base plan matched basePlanId "$basePlanId" for this product.',
    );
  }

  @override
  Future<PurchaseOutcome> purchaseWithOffer({
    required String productId,
    required SignedNativeOffer offer,
    required String appAccountToken,
  }) {
    // Dispatch on the offer variant and the platform. Each store transports
    // only its own kind of offer — an Apple legacy-scheme signature rides
    // StoreKit 2 on an Apple platform; a Google offer rides Play Billing on
    // Android. Anything else (an unknown future variant, a non-legacy Apple
    // scheme, or an offer on the wrong store) falls through to a fail-closed
    // default: never fall back to a full-price purchase — the host/paywall
    // decides what to do with an unavailable offer.
    if (offer is AppleSignedOffer &&
        offer.scheme == OfferSignatureScheme.legacy &&
        _isApplePlatform) {
      return _purchaseFlow(
        productId: productId,
        buildParam: (products) async => buildApplePromotionalOfferParam(
          product: products.first,
          appAccountToken: appAccountToken,
          offer: offer,
        ),
        classifyBuyError: _classifyOfferBuyError,
      );
    }
    if (offer is GoogleOffer && _isAndroidPlatform) {
      return _purchaseFlow(
        productId: productId,
        buildParam: (products) async => buildGooglePlayOfferParam(
          productId: productId,
          products: products,
          appAccountToken: appAccountToken,
          offer: offer,
        ),
        classifyBuyError: _classifyOfferBuyError,
      );
    }
    return Future<PurchaseOutcome>.value(
      PurchaseOutcome.failed(
        productId: productId,
        errorCode: RestageBillingErrorCodes.offerUnavailable,
        message: 'This gateway cannot transport the requested offer.',
      ),
    );
  }

  /// The shared purchase flow: availability + product lookup, then drive the
  /// store purchase built by [buildParam] and resolve the first terminal
  /// status off the purchase stream. [buildParam] receives the full product
  /// list a query returns (a subscription query fans out to one entry per
  /// base-plan/offer on Android) and may return `null` to fail closed with
  /// `offerUnavailable` — an offer that could not be resolved to an eligible
  /// store offer must never silently charge a different plan. [classifyBuyError]
  /// maps a thrown `buyNonConsumable` error to a [RestageBillingErrorCodes]
  /// value.
  Future<PurchaseOutcome> _purchaseFlow({
    required String productId,
    required Future<PurchaseParam?> Function(List<ProductDetails> products)
        buildParam,
    required String Function(Object error) classifyBuyError,
    String unresolvedErrorCode = RestageBillingErrorCodes.offerUnavailable,
    String unresolvedMessage =
        'The requested offer is not available for this product.',
  }) async {
    if (!await _plugin.isAvailable()) {
      return PurchaseOutcome.failed(
        productId: productId,
        errorCode: RestageBillingErrorCodes.unavailable,
        message: 'In-app purchase is unavailable on this device.',
      );
    }

    final response = await _plugin.queryProductDetails(<String>{productId});
    if (response.notFoundIDs.contains(productId) ||
        response.productDetails.isEmpty) {
      return PurchaseOutcome.failed(
        productId: productId,
        errorCode: RestageBillingErrorCodes.productNotFound,
        message: 'Store does not recognize productId: $productId',
      );
    }

    final purchaseParam = await buildParam(response.productDetails);
    if (purchaseParam == null) {
      return PurchaseOutcome.failed(
        productId: productId,
        errorCode: unresolvedErrorCode,
        message: unresolvedMessage,
      );
    }
    // Report the charged amount from the product the purchase actually targets
    // (the matched offer entry on Android), not an arbitrary first entry.
    final product = purchaseParam.productDetails;

    final completer = Completer<PurchaseOutcome>();
    late final StreamSubscription<List<PurchaseDetails>> sub;
    sub = _plugin.purchaseStream.listen((purchases) {
      for (final p in purchases) {
        if (p.productID != productId) continue;
        if (completer.isCompleted) continue;
        switch (p.status) {
          case PurchaseStatus.pending:
            completer.complete(
              PurchaseOutcome.pending(
                productId: productId,
                reason: PendingReason.paymentPending,
              ),
            );
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            completer.complete(
              PurchaseOutcome.succeeded(
                productId: productId,
                transactionId: p.purchaseID ?? '',
                verificationData: p.verificationData.serverVerificationData,
                priceMicros: (product.rawPrice * 1000000).toInt(),
                currency: product.currencyCode,
              ),
            );
            if (p.pendingCompletePurchase) {
              unawaited(_plugin.completePurchase(p));
            }
          case PurchaseStatus.canceled:
            completer.complete(
              PurchaseOutcome.cancelled(productId: productId),
            );
          case PurchaseStatus.error:
            completer.complete(
              PurchaseOutcome.failed(
                productId: productId,
                errorCode: p.error?.code ?? RestageBillingErrorCodes.unknown,
                message: p.error?.message ?? 'Purchase error',
                platformErrorCode: p.error?.details?.toString(),
              ),
            );
        }
      }
    });

    try {
      await _plugin.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      if (!completer.isCompleted) {
        completer.complete(
          PurchaseOutcome.failed(
            productId: productId,
            errorCode: classifyBuyError(e),
            message: e.toString(),
          ),
        );
      }
    }

    final outcome = await completer.future;
    await sub.cancel();
    return outcome;
  }

  /// Whether [products] is a Google Play *subscription* query result — a list
  /// of per-base-plan/offer entries that needs base-plan resolution. A one-time
  /// Google product (`subscriptionIndex` null) and Apple products are not, and
  /// resolve to a single entry.
  static bool _isGoogleSubscriptionQuery(List<ProductDetails> products) =>
      products.any(
          (p) => p is GooglePlayProductDetails && p.subscriptionIndex != null);

  /// Whether the current platform is Android — the only platform whose Play
  /// Billing transport can carry a Google subscription offer token.
  static bool get _isAndroidPlatform =>
      defaultTargetPlatform == TargetPlatform.android;

  /// Whether the current platform is an Apple store (iOS / macOS) — the only
  /// platforms whose StoreKit transport can carry an Apple promotional offer.
  static bool get _isApplePlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Maps a thrown offer-purchase error to a billing code: a device that cannot
  /// carry an SK2 promotional offer surfaces the typed "offer unavailable"
  /// contract; anything else stays a generic buy failure. Both fail closed.
  static String _classifyOfferBuyError(Object error) {
    return error is PlatformException && _storeKit2CannotCarryOffer(error)
        ? RestageBillingErrorCodes.offerUnavailable
        : RestageBillingErrorCodes.buyFailed;
  }

  /// Whether [error] signals StoreKit 2 cannot carry an offer on this device
  /// (StoreKit 1 active, or a pre-SK2 OS version), as opposed to a generic
  /// purchase failure. The exact codes are confirmed against a real device
  /// store-sandbox session; an unrecognized code is treated as a generic
  /// failure, which already fails closed.
  static bool _storeKit2CannotCarryOffer(PlatformException error) =>
      error.code == 'storekit2_not_enabled' ||
      error.code.contains('unsupported_platform');

  @override
  Future<RestoreOutcome> restore() async {
    if (!await _plugin.isAvailable()) {
      return RestoreOutcome.failed(
        errorCode: RestageBillingErrorCodes.unavailable,
        message: 'In-app purchase is unavailable on this device.',
      );
    }

    final restored = <String>{};
    late final StreamSubscription<List<PurchaseDetails>> sub;
    sub = _plugin.purchaseStream.listen((purchases) {
      for (final p in purchases) {
        if (p.status == PurchaseStatus.restored) {
          restored.add(p.productID);
          if (p.pendingCompletePurchase) {
            unawaited(_plugin.completePurchase(p));
          }
        }
      }
    });

    final applicationUserName =
        await resolveApplicationUserNameForStamping(_anonymousTokenProvider);
    try {
      await _plugin.restorePurchases(
        applicationUserName: applicationUserName,
      );
    } catch (e) {
      await sub.cancel();
      return RestoreOutcome.failed(
        errorCode: RestageBillingErrorCodes.restoreFailed,
        message: e.toString(),
      );
    }

    // `restorePurchases` emits restored items via [purchaseStream] with no
    // terminator event. Wait a bounded window for entries to arrive, then
    // resolve. A typed restore-complete signal can replace this bounded wait
    // when the host/store integration provides one.
    await Future<void>.delayed(_restoreTimeout);
    await sub.cancel();

    if (restored.isEmpty) {
      return RestoreOutcome.noPurchases();
    }
    return RestoreOutcome.succeeded(
      restoredProductIds: restored.toList(growable: false),
    );
  }
}

/// Resolves the value to pass as `PurchaseParam.applicationUserName`.
///
/// Returns null when [provider] is null or yields null, or when the
/// resolved value is not a canonical-form UUID. The guard prevents the
/// SDK from silently passing a malformed token to StoreKit 2, which
/// drops non-UUID values without a diagnostic.
@visibleForTesting
Future<String?> resolveApplicationUserNameForStamping(
  Future<String?> Function()? provider,
) async {
  if (provider == null) return null;
  final value = await provider();
  if (value == null) return null;
  return AnonymousTokenStore.isValidUuid(value) ? value : null;
}

/// Builds the StoreKit-2 purchase param that carries an Apple promotional
/// [offer]'s signature, stamping [appAccountToken] as the application user name
/// (Apple `appAccountToken`). The signature commits to that token, so it must be
/// the same value the signature was minted with. Pure — exposed for testing the
/// signature field mapping without a store.
@visibleForTesting
Sk2PurchaseParam buildApplePromotionalOfferParam({
  required ProductDetails product,
  required String appAccountToken,
  required AppleSignedOffer offer,
}) {
  return Sk2PurchaseParam(
    productDetails: product,
    applicationUserName: appAccountToken,
    promotionalOffer: SK2PromotionalOffer(
      offerId: offer.offerId,
      signature: SK2SubscriptionOfferSignature(
        keyID: offer.keyIdentifier,
        nonce: offer.nonce,
        timestamp: offer.timestampMs,
        signature: offer.signatureBase64,
      ),
    ),
  );
}

/// Resolves the Google Play purchase param that applies [offer] to one of
/// [products], stamping [appAccountToken] as the application user name (Play
/// `obfuscatedAccountId`).
///
/// [products] is the per-offer `GooglePlayProductDetails` list a subscription
/// query returns — one entry per base-plan/offer, each with its own eligible
/// `offerToken`. Only entries for [productId] are considered, so an offer id
/// that happens to collide across different products can never cross-match. The
/// match is strict and fail-closed: it selects the entry whose discounted offer
/// id equals [GoogleOffer.offerId] (a plain base plan has a null offer id and is
/// never matched), additionally requiring the base-plan id to match when
/// [GoogleOffer.basePlanId] is set. It returns `null` — so the gateway fails
/// closed with `offerUnavailable` rather than charging a plan the user didn't
/// choose — when zero entries match, or when more than one matches (the same
/// offer id under multiple base plans of [productId] with no base-plan id to
/// disambiguate). Pure — exposed for testing the resolution without a store.
@visibleForTesting
GooglePlayPurchaseParam? buildGooglePlayOfferParam({
  required String productId,
  required List<ProductDetails> products,
  required String appAccountToken,
  required GoogleOffer offer,
}) {
  final matches = <GooglePlayProductDetails>[];
  for (final product in products) {
    if (product is! GooglePlayProductDetails) continue;
    if (product.id != productId) continue;
    final index = product.subscriptionIndex;
    if (index == null) continue;
    final details = product.productDetails.subscriptionOfferDetails;
    if (details == null || index >= details.length) continue;
    final candidate = details[index];
    // A plain base plan has a null offer id and is never a promotional offer.
    if (candidate.offerId == null || candidate.offerId != offer.offerId) {
      continue;
    }
    if (offer.basePlanId != null && candidate.basePlanId != offer.basePlanId) {
      continue;
    }
    matches.add(product);
  }
  if (matches.length != 1) return null;
  final match = matches.first;
  return GooglePlayPurchaseParam(
    productDetails: match,
    applicationUserName: appAccountToken,
    offerToken: match.offerToken,
  );
}

/// Resolves the Google Play purchase param for a plain (no-discount) base-plan
/// purchase of [productId], optionally narrowed to [basePlanId].
///
/// [products] is the per-offer `GooglePlayProductDetails` list a subscription
/// query returns — one entry per base-plan/offer. Only **standard base-plan
/// entries** (those with a null offer id) for [productId] are eligible: a plain
/// purchase must never silently apply a discounted offer the user didn't choose,
/// so offer entries (non-null offer id) are skipped entirely.
///
/// The match is strict and fail-closed. With [basePlanId] null it resolves the
/// sole base plan, returning `null` when the subscription has **more than one**
/// base plan (ambiguous — the caller must choose one). With [basePlanId] set it
/// resolves that base plan, returning `null` when no standard base-plan entry
/// matches. Returning `null` lets the gateway fail closed rather than charge a
/// base plan the caller didn't intend. [applicationUserName] is the (optional)
/// store-account token stamped onto the purchase. Pure — exposed for testing the
/// resolution without a store.
@visibleForTesting
GooglePlayPurchaseParam? buildGooglePlayBasePlanParam({
  required String productId,
  required List<ProductDetails> products,
  required String? basePlanId,
  required String? applicationUserName,
}) {
  final matches = <GooglePlayProductDetails>[];
  for (final product in products) {
    if (product is! GooglePlayProductDetails) continue;
    if (product.id != productId) continue;
    final index = product.subscriptionIndex;
    if (index == null) continue;
    final details = product.productDetails.subscriptionOfferDetails;
    if (details == null || index >= details.length) continue;
    final candidate = details[index];
    // Only standard base-plan entries are eligible — never a discounted offer.
    if (candidate.offerId != null) continue;
    if (basePlanId != null && candidate.basePlanId != basePlanId) continue;
    matches.add(product);
  }
  if (matches.length != 1) return null;
  final match = matches.first;
  return GooglePlayPurchaseParam(
    productDetails: match,
    applicationUserName: applicationUserName,
    offerToken: match.offerToken,
  );
}
