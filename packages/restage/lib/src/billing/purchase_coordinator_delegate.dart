import 'billing_gateway.dart';
import 'signed_native_offer.dart';

/// Internal delegation seam installed on the bundled billing gateway.
abstract interface class PurchaseCoordinatorDelegate {
  /// Creates an intent and initiates a plain store purchase.
  Future<PurchaseOutcome> purchase(
    String productId, {
    String? basePlanId,
  });

  /// Resolves the selected offer against a fresh durable purchase intent.
  Future<PurchaseOutcome> purchaseWithOffer({
    required String productId,
    required SignedNativeOffer offer,
  });

  /// Initiates store restore/query work without installing another listener.
  Future<RestoreOutcome> restore();
}
