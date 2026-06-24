import '../events/event_enums.dart' show PendingReason;
import 'signed_native_offer.dart';

/// Abstract billing client.
///
/// Ships one impl ([InAppPurchaseGateway]) backed by `package:in_app_purchase`.
/// Defining the abstraction lets host apps swap in mock implementations for
/// tests, and lets us replace `in_app_purchase` later if we hit limitations.
///
/// ```dart
/// class FakeGateway implements BillingGateway {
///   @override
///   Future<PurchaseOutcome> purchase(String productId, {String? basePlanId})
///       async {
///     return PurchaseOutcome.succeeded(
///       productId: productId,
///       transactionId: 'fake_${DateTime.now().millisecondsSinceEpoch}',
///       verificationData: 'fake-verification',
///       priceMicros: 9990000,
///       currency: 'USD',
///     );
///   }
///
///   @override
///   Future<RestoreOutcome> restore() async => RestoreOutcome.noPurchases();
/// }
///
/// Restage.configure(apiKey: 'rs_pk_…', billingGateway: FakeGateway());
/// ```
abstract class BillingGateway {
  /// Initiates a non-consumable purchase for [productId] and resolves with the
  /// outcome once the platform store reports a terminal status.
  ///
  /// [basePlanId] selects a specific Google Play subscription **base plan** at
  /// its standard (no-discount) price. It is required to disambiguate a
  /// subscription with more than one base plan: a plain purchase of such a
  /// subscription with no [basePlanId] must fail closed
  /// ([RestageBillingErrorCodes.basePlanSelectionRequired]) rather than charge
  /// an arbitrary plan. It has no effect on Apple subscriptions (no base-plan
  /// concept) or one-time products, so cross-platform call sites may pass it
  /// unconditionally. To apply a discounted *offer* (not just select a base
  /// plan) use [OfferCapableBillingGateway.purchaseWithOffer].
  Future<PurchaseOutcome> purchase(String productId, {String? basePlanId});

  /// Restores prior purchases for the current store account.
  Future<RestoreOutcome> restore();
}

/// A [BillingGateway] that can additionally transport a native promotional
/// offer to the store.
///
/// The two stores resolve a native offer differently: an Apple offer carries a
/// server-minted signature ([AppleSignedOffer]), while a Google offer names the
/// requested discount and is resolved to an eligible Play offer token
/// client-side ([GoogleOffer]). Both are [SignedNativeOffer] variants the SDK
/// builds; this gateway just transports them.
///
/// This is an **opt-in** capability, kept separate from [BillingGateway] so the
/// base interface stays stable for existing implementers. The SDK
/// feature-detects it (`gateway is OfferCapableBillingGateway`): when the active
/// gateway is not offer-capable, or no offer can be resolved, the SDK fails
/// closed with [RestageBillingErrorCodes.offerUnavailable] rather than charging
/// full price for a discount the user chose.
abstract class OfferCapableBillingGateway implements BillingGateway {
  /// Initiates a purchase of [productId] applying the resolved [offer],
  /// resolving with the outcome once the store reports a terminal status — the
  /// same contract as [BillingGateway.purchase], with the offer applied.
  ///
  /// [appAccountToken] is the store-account token threaded through the purchase
  /// (Apple `appAccountToken` / Google `obfuscatedAccountId`). For an Apple
  /// offer it is the value the signature commits to, so it **must** be the same
  /// value the SDK sent when minting [offer] — the store rejects the offer if
  /// the two differ. The SDK resolves the token once and threads the same value
  /// into both the resolution step and this call.
  ///
  /// Fails closed with a [PurchaseOutcomeFailed] carrying
  /// [RestageBillingErrorCodes.offerUnavailable] when the offer cannot be
  /// transported (e.g. an unsupported offer variant or signing scheme, or a
  /// store generation that cannot carry it); it must never silently fall back to
  /// a full-price purchase.
  Future<PurchaseOutcome> purchaseWithOffer({
    required String productId,
    required SignedNativeOffer offer,
    required String appAccountToken,
  });
}

/// Outcome of a purchase attempt.
///
/// Sealed so consumers can pattern-match exhaustively over the four
/// terminal states reported by the underlying store.
sealed class PurchaseOutcome {
  const PurchaseOutcome();

