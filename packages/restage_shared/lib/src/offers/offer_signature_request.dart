import 'package:meta/meta.dart';

/// Request the SDK posts to mint a native promotional-offer signature.
///
/// The three fields are the only inputs the signing service needs to bind a
/// signature to a specific offer for a specific store account. The same
/// `appAccountToken` MUST be passed to the store at purchase time — the
/// signature commits to it, so a mismatch makes the store reject the offer.
@immutable
final class OfferSignatureRequest {
  /// Creates an offer-signature request. All three fields are required and
  /// must be non-empty — each is load-bearing for the signature.
  const OfferSignatureRequest({
    required this.productId,
    required this.offerId,
    required this.appAccountToken,
  })  : assert(productId.length > 0, 'productId must not be empty'),
        assert(offerId.length > 0, 'offerId must not be empty'),
        assert(appAccountToken.length > 0, 'appAccountToken must not be empty');

  /// Store product identifier the offer applies to.
  final String productId;

  /// Promotional offer identifier to authorize.
  final String offerId;

  /// Stable, opaque store-account token (Apple `appAccountToken` /
  /// Google `obfuscatedAccountId`). The signature commits to this value;
  /// the same token must be presented to the store at purchase time.
  final String appAccountToken;

  /// Converts this request to its JSON wire form.
  Map<String, dynamic> toJson() => {
        'productId': productId,
        'offerId': offerId,
        'appAccountToken': appAccountToken,
      };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is OfferSignatureRequest &&
            other.productId == productId &&
            other.offerId == offerId &&
            other.appAccountToken == appAccountToken;
  }

  @override
  int get hashCode => Object.hash(productId, offerId, appAccountToken);
}
