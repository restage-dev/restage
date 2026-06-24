part of 'restage_event.dart';

/// Fired when the user taps a buy CTA and the SDK begins a purchase flow.
///
/// `priceMicros` and `currency` are nullable because the SDK fires this event
/// the instant the user taps — before the platform store lookup has returned
/// price metadata. Hosts forwarding to analytics should filter out null
/// `priceMicros` rows or attribute revenue from [PurchaseSucceeded] instead,
/// which always carries verified price data.
final class PurchaseInitiated extends RestageEvent {
  /// Const constructor.
  const PurchaseInitiated({
    required String super.paywallId,
    required this.productId,
    this.priceMicros,
    this.currency,
    this.offerId,
    this.isTrial = false,
    this.isIntroOffer = false,
    super.firedAt,
  });

  /// Platform product identifier (StoreKit `productID` / Play `sku`).
  final String productId;

  /// Price in micros (1_000_000 = 1 unit of currency). `null` until the
  /// platform store lookup completes — typically `null` on this event and
  /// non-null on [PurchaseSucceeded].
  final int? priceMicros;

  /// ISO 4217 currency code. `null` until the platform store lookup completes.
  final String? currency;

  /// Promotional offer / Play offer identifier; null for base price.
  final String? offerId;

  /// Whether the SKU includes a free trial.
  final bool isTrial;

  /// Whether the SKU is an introductory offer (Play) / introductory price
  /// (StoreKit).
  final bool isIntroOffer;

  @override
  String get name => 'purchase_initiated';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'productId': productId,
        if (priceMicros != null) 'priceMicros': priceMicros,
        if (currency != null) 'currency': currency,
        if (offerId != null) 'offerId': offerId,
        'isTrial': isTrial,
        'isIntroOffer': isIntroOffer,
      };
}

/// Fired when a purchase completes and the receipt is verified.
final class PurchaseSucceeded extends RestageEvent {
  /// Const constructor.
  const PurchaseSucceeded({
    required String super.paywallId,
    required this.productId,
    required this.transactionId,
    required this.priceMicros,
    required this.currency,
    this.offerId,
    super.firedAt,
  });

  /// Platform product identifier.
  final String productId;

  /// Platform transaction identifier (StoreKit `transactionIdentifier` /
  /// Play `purchaseToken`).
  final String transactionId;

  /// Price in micros at purchase time.
  final int priceMicros;

  /// ISO 4217 currency code at purchase time.
  final String currency;

  /// Promotional offer identifier applied to the purchase; null for base price.
  final String? offerId;

  @override
  String get name => 'purchase_succeeded';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'productId': productId,
        'transactionId': transactionId,
        'priceMicros': priceMicros,
        'currency': currency,
        if (offerId != null) 'offerId': offerId,
      };
}

/// Fired when a purchase enters the platform "pending" state (Ask to Buy,
/// SCA, deferred payment).
final class PurchasePending extends RestageEvent {
  /// Const constructor.
  const PurchasePending({
    required String super.paywallId,
    required this.productId,
    required this.reason,
    super.firedAt,
  });

  /// Platform product identifier.
  final String productId;

  /// Why the purchase is pending.
  final PendingReason reason;

  @override
  String get name => 'purchase_pending';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'productId': productId,
        'reason': reason.wireName,
      };
}

/// Fired when the user dismisses the platform purchase sheet.
final class PurchaseCancelled extends RestageEvent {
  /// Const constructor.
  const PurchaseCancelled({
    required String super.paywallId,
    required this.productId,
    super.firedAt,
  });

  /// Platform product identifier.
  final String productId;

  @override
  String get name => 'purchase_cancelled';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'productId': productId,
      };
}

/// Fired when a purchase fails (network, receipt validation, etc.).
final class PurchaseFailed extends RestageEvent {
  /// Const constructor.
  const PurchaseFailed({
    required String super.paywallId,
    required this.productId,
    required this.errorCode,
    required this.message,
    this.platformErrorCode,
    super.firedAt,
  });

  /// Platform product identifier.
  final String productId;

  /// Stable, machine-readable error code; see [RestageBillingErrorCodes].
  final String errorCode;

  /// Human-readable message (logged but not user-visible).
  final String message;

  /// Raw platform error code (StoreKit `SKError` / Play
  /// `BillingResponseCode`); null if not surfaced by the platform.
  final String? platformErrorCode;

  @override
  String get name => 'purchase_failed';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'productId': productId,
        'errorCode': errorCode,
        'message': message,
        if (platformErrorCode != null) 'platformErrorCode': platformErrorCode,
      };
}

/// Fired when the user taps "Restore Purchases" and the SDK begins the
/// restore flow.
final class RestoreInitiated extends RestageEvent {
  /// Const constructor.
  const RestoreInitiated({
    required String super.paywallId,
    super.firedAt,
  });

  @override
  String get name => 'restore_initiated';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
      };
}

/// Fired when restore completes with one or more active entitlements.
final class RestoreSucceeded extends RestageEvent {
  /// Const constructor.
  const RestoreSucceeded({
    required String super.paywallId,
    required this.restoredProductIds,
    super.firedAt,
  });

  /// Platform product identifiers that were restored to active.
  final List<String> restoredProductIds;

  @override
  String get name => 'restore_succeeded';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'restoredProductIds': restoredProductIds,
      };
}

/// Fired when restore completes but no active entitlements were found.
final class RestoreNoPurchases extends RestageEvent {
  /// Const constructor.
  const RestoreNoPurchases({
    required String super.paywallId,
    super.firedAt,
  });

  @override
  String get name => 'restore_no_purchases';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
      };
}

/// Fired when restore fails (network, receipt validation, etc.).
final class RestoreFailed extends RestageEvent {
  /// Const constructor.
  const RestoreFailed({
    required String super.paywallId,
    required this.errorCode,
    required this.message,
    this.platformErrorCode,
    super.firedAt,
  });

  /// Stable, machine-readable error code; see [RestageBillingErrorCodes].
  final String errorCode;

  /// Human-readable message.
  final String message;

  /// Raw platform error code; null if not surfaced.
  final String? platformErrorCode;

  @override
  String get name => 'restore_failed';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'errorCode': errorCode,
        'message': message,
        if (platformErrorCode != null) 'platformErrorCode': platformErrorCode,
      };
}