  /// Purchase completed successfully.
  ///
  /// [verificationData] stays `required` so every gateway makes an explicit
  /// choice between a verified success (the store receipt) and a receipt-less,
  /// attribution-only one (`null`) — pass `null` deliberately rather than by
  /// omission. See [PurchaseOutcomeSucceeded.verificationData] for the full
  /// contract.
  factory PurchaseOutcome.succeeded({
    required String productId,
    required String transactionId,
    required String? verificationData,
    required int priceMicros,
    required String currency,
  }) = PurchaseOutcomeSucceeded;

  /// Purchase is pending an out-of-band action (e.g. SCA challenge,
  /// parental approval, deferred payment). [reason] is the typed
  /// [PendingReason] the SDK forwards directly to the `PurchasePending`
  /// event.
  factory PurchaseOutcome.pending({
    required String productId,
    required PendingReason reason,
  }) = PurchaseOutcomePending;

  /// User cancelled the purchase before the store reported a terminal status.
  factory PurchaseOutcome.cancelled({required String productId}) =
      PurchaseOutcomeCancelled;

  /// Purchase failed. [productId] is nullable because some failure paths
  /// (e.g. restore-flow errors lifted into the purchase shape) don't
  /// correspond to a specific product.
  factory PurchaseOutcome.failed({
    required String? productId,
    required String errorCode,
    required String message,
    String? platformErrorCode,
  }) = PurchaseOutcomeFailed;
}

/// Successful purchase outcome — store reported a completed transaction.
final class PurchaseOutcomeSucceeded extends PurchaseOutcome {
  /// Creates a [PurchaseOutcomeSucceeded].
  const PurchaseOutcomeSucceeded({
    required this.productId,
    required this.transactionId,
    required this.verificationData,
    required this.priceMicros,
    required this.currency,
  });

  /// Product whose purchase succeeded.
  final String productId;

  /// Store-issued transaction identifier. For the bundled gateway this is the
  /// receipt's transaction id; for an external-provider gateway it is the
  /// id that provider surfaces (e.g. RevenueCat's `StoreTransaction.
  /// transactionIdentifier` — the per-transaction id on iOS, the Google order
  /// id on Android), which a server can correlate to its own store ingestion.
  final String transactionId;

  /// Opaque store-issued verification payload (e.g. StoreKit
  /// `serverVerificationData` — the receipt blob for App Store
  /// transactions, the purchase token for Play). Forwarded to the
  /// entitlement service for server-side verification.
  ///
  /// `null` for a **receipt-less, attribution-only** success: a gateway that
  /// delegates the purchase to an external billing provider does not surface
  /// the raw receipt, so there is nothing to verify on the wire. Such a
  /// success is an attribution hint (transaction id + paywall id), never a
  /// verified signal — the SDK must not send it down the receipt-validation
  /// path.
  ///
  /// This field never establishes that a purchase is "verified": the server is
  /// the trust boundary for that, validating the receipt out-of-band against
  /// the store. A non-null value is only the material the server validates; a
  /// `null` value is an honest "no receipt to validate", not a weaker claim of
  /// verification.
  final String? verificationData;

  /// Charged amount in micro-units of [currency] (`1.99 USD` → `1990000`).
  ///
  /// For a promotional-offer purchase this is a local estimate read from the
  /// product entry the purchase targets — on Apple the base list price (not the
  /// discounted amount), on Android the matched offer's first pricing-phase
  /// price — so treat it as optimistic. The store receipt the server validates
  /// is the authoritative charged amount.
  final int priceMicros;

  /// ISO-4217 currency code of the charged amount.
  final String currency;
}

/// Pending purchase — the store is waiting on an out-of-band action.
///
/// Examples include SCA bank challenges, parental approval, or deferred
/// payment. The host app should not grant entitlements yet; a follow-up
/// terminal status will arrive once the action completes.
final class PurchaseOutcomePending extends PurchaseOutcome {
  /// Creates a [PurchaseOutcomePending].
  const PurchaseOutcomePending({
    required this.productId,
    required this.reason,
  });

  /// Product whose purchase is pending.
  final String productId;

  /// Why the purchase is pending.
  final PendingReason reason;
}

/// Cancelled purchase — the user dismissed the platform purchase sheet.
final class PurchaseOutcomeCancelled extends PurchaseOutcome {
  /// Creates a [PurchaseOutcomeCancelled].
  const PurchaseOutcomeCancelled({required this.productId});

  /// Product whose purchase was cancelled.
  final String productId;
}

/// Failed purchase — the store reported a non-recoverable error.
final class PurchaseOutcomeFailed extends PurchaseOutcome {
  /// Creates a [PurchaseOutcomeFailed].
  const PurchaseOutcomeFailed({
    required this.productId,
    required this.errorCode,
    required this.message,
    this.platformErrorCode,
  });

