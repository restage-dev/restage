import 'package:restage_shared/restage_shared.dart'
    show OfferSignatureResponse, OfferSignatureScheme;

/// A server-signed native promotional offer, ready to transport to the store.
///
/// This is a gateway service-provider (SPI) type: only custom
/// [OfferCapableBillingGateway] implementers read it (the SDK builds it
/// internally from a resolved signature). The high-level app / paywall API
/// stays offer-id based.
///
/// `abstract final`, deliberately NOT `sealed`: only the SDK defines variants
/// ([AppleSignedOffer] and [GoogleOffer]), so an external implementer cannot
/// forge one — but switches over it are NOT exhaustive, so a later variant never
/// breaks an external gateway's `switch`. Consumers must handle an unrecognized
/// variant with a fail-closed default (treat it as an unavailable offer), never
/// assume the set is closed.
///
/// The two variants carry deliberately different payloads, reflecting where each
/// store resolves an offer: [AppleSignedOffer] carries a server-minted
/// signature (the SDK resolves it via the server before transport), while
/// [GoogleOffer] carries only the requested offer identifier (Play needs no
/// server crypto, so the offer-capable gateway resolves the eligible token from
/// the live product at transport time).
abstract final class SignedNativeOffer {
  /// Const base constructor.
  const SignedNativeOffer();

  /// Promotional offer identifier this signature authorizes.
  String get offerId;
}

/// An Apple promotional offer signed for StoreKit transport.
///
/// Carries the four-field legacy signature the store verifies: the signing-key
/// identifier, the nonce and timestamp the signature commits to, and the
/// base64 binary signature. [scheme] records which signing scheme produced it;
/// the bundled gateway transports only [OfferSignatureScheme.legacy], so a
/// non-legacy scheme fails closed at the gateway.
final class AppleSignedOffer extends SignedNativeOffer {
  /// Creates an Apple signed offer.
  const AppleSignedOffer({
    required this.offerId,
    required this.keyIdentifier,
    required this.nonce,
    required this.timestampMs,
    required this.signatureBase64,
    this.scheme = OfferSignatureScheme.legacy,
  });

  /// Builds an Apple signed offer for [offerId] from a minted [signature],
  /// keeping the signature-material mapping in one place.
  AppleSignedOffer.fromSignature({
    required this.offerId,
    required OfferSignatureResponse signature,
  })  : keyIdentifier = signature.keyIdentifier,
        nonce = signature.nonce,
        timestampMs = signature.timestampMs,
        signatureBase64 = signature.signatureBase64,
        scheme = signature.scheme;

  @override
  final String offerId;

  /// Identifier of the signing key the signature commits to.
  final String keyIdentifier;

  /// Nonce the signature commits to.
  final String nonce;

  /// Timestamp the signature commits to, in milliseconds since the epoch.
  final int timestampMs;

  /// The base64-encoded binary signature.
  final String signatureBase64;

  /// Signing scheme that produced [signatureBase64].
  final OfferSignatureScheme scheme;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppleSignedOffer &&
            other.offerId == offerId &&
            other.keyIdentifier == keyIdentifier &&
            other.nonce == nonce &&
            other.timestampMs == timestampMs &&
            other.signatureBase64 == signatureBase64 &&
            other.scheme == scheme;
  }

  @override
  int get hashCode => Object.hash(
        offerId,
        keyIdentifier,
        nonce,
        timestampMs,
        signatureBase64,
        scheme,
      );
}

/// A Google Play promotional offer the user chose, ready to transport to the
/// store.
///
/// Unlike [AppleSignedOffer], a Google offer carries no signature: Play requires
/// no server crypto. It names the requested discount [offerId] — the offer-capable
/// gateway resolves the matching eligible `offerToken` from the product's live
/// subscription offers at transport time. An optional [basePlanId] disambiguates
/// when the same [offerId] recurs across base plans (a Play offer id is unique
/// only within a base plan); when omitted, resolution requires a single
/// unambiguous [offerId] match and otherwise fails closed.
final class GoogleOffer extends SignedNativeOffer {
  /// Creates a Google promotional offer for [offerId], optionally scoped to
  /// [basePlanId].
  const GoogleOffer({
    required this.offerId,
    this.basePlanId,
  });

  @override
  final String offerId;

  /// Base-plan identifier the requested [offerId] belongs to, if known.
  ///
  /// Optional. When set, offer resolution matches the `(basePlanId, offerId)`
  /// pair exactly; when null, it matches on [offerId] alone and fails closed if
  /// more than one base plan exposes that offer id.
  final String? basePlanId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GoogleOffer &&
            other.offerId == offerId &&
            other.basePlanId == basePlanId;
  }

  @override
  int get hashCode => Object.hash(offerId, basePlanId);
}
