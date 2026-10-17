final RegExp _commerceStoreCodePattern = RegExp(r'^[a-z][a-z0-9._]{0,63}$');

String _requireCommerceStoreCode(String value) {
  if (!_commerceStoreCodePattern.hasMatch(value)) {
    throw FormatException('Invalid commerce store code', value);
  }
  return value;
}

/// A store that can process a commerce transaction.
///
/// Unknown values are preserved so adapters can decline unsupported stores
/// without narrowing a future store selection.
final class CommerceStore {
  factory CommerceStore(String value) {
    final code = _requireCommerceStoreCode(value);
    return switch (code) {
      'app_store' => appStore,
      'play_store' => playStore,
      _ => CommerceStore._(code, false),
    };
  }

  const CommerceStore._(this.value, this.isKnown);

  /// The normalized store code.
  final String value;

  /// Whether this SDK recognizes [value].
  final bool isKnown;

  /// Apple App Store.
  static const appStore = CommerceStore._('app_store', true);

  /// Google Play.
  static const playStore = CommerceStore._('play_store', true);

  @override
  bool operator ==(Object other) =>
      other is CommerceStore && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A store product form that an adapter can purchase.
///
/// The initial commerce loop supports subscriptions only. Unknown values are
/// retained and must be declined until their fulfillment path is available.
final class CommerceStoreProductKind {
  factory CommerceStoreProductKind(String value) {
    final code = _requireCommerceStoreCode(value);
    return switch (code) {
      'subscription' => subscription,
      _ => CommerceStoreProductKind._(code, false),
    };
  }

  const CommerceStoreProductKind._(this.value, this.isKnown);

  /// The normalized product form code.
  final String value;

  /// Whether this SDK supports [value].
  final bool isKnown;

  /// A renewing subscription.
  static const subscription = CommerceStoreProductKind._(
    'subscription',
    true,
  );

  @override
  bool operator ==(Object other) =>
      other is CommerceStoreProductKind && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// The normalized status of a store transaction.
///
/// Unknown values are retained for a later SDK version to handle explicitly.
final class CommerceStoreTransactionStatus {
  factory CommerceStoreTransactionStatus(String value) {
    final code = _requireCommerceStoreCode(value);
    return switch (code) {
      'pending' => pending,
      'purchased' => purchased,
      'restored' => restored,
      'canceled' => canceled,
      'failed' => failed,
      _ => CommerceStoreTransactionStatus._(code, false),
    };
  }

  const CommerceStoreTransactionStatus._(this.value, this.isKnown);

  /// The normalized transaction status code.
  final String value;

  /// Whether this SDK recognizes [value].
  final bool isKnown;

  /// The store is waiting for the purchaser to complete the transaction.
  static const pending = CommerceStoreTransactionStatus._('pending', true);

  /// The store accepted the purchase.
  static const purchased = CommerceStoreTransactionStatus._(
    'purchased',
    true,
  );

  /// The store restored a prior purchase.
  static const restored = CommerceStoreTransactionStatus._('restored', true);

  /// The purchaser canceled the store flow.
  static const canceled = CommerceStoreTransactionStatus._('canceled', true);

  /// The store flow failed.
  static const failed = CommerceStoreTransactionStatus._('failed', true);

  @override
  bool operator ==(Object other) =>
      other is CommerceStoreTransactionStatus && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A provider-neutral store product retained by its adapter.
///
/// The adapter keeps any provider-specific product object private and uses this
/// value to prove that a resolved product, base plan, and offer match a store
/// result before it starts a purchase.
abstract interface class CommerceStoreProduct {
  CommerceStore get store;

  String get storeProductId;

  CommerceStoreProductKind get kind;

  String? get basePlanId;

  String? get storeOfferIdentifier;
}

/// A server-resolved store product and the account token for its purchase.
final class CommerceStorePurchasable {
  CommerceStorePurchasable({
    required this.product,
    required String applicationAccountToken,
    this.offerSignature,
  }) : applicationAccountToken = _requireApplicationAccountToken(
          applicationAccountToken,
        );

  final CommerceStoreProduct product;

  /// The store account token or obfuscated account identifier.
  final String applicationAccountToken;

  /// An opaque server-issued offer signature, when the store requires one.
  final String? offerSignature;
}

String _requireApplicationAccountToken(String value) {
  if (value.isEmpty) {
    throw ArgumentError.value(
      value,
      'applicationAccountToken',
      'must not be empty',
    );
  }
  return value;
}

/// A provider-neutral transaction emitted by a [CommerceStoreAdapter].
abstract interface class CommerceStoreTransaction {
  CommerceStore get store;

  CommerceStoreTransactionStatus get status;

  String get storeProductId;

  String? get storeTransactionId;

  /// Apple signed transaction JWS or a Play signed purchase receipt.
  ///
  /// Play uses the JSON object `{originalJson, signature}`. Preserve the exact
  /// original JSON from BillingClient and its Base64 signature; a bare purchase
  /// token is not verification data. The SDK keys Play retries by the signed
  /// purchase token so updated receipt snapshots retain one provider identity.
  String? get storeVerificationData;

  /// Whether this transaction must be completed on the device after a server
  /// reports a verified grant.
  bool get requiresDeviceCompletion;
}

/// A provider-neutral bridge to one configured application store.
///
/// Store adapters keep provider packages and provider-specific values outside
/// the core SDK. The SDK starts a resolved subscription, persists each report
/// before it sends it to the server, and calls [completeTransaction] only after
/// a verified server result and only when [CommerceStoreTransaction]
/// requests device completion.
abstract interface class CommerceStoreAdapter {
  CommerceStore get store;

  Stream<CommerceStoreTransaction> get transactions;

  Future<List<CommerceStoreProduct>> queryProducts(
    Set<String> storeProductIds,
  );

  /// Returns one complete snapshot of the transactions currently owned by the
  /// store account. An empty list is a successful empty snapshot.
  Future<List<CommerceStoreTransaction>> queryOwnedTransactions();

  /// Starts a provider flow and returns whether the provider presented it.
  Future<bool> startPurchase(CommerceStorePurchasable purchasable);

  Future<void> restore();

  Future<void> completeTransaction(CommerceStoreTransaction transaction);
}