  /// Product whose purchase failed, if known. Null for failures lifted from
  /// flows where no specific product is involved (e.g. restore errors).
  final String? productId;

  /// Stable, machine-readable error code. Use [RestageBillingErrorCodes]
  /// constants rather than literal strings.
  final String errorCode;

  /// Human-readable error message.
  final String message;

  /// Underlying platform error code (e.g. StoreKit `SKError.code`), if any.
  final String? platformErrorCode;
}

/// Outcome of a restore-purchases attempt.
sealed class RestoreOutcome {
  const RestoreOutcome();

  /// Restore returned at least one previously purchased product.
  factory RestoreOutcome.succeeded({
    required List<String> restoredProductIds,
  }) = RestoreOutcomeSucceeded;

  /// Restore completed but the account has no eligible prior purchases.
  factory RestoreOutcome.noPurchases() = RestoreOutcomeNoPurchases;

  /// Restore failed before producing a result.
  factory RestoreOutcome.failed({
    required String errorCode,
    required String message,
  }) = RestoreOutcomeFailed;
}

/// Restore succeeded with at least one previously purchased product.
final class RestoreOutcomeSucceeded extends RestoreOutcome {
  /// Creates a [RestoreOutcomeSucceeded].
  const RestoreOutcomeSucceeded({required this.restoredProductIds});

  /// Product identifiers of purchases reported by the store.
  final List<String> restoredProductIds;
}

/// Restore completed cleanly but found no eligible prior purchases.
final class RestoreOutcomeNoPurchases extends RestoreOutcome {
  /// Creates a [RestoreOutcomeNoPurchases].
  const RestoreOutcomeNoPurchases();
}

/// Restore failed before producing a result (network, auth, etc.).
final class RestoreOutcomeFailed extends RestoreOutcome {
  /// Creates a [RestoreOutcomeFailed].
  const RestoreOutcomeFailed({
    required this.errorCode,
    required this.message,
  });

  /// Stable, machine-readable error code. Use [RestageBillingErrorCodes]
  /// constants rather than literal strings.
  final String errorCode;

  /// Human-readable error message.
  final String message;
}

/// Stable, machine-readable error codes carried on the `errorCode` field of
/// [PurchaseOutcomeFailed] / [RestoreOutcomeFailed] (and the mirrored
/// `PurchaseFailed` / `RestoreFailed` events). Switch on these constants
/// rather than literal strings — typos in either direction are caught at
/// compile time.
///
/// These are the codes the bundled [InAppPurchaseGateway] produces. A code
/// outside this set can still appear: the bundled gateway forwards a raw
/// platform error code verbatim when the store supplies one, and a custom
/// [BillingGateway] may surface its own platform-specific codes. Treat this
/// set as the canonical Restage vocabulary, not an exhaustive bound.
abstract final class RestageBillingErrorCodes {
  RestageBillingErrorCodes._();

  /// In-app purchase is unavailable on this device (store disabled, the user
  /// is not signed in, or an unsupported platform).
  static const String unavailable = 'unavailable';

  /// The store did not recognize the requested product identifier.
  static const String productNotFound = 'product_not_found';

  /// The platform purchase call threw before reporting a terminal status.
  static const String buyFailed = 'buy_failed';

  /// The platform restore call threw before producing a result.
  static const String restoreFailed = 'restore_failed';

  /// The requested promotional offer could not be applied — no signature was
  /// available, or the active gateway cannot transport native offers. The SDK
  /// surfaces this on [PurchaseOutcomeFailed] instead of silently charging the
  /// full price; the host/paywall decides whether to retry or present the
  /// standard price.
  static const String offerUnavailable = 'offer_unavailable';

  /// A plain subscription purchase could not pick a base plan unambiguously: the
  /// subscription has more than one base plan and none was specified, or the
  /// specified `basePlanId` matched no standard base plan. The SDK surfaces this
  /// on [PurchaseOutcomeFailed] instead of silently buying an arbitrary base
  /// plan; pass an explicit `basePlanId` (e.g. via a plan picker) to resolve it.
  /// Google Play only — Apple subscriptions have no base-plan concept.
  static const String basePlanSelectionRequired =
      'base_plan_selection_required';

  /// Unclassified billing error — the fallback used when the platform reports
  /// an error but supplies no error code.
  static const String unknown = 'unknown';
}
