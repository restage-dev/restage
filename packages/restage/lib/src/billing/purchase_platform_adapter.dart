import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

/// Where a recoverable transaction was observed.
enum StoreTransactionSource {
  /// The long-lived purchase update stream.
  purchaseStream,

  /// StoreKit 2's unfinished transaction sequence.
  storeKit2Unfinished,

  /// Google Play's owned-purchase query.
  googleOwnedPurchases,
}

/// Store state carried by a transaction observation.
enum StoreTransactionState {
  /// The store is waiting for an out-of-band decision.
  pending,

  /// The store reports a completed purchase.
  purchased,

  /// The store reports a restored purchase.
  restored,

  /// The user cancelled the purchase.
  cancelled,

  /// The store reported an error.
  failed,
}

/// In-memory evidence needed to report and eventually complete a transaction.
///
/// [verificationData] is deliberately opaque. It must never be persisted or
/// included in diagnostics. [evidenceKey] contains only a non-secret store
/// transaction or order identifier, so it is safe to use for in-memory
/// coalescing and diagnostics that name the key shape (but not its value).
final class StoreTransactionEvidence {
  /// Creates normalized store evidence.
  StoreTransactionEvidence({
    required this.evidenceKey,
    required this.store,
    required this.source,
    required this.state,
    required this.productId,
    required this.transactionId,
    required this.verificationData,
    required this.purchaseIntentId,
    required this.originalTransactionId,
    required this.needsFinish,
    required this.finish,
  });

  /// Canonical, non-secret in-memory serialization key.
  final String evidenceKey;

  /// Store wire name (`appStore` or `playStore`).
  final String store;

  /// Observation surface that supplied this evidence.
  final StoreTransactionSource source;

  /// Current store state.
  final StoreTransactionState state;

  /// Store product identifier.
  final String productId;

  /// App Store transaction ID or Google Play order ID.
  final String transactionId;

  /// Opaque receipt, JWS, or purchase token used only for server verification.
  final String verificationData;

  /// Purchase-intent UUID recovered from the store evidence, when present.
  final String? purchaseIntentId;

  /// App Store original transaction ID, when available.
  final String? originalTransactionId;

  /// Whether the native transaction still requires finish/acknowledgement.
  final bool needsFinish;

  /// Completes the native transaction. Call only after durable acceptance.
  final Future<void> Function() finish;
}

/// Explicit platform recovery seam owned by the purchase coordinator.
abstract interface class PurchasePlatformAdapter {
  /// Whether this adapter is drained when the coordinator starts.
  bool get drainOnConfigure;

  /// Whether this adapter is drained when the app resumes.
  bool get drainOnResume;

  /// Enumerates currently recoverable native transactions.
  Future<List<StoreTransactionEvidence>> drain();
}

/// StoreKit 2 unfinished-transaction enumeration.
final class StoreKit2UnfinishedPurchaseAdapter
    implements PurchasePlatformAdapter {
  /// Creates the production adapter.
  StoreKit2UnfinishedPurchaseAdapter({
    Future<List<SK2Transaction>> Function()? enumerate,
    Future<void> Function(int transactionId)? finish,
  })  : _enumerate = enumerate ?? SK2Transaction.unfinishedTransactions,
        _finish = finish ?? SK2Transaction.finish;

  final Future<List<SK2Transaction>> Function() _enumerate;
  final Future<void> Function(int transactionId) _finish;

  @override
  bool get drainOnConfigure => true;

  @override
  bool get drainOnResume => false;

  @override
  Future<List<StoreTransactionEvidence>> drain() async {
    final transactions = await _enumerate();
    final evidence = <StoreTransactionEvidence>[];
    for (final transaction in transactions) {
      final numericId = int.tryParse(transaction.id);
      final verificationData = transaction.receiptData;
      if (numericId == null ||
          transaction.id.isEmpty ||
          transaction.productId.isEmpty ||
          verificationData == null ||
          verificationData.isEmpty) {
        continue;
      }
      evidence.add(
        StoreTransactionEvidence(
          evidenceKey: appleEvidenceKey(transaction.id),
          store: 'appStore',
          source: StoreTransactionSource.storeKit2Unfinished,
          state: StoreTransactionState.purchased,
          productId: transaction.productId,
          transactionId: transaction.id,
          verificationData: verificationData,
          purchaseIntentId: transaction.appAccountToken,
          originalTransactionId: transaction.originalId,
          needsFinish: true,
          finish: () => _finish(numericId),
        ),
      );
    }
    return evidence;
  }
}

/// Google Play configure/resume owned-purchase enumeration.
final class GoogleOwnedPurchaseAdapter implements PurchasePlatformAdapter {
  /// Creates the production adapter.
  GoogleOwnedPurchaseAdapter({
    required InAppPurchase plugin,
    required Set<String> knownSubscriptionProductIds,
    Future<QueryPurchaseDetailsResponse> Function()? query,
  })  : _plugin = plugin,
        _knownSubscriptionProductIds =
            Set.unmodifiable(knownSubscriptionProductIds),
        _query = query;

  final InAppPurchase _plugin;
  final Set<String> _knownSubscriptionProductIds;
  final Future<QueryPurchaseDetailsResponse> Function()? _query;

  @override
  bool get drainOnConfigure => true;

  @override
  bool get drainOnResume => true;

  @override
  Future<List<StoreTransactionEvidence>> drain() async {
    final response = await (_query?.call() ??
        _plugin
            .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
            .queryPastPurchases());
    final evidence = <StoreTransactionEvidence>[];
    for (final purchase in response.pastPurchases) {
      if (!_knownSubscriptionProductIds.contains(purchase.productID)) {
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      final wrapper = purchase.billingClientPurchase;
      final orderId = wrapper.orderId;
      if (orderId.isEmpty ||
          purchase.productID.isEmpty ||
          wrapper.purchaseToken.isEmpty) {
        continue;
      }
      evidence.add(
        StoreTransactionEvidence(
          evidenceKey: googleEvidenceKey(orderId),
          store: 'playStore',
          source: StoreTransactionSource.googleOwnedPurchases,
          state: _stateFromPurchaseStatus(purchase.status),
          productId: purchase.productID,
          transactionId: orderId,
          verificationData: wrapper.purchaseToken,
          purchaseIntentId: wrapper.obfuscatedAccountId,
          originalTransactionId: null,
          needsFinish: !wrapper.isAcknowledged,
          finish: () => _plugin.completePurchase(purchase),
        ),
      );
    }
    return evidence;
  }
}

/// Canonical App Store evidence key. The transaction ID is not receipt data.
String appleEvidenceKey(String transactionId) =>
    'appStore/transaction/$transactionId';

/// Canonical Google Play evidence key. The order ID is not the purchase token.
String googleEvidenceKey(String orderId) => 'playStore/order/$orderId';

StoreTransactionState _stateFromPurchaseStatus(PurchaseStatus status) {
  return switch (status) {
    PurchaseStatus.pending => StoreTransactionState.pending,
    PurchaseStatus.purchased => StoreTransactionState.purchased,
    PurchaseStatus.restored => StoreTransactionState.restored,
    PurchaseStatus.canceled => StoreTransactionState.cancelled,
    PurchaseStatus.error => StoreTransactionState.failed,
  };
}
