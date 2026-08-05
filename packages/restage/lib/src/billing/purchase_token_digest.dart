import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// Digest of a Google Play purchase token, used to correlate an acceptance to
/// the exact submitted purchase without the token itself ever being sent back.
///
/// SHA-256 over the UTF-8 bytes of the token exactly as received — no trimming,
/// normalization, or case folding — as 64 lowercase hex characters. No salt,
/// prefix, or key derivation.
String googlePurchaseTokenDigest(String purchaseToken) =>
    crypto.sha256.convert(utf8.encode(purchaseToken)).toString();
