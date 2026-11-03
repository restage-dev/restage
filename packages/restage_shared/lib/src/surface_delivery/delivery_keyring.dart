import 'dart:collection';
import 'dart:typed_data';

import 'package:restage_shared/src/surface_delivery/delivery_signature.dart';
import 'package:restage_shared/src/surface_delivery/ed25519_verify.dart';
import 'package:restage_shared/src/surface_delivery/surface_artifact_descriptor.dart';

/// Why a delivered descriptor was refused.
enum DeliveryRefusal {
  /// No configured key has the signature's key id.
  unknownKey('unknown_key'),

  /// The signature does not verify over the descriptor's statement.
  invalidSignature('invalid_signature');

  const DeliveryRefusal(this.wireName);

  /// Stable name for reporting.
  final String wireName;
}

/// The keys an app accepts delivered artifacts from.
///
/// Holds more than one key so a rotation ships before the old key retires.
final class DeliveryKeyring {
  /// Creates a keyring over [keys].
  DeliveryKeyring(Iterable<DeliveryPublicKey> keys)
      : _keys = {for (final key in keys) key.keyId: key};

  final Map<String, DeliveryPublicKey> _keys;

  // Statements already verified, by signature, so a descriptor seen again
  // costs one comparison.
  final LinkedHashMap<String, Uint8List> _verified =
      LinkedHashMap<String, Uint8List>();
  static const int _memoLimit = 256;

  /// The configured keys.
  Iterable<DeliveryPublicKey> get keys => _keys.values;

  /// Null when [descriptor]'s signature verifies under a configured key.
  DeliveryRefusal? check(SurfaceArtifactDescriptor descriptor) {
    final signature = descriptor.signature;
    final key = _keys[signature.keyId];
    if (key == null) return DeliveryRefusal.unknownKey;
    final Uint8List statement;
    try {
      statement = descriptor.statementBytes(key.organizationId);
    } on Exception {
      // A value with no canonical form was never signed.
      return DeliveryRefusal.invalidSignature;
    }
    final memoKey = signature.toString();
    final known = _verified[memoKey];
    if (known != null && _sameBytes(known, statement)) return null;
    if (!ed25519Verify(key.bytes, statement, signature.bytes)) {
      return DeliveryRefusal.invalidSignature;
    }
    _verified[memoKey] = statement;
    if (_verified.length > _memoLimit) _verified.remove(_verified.keys.first);
    return null;
  }
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
