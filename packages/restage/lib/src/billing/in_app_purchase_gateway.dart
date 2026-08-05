import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        debugPrint,
        defaultTargetPlatform,
        internal,
        visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show ProductType, RecurrenceMode;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart'
    show SK2ProductType;
import 'package:restage_shared/restage_shared.dart'
    show
        AppleAcceptedStoreEvidence,
        CreatePurchaseIntentRequest,
        EntitlementSummary,
        GoogleAcceptedStoreEvidence,
        IntentBoundOfferSignatureRequest,
        OfferSignatureScheme,
        PurchaseIntentDisposition,
        ReportTransactionRequest,
        ReportTransactionResponse;

import '../events/event_enums.dart' show PendingReason;
import '../restage_rpc_client/restage_rpc_client.dart';
import 'anonymous_token.dart';
import 'billing_gateway.dart';
import 'purchase_attribution.dart';
import 'purchase_coordinator_delegate.dart';
import 'purchase_platform_adapter.dart';
import 'purchase_token_digest.dart';
import 'signed_native_offer.dart';

part 'purchase_coordinator.dart';

enum _SubscriptionProductVerdict {
  supported,
  unsupported,
  indeterminate,
}

/// Basic implementation backed by `package:in_app_purchase`.
///
/// When installed through `Restage.configure`, the SDK owns one long-lived
/// purchase listener plus native recovery drains. Constructing and invoking the
/// gateway directly retains the bounded call-scoped behavior for compatibility.
///
/// **Operational limits:**
/// - A directly-invoked [purchase] call subscribes to
///   [InAppPurchase.purchaseStream]
///   for the duration of the call and unsubscribes after the first
///   terminal status. StoreKit "Ask to Buy" / "SCA challenge" flows where
///   `pending` is followed minutes-to-hours later by `purchased` will not
///   surface the eventual approval — only the initial `pending` outcome.
///   Apps that need eventual approval handling should install the gateway
///   through `Restage.configure`, which owns the long-lived listener and
///   durable server-reporting lifecycle.
/// - Configure-owned durable billing currently accepts auto-renewing
///   subscriptions only. One-time products fail before intent creation or
///   store UI. Google Play prepaid base plans are not accepted. Direct gateway
///   calls retain their legacy product behavior.
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
  /// [anonymousTokenProvider] supplies the restore identity and the legacy
  /// direct-invocation stamp. Configure-owned purchases instead stamp the
  /// durably committed purchase-intent UUID.
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
  PurchaseCoordinatorDelegate? _purchaseCoordinator;

  @override
  Future<PurchaseOutcome> purchase(String productId, {String? basePlanId}) {
    final coordinator = _purchaseCoordinator;
    if (coordinator != null) {
      return coordinator.purchase(productId, basePlanId: basePlanId);
    }
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
    final coordinator = _purchaseCoordinator;
    if (coordinator != null) {
      return coordinator.purchaseWithOffer(
        productId: productId,
        offer: offer,
      );
    }
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
                transactionId: p.purchaseID,
                verificationData: p.verificationData.serverVerificationData,
                priceMicros: _priceMicros(product),
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
    final coordinator = _purchaseCoordinator;
    if (coordinator != null) return coordinator.restore();
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

  Future<_PreparedPurchaseResult> _prepareCoordinatedPurchase({
    required String productId,
    required String? basePlanId,
    required String? offerId,
    required String store,
    required bool Function() isCurrentEpoch,
  }) async {
    if (!isCurrentEpoch()) {
      return _PreparedPurchaseResult.failure(
        _coordinatedConfigurationChanged(productId),
      );
    }
    try {
      if (!await _plugin.isAvailable()) {
        return _PreparedPurchaseResult.failure(
          PurchaseOutcomeFailed(
            productId: productId,
            errorCode: RestageBillingErrorCodes.unavailable,
            message: 'In-app purchase is unavailable on this device.',
          ),
        );
      }
    } on Object {
      return _PreparedPurchaseResult.failure(
        PurchaseOutcomeFailed(
          productId: productId,
          errorCode: RestageBillingErrorCodes.unavailable,
          message: 'In-app purchase is unavailable on this device.',
        ),
      );
    }
    if (!isCurrentEpoch()) {
      return _PreparedPurchaseResult.failure(
        _coordinatedConfigurationChanged(productId),
      );
    }

    ProductDetailsResponse response;
    try {
      response = await _plugin.queryProductDetails(<String>{productId});
    } on Object {
      return _PreparedPurchaseResult.failure(
        PurchaseOutcomeFailed(
          productId: productId,
          errorCode: RestageBillingErrorCodes.buyFailed,
          message: 'The store product could not be verified.',
        ),
      );
    }
    if (!isCurrentEpoch()) {
      return _PreparedPurchaseResult.failure(
        _coordinatedConfigurationChanged(productId),
      );
    }
    if (response.error != null ||
        response.notFoundIDs.contains(productId) ||
        response.productDetails.isEmpty) {
      return _PreparedPurchaseResult.failure(
        PurchaseOutcomeFailed(
          productId: productId,
          errorCode: RestageBillingErrorCodes.productNotFound,
          message: 'The store did not recognize the requested product.',
        ),
      );
    }

    _PreparedPurchase? prepared;
    String unresolvedCode = RestageBillingErrorCodes.offerUnavailable;
    String unresolvedMessage =
        'The requested offer is not available for this product.';
    if (store == 'appStore') {
      // Promotional offers in this path use StoreKit 2 purchase parameters.
      // Exclude StoreKit 1 products before committing an intent so the offer
      // cannot be silently dropped when the store UI opens.
      final matches = response.productDetails
          .where((product) =>
              product.id == productId &&
              _isSupportedSubscriptionProduct(product, store) &&
              (offerId == null || product is AppStoreProduct2Details))
          .toList(growable: false);
      if (matches.length == 1) {
        prepared = _PreparedPurchase(
          product: matches.single,
          resolvedBasePlanId: null,
          offerId: offerId,
        );
      }
    } else if (store == 'playStore') {
      final GooglePlayProductDetails? selected;
      if (offerId != null) {
        selected = _resolveGooglePlayOfferProduct(
          productId: productId,
          products: response.productDetails,
          basePlanId: basePlanId,
          offerId: offerId,
        );
      } else {
        selected = _resolveGooglePlayBasePlanProduct(
          productId: productId,
          products: response.productDetails,
          basePlanId: basePlanId,
        );
        unresolvedCode = RestageBillingErrorCodes.basePlanSelectionRequired;
        unresolvedMessage = basePlanId == null
            ? 'This subscription requires an explicit base plan.'
            : 'The requested base plan is unavailable.';
      }
      if (selected != null &&
          _isSupportedSubscriptionProduct(selected, store)) {
        prepared = _PreparedPurchase(
          product: selected,
          resolvedBasePlanId: _googleBasePlanId(selected),
          offerId: offerId,
        );
      }
    }

    if (prepared == null) {
      final hasSupportedSubscription = response.productDetails.any(
        (product) =>
            product.id == productId &&
            _isSupportedSubscriptionProduct(product, store),
      );
      return _PreparedPurchaseResult.failure(
        PurchaseOutcomeFailed(
          productId: productId,
          errorCode: hasSupportedSubscription
              ? unresolvedCode
              : RestageBillingErrorCodes.buyFailed,
          message: hasSupportedSubscription
              ? unresolvedMessage
              : 'Only auto-renewing subscriptions are supported.',
        ),
      );
    }

    if (!isCurrentEpoch()) {
      return _PreparedPurchaseResult.failure(
        _coordinatedConfigurationChanged(productId),
      );
    }
    return _PreparedPurchaseResult.success(prepared);
  }

  Future<_SubscriptionProductVerdict> _verifyCoordinatedSubscriptionProduct({
    required String productId,
    required String store,
    required bool Function() isCurrentEpoch,
    required Duration attemptTimeout,
  }) async {
    if (!isCurrentEpoch()) {
      return _SubscriptionProductVerdict.indeterminate;
    }
    ProductDetailsResponse response;
    try {
      response = await _plugin
          .queryProductDetails(<String>{productId}).timeout(attemptTimeout);
    } on Object {
      return _SubscriptionProductVerdict.indeterminate;
    }
    if (!isCurrentEpoch() || response.error != null) {
      return _SubscriptionProductVerdict.indeterminate;
    }
    if (response.notFoundIDs.contains(productId)) {
      // A temporarily unavailable catalog or locale can make an existing
      // product look absent, so absence is not a definitive product verdict.
      return _SubscriptionProductVerdict.indeterminate;
    }
    final products = response.productDetails
        .where((product) => product.id == productId)
        .toList(growable: false);
    if (!isCurrentEpoch() || products.isEmpty) {
      return _SubscriptionProductVerdict.indeterminate;
    }
    var sawUnrecognizedSubtype = false;
    for (final product in products) {
      if (!_isRecognizedSubscriptionProductSubtype(product, store)) {
        sawUnrecognizedSubtype = true;
        continue;
      }
      if (_isSupportedSubscriptionProduct(product, store)) {
        return isCurrentEpoch()
            ? _SubscriptionProductVerdict.supported
            : _SubscriptionProductVerdict.indeterminate;
      }
    }
    if (sawUnrecognizedSubtype) {
      return _SubscriptionProductVerdict.indeterminate;
    }
    return isCurrentEpoch()
        ? _SubscriptionProductVerdict.unsupported
        : _SubscriptionProductVerdict.indeterminate;
  }

  Future<PurchaseOutcomeFailed?> _launchCoordinatedPurchase({
    required _PreparedPurchase prepared,
    required SignedNativeOffer? offer,
    required String purchaseIntentId,
    required bool Function() isCurrentEpoch,
  }) async {
    if (!isCurrentEpoch()) {
      return _coordinatedConfigurationChanged(prepared.product.id);
    }
    final purchaseParam = prepared.buildParam(
      purchaseIntentId: purchaseIntentId,
      offer: offer,
    );
    if (purchaseParam == null) {
      return PurchaseOutcomeFailed(
        productId: prepared.product.id,
        errorCode: RestageBillingErrorCodes.offerUnavailable,
        message: 'The prepared store offer no longer matches the intent.',
      );
    }
    try {
      final opened =
          await _plugin.buyNonConsumable(purchaseParam: purchaseParam);
      if (!opened) {
        return PurchaseOutcomeFailed(
          productId: prepared.product.id,
          errorCode: RestageBillingErrorCodes.buyFailed,
          message: 'The store did not open the purchase flow.',
        );
      }
    } on Object catch (error) {
      return PurchaseOutcomeFailed(
        productId: prepared.product.id,
        errorCode: prepared.offerId == null
            ? RestageBillingErrorCodes.buyFailed
            : _classifyOfferBuyError(error),
        message: 'The store could not start the purchase.',
      );
    }
    return null;
  }

  PurchaseOutcomeFailed _coordinatedConfigurationChanged(String productId) =>
      PurchaseOutcomeFailed(
        productId: productId,
        errorCode: RestageBillingErrorCodes.buyFailed,
        message: 'Billing configuration changed during the purchase.',
      );

  Future<RestoreOutcome> _initiateCoordinatedRestore() async {
    if (!await _plugin.isAvailable()) {
      return RestoreOutcome.failed(
        errorCode: RestageBillingErrorCodes.unavailable,
        message: 'In-app purchase is unavailable on this device.',
      );
    }
    final applicationUserName =
        await resolveApplicationUserNameForStamping(_anonymousTokenProvider);
    try {
      await _plugin.restorePurchases(
        applicationUserName: applicationUserName,
      );
      return RestoreOutcome.noPurchases();
    } on Object {
      return RestoreOutcome.failed(
        errorCode: RestageBillingErrorCodes.restoreFailed,
        message: 'The store could not start purchase restoration.',
      );
    }
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
  final match = _resolveGooglePlayOfferProduct(
    productId: productId,
    products: products,
    basePlanId: offer.basePlanId,
    offerId: offer.offerId,
  );
  if (match == null) return null;
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
  final match = _resolveGooglePlayBasePlanProduct(
    productId: productId,
    products: products,
    basePlanId: basePlanId,
  );
  if (match == null) return null;
  return GooglePlayPurchaseParam(
    productDetails: match,
    applicationUserName: applicationUserName,
    offerToken: match.offerToken,
  );
}

GooglePlayProductDetails? _resolveGooglePlayOfferProduct({
  required String productId,
  required List<ProductDetails> products,
  required String? basePlanId,
  required String offerId,
}) {
  final matches = <GooglePlayProductDetails>[];
  for (final product in products) {
    if (product is! GooglePlayProductDetails) continue;
    if (product.id != productId) continue;
    final index = product.subscriptionIndex;
    if (index == null || index < 0) continue;
    final details = product.productDetails.subscriptionOfferDetails;
    if (details == null || index >= details.length) continue;
    final candidate = details[index];
    if (candidate.basePlanId.isEmpty) continue;
    if (candidate.offerId == null || candidate.offerId != offerId) continue;
    if (basePlanId != null && candidate.basePlanId != basePlanId) continue;
    matches.add(product);
  }
  return matches.length == 1 ? matches.single : null;
}

GooglePlayProductDetails? _resolveGooglePlayBasePlanProduct({
  required String productId,
  required List<ProductDetails> products,
  required String? basePlanId,
}) {
  final matches = <GooglePlayProductDetails>[];
  for (final product in products) {
    if (product is! GooglePlayProductDetails) continue;
    if (product.id != productId) continue;
    final index = product.subscriptionIndex;
    if (index == null || index < 0) continue;
    final details = product.productDetails.subscriptionOfferDetails;
    if (details == null || index >= details.length) continue;
    final candidate = details[index];
    if (candidate.basePlanId.isEmpty) continue;
    // Only standard base-plan entries are eligible — never a discounted offer.
    if (candidate.offerId != null) continue;
    if (basePlanId != null && candidate.basePlanId != basePlanId) continue;
    matches.add(product);
  }
  return matches.length == 1 ? matches.single : null;
}

int _priceMicros(ProductDetails product) =>
    (product.rawPrice * 1000000).toInt();

bool _isRecognizedSubscriptionProductSubtype(
  ProductDetails product,
  String store,
) {
  if (store == 'playStore') return product is GooglePlayProductDetails;
  if (store == 'appStore') {
    return product is AppStoreProductDetails ||
        product is AppStoreProduct2Details;
  }
  return false;
}

bool _isSupportedSubscriptionProduct(ProductDetails product, String store) {
  if (store == 'playStore') {
    if (product is! GooglePlayProductDetails ||
        product.productDetails.productType != ProductType.subs) {
      return false;
    }
    final index = product.subscriptionIndex;
    final details = product.productDetails.subscriptionOfferDetails;
    if (index == null ||
        index < 0 ||
        details == null ||
        index >= details.length) {
      return false;
    }
    final offer = details[index];
    return offer.basePlanId.isNotEmpty &&
        offer.pricingPhases.isNotEmpty &&
        offer.pricingPhases.last.recurrenceMode ==
            RecurrenceMode.infiniteRecurring;
  }
  if (store == 'appStore') {
    if (product is AppStoreProductDetails) {
      return product.skProduct.subscriptionPeriod != null;
    }
    if (product is AppStoreProduct2Details) {
      return product.sk2Product.type == SK2ProductType.autoRenewable;
    }
  }
  return false;
}

String _googleBasePlanId(GooglePlayProductDetails product) {
  final index = product.subscriptionIndex!;
  return product.productDetails.subscriptionOfferDetails![index].basePlanId;
}

final class _PreparedPurchaseResult {
  const _PreparedPurchaseResult._({this.prepared, this.failure});

  factory _PreparedPurchaseResult.success(_PreparedPurchase prepared) =>
      _PreparedPurchaseResult._(prepared: prepared);

  factory _PreparedPurchaseResult.failure(PurchaseOutcomeFailed failure) =>
      _PreparedPurchaseResult._(failure: failure);

  final _PreparedPurchase? prepared;
  final PurchaseOutcomeFailed? failure;
}

final class _PreparedPurchase {
  const _PreparedPurchase({
    required this.product,
    required this.resolvedBasePlanId,
    required this.offerId,
  });

  final ProductDetails product;
  final String? resolvedBasePlanId;
  final String? offerId;

  PurchaseParam? buildParam({
    required String purchaseIntentId,
    required SignedNativeOffer? offer,
  }) {
    if (product is GooglePlayProductDetails) {
      if (offerId == null) {
        if (offer != null) return null;
      } else if (offer is! GoogleOffer ||
          offer.offerId != offerId ||
          offer.basePlanId != resolvedBasePlanId) {
        return null;
      }
      final googleProduct = product as GooglePlayProductDetails;
      return GooglePlayPurchaseParam(
        productDetails: googleProduct,
        applicationUserName: purchaseIntentId,
        offerToken: googleProduct.offerToken,
      );
    }
    if (offerId == null) {
      if (offer != null) return null;
      return PurchaseParam(
        productDetails: product,
        applicationUserName: purchaseIntentId,
      );
    }
    if (offer is! AppleSignedOffer || offer.offerId != offerId) return null;
    return buildApplePromotionalOfferParam(
      product: product,
      appAccountToken: purchaseIntentId,
      offer: offer,
    );
  }
}
