import 'package:meta/meta.dart';

/// Signing scheme of a minted offer signature.
///
/// A server-to-client discriminator, parsed leniently: an unrecognized value
/// decodes to [unsupported] rather than throwing, so a newer scheme never
/// breaks an older client. The client treats anything it cannot transport as
/// "offer unavailable".
enum OfferSignatureScheme {
  /// The four-field signature transported through StoreKit: a key identifier,
  /// nonce, timestamp, and a base64 binary signature.
  legacy,

  /// A compact-JWS signature. Reserved; the SDK does not transport it.
  jws,

  /// Any scheme this client does not recognize. Decoded leniently from an
  /// unknown wire value; never transported.
  unsupported,
}

/// Parses the wire `scheme` value: absent or `"legacy"` ->
/// [OfferSignatureScheme.legacy], `"jws"` -> [OfferSignatureScheme.jws],
/// anything else -> [OfferSignatureScheme.unsupported] (lenient, never throws).
OfferSignatureScheme offerSignatureSchemeFromWire(Object? raw) {
  if (raw == null || raw == 'legacy') return OfferSignatureScheme.legacy;
  if (raw == 'jws') return OfferSignatureScheme.jws;
  return OfferSignatureScheme.unsupported;
}

/// A minted native promotional-offer signature returned by the signing service.
///
/// The signature material ([keyIdentifier], [nonce], [timestampMs],
/// [signatureBase64]) is strict-validated — a missing field is a server/contract
/// bug — while [scheme] is parsed leniently for forward-compatibility; further
/// scheme-specific fields can be added additively.
@immutable
final class OfferSignatureResponse {
  /// Creates an offer-signature response.
  const OfferSignatureResponse({
    required this.scheme,
    required this.keyIdentifier,
    required this.nonce,
    required this.timestampMs,
    required this.signatureBase64,
  });

  /// Parses a response from the signing service's JSON.
  factory OfferSignatureResponse.fromJson(Map<String, dynamic> json) {
    return OfferSignatureResponse(
      scheme: offerSignatureSchemeFromWire(json['scheme']),
      keyIdentifier: _requiredString(json, 'keyIdentifier'),
      nonce: _requiredString(json, 'nonce'),
      timestampMs: _requiredInt(json, 'timestamp'),
      signatureBase64: _requiredString(json, 'signature'),
    );
  }

  /// Signing scheme of this signature.
  final OfferSignatureScheme scheme;

  /// Identifier of the signing key the signature commits to.
  final String keyIdentifier;

  /// Nonce the signature commits to.
  final String nonce;

  /// Timestamp the signature commits to, in milliseconds since the epoch.
  final int timestampMs;

  /// The base64-encoded binary signature.
  final String signatureBase64;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is OfferSignatureResponse &&
            other.scheme == scheme &&
            other.keyIdentifier == keyIdentifier &&
            other.nonce == nonce &&
            other.timestampMs == timestampMs &&
            other.signatureBase64 == signatureBase64;
  }

  @override
  int get hashCode =>
      Object.hash(scheme, keyIdentifier, nonce, timestampMs, signatureBase64);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw ArgumentError.value(value, key, 'Expected a non-empty string');
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw ArgumentError.value(value, key, 'Expected an int');
}
