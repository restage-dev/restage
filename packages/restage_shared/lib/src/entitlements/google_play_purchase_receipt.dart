import 'dart:convert';

/// A Play purchase's exact signed JSON and Base64 signature.
///
/// This is the current Play `storeVerificationData` format. Parsing preserves
/// the signed bytes and supplies identity only. The server verifies the signature.
final class GooglePlayPurchaseReceipt {
  /// Creates current evidence from the billing client's unchanged signed data.
  factory GooglePlayPurchaseReceipt({
    required String originalJson,
    required String signature,
  }) {
    if (originalJson.isEmpty || signature.isEmpty) {
      throw const FormatException('Play signed purchase is incomplete.');
    }
    final decoded = jsonDecode(originalJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Play purchase JSON is invalid.');
    }
    final token = decoded.containsKey('token')
        ? decoded['token']
        : decoded['purchaseToken'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('Play purchase token is absent.');
    }
    return GooglePlayPurchaseReceipt._(
      originalJson,
      signature,
      Map.unmodifiable(decoded),
      token,
    );
  }

  const GooglePlayPurchaseReceipt._(
    this.originalJson,
    this.signature,
    this.purchaseData,
    this.purchaseToken,
  );

  /// Decodes the current two-field receipt object; bare tokens are invalid.
  factory GooglePlayPurchaseReceipt.fromVerificationData(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        decoded['originalJson'] is! String ||
        decoded['signature'] is! String) {
      throw const FormatException('Play signed purchase is invalid.');
    }
    return GooglePlayPurchaseReceipt(
      originalJson: decoded['originalJson'] as String,
      signature: decoded['signature'] as String,
    );
  }

  /// The exact JSON text covered by [signature].
  final String originalJson;

  /// The billing client's Base64 signature.
  final String signature;

  /// Parsed identity data, which remains untrusted until signature verification.
  final Map<String, dynamic> purchaseData;

  /// Stable token identity extracted from [originalJson].
  final String purchaseToken;

  /// Encodes this receipt for `storeVerificationData` without changing its JSON.
  String toVerificationData() => jsonEncode({
        'originalJson': originalJson,
        'signature': signature,
      });
}

/// Stable provider identity despite changes to a signed Play purchase snapshot.
String commerceVerificationIdentity(String store, String verificationData) =>
    store == 'play_store'
        ? GooglePlayPurchaseReceipt.fromVerificationData(verificationData)
            .purchaseToken
        : verificationData;
