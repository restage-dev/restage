import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show CanonicalJsonCodec;

/// The signature scheme every delivered artifact is signed with.
const String kDeliverySignatureScheme = 'ed25519';

/// Prefix of the signed bytes, so a delivery signature can never be read as a
/// signature over anything else.
const String _statementDomain = 'restage-delivery-v1\n';

/// The bytes a delivery signature covers.
///
/// The frame's capability floor and required libraries are covered through
/// [contentHash], and the published fit requirement through
/// [fitRequirementHash] (null when the version has none). [authorizedAtMicros]
/// is when the server last made this version servable: its publication, or a
/// later activation or rollback.
Uint8List deliveryStatementBytes({
  required int organizationId,
  required String surfaceType,
  required String surfaceSlug,
  required int version,
  required int payloadFormatVersion,
  required String contentHash,
  required int publishedAtMicros,
  required int authorizedAtMicros,
  required String? fitRequirementHash,
}) =>
    Uint8List.fromList([
      ...utf8.encode(_statementDomain),
      ...CanonicalJsonCodec.encode({
        'authorizedAtMicros': authorizedAtMicros,
        'contentHash': contentHash,
        'fitRequirementHash': fitRequirementHash,
        'organizationId': organizationId,
        'payloadFormatVersion': payloadFormatVersion,
        'publishedAtMicros': publishedAtMicros,
        'surfaceSlug': surfaceSlug,
        'surfaceType': surfaceType,
        'version': version,
      }),
    ]);

/// The key id of a raw 32-byte Ed25519 public key: the first 16 hex digits of
/// its SHA-256.
String deliveryKeyId(List<int> publicKey) {
  if (publicKey.length != 32) {
    throw const FormatException('An Ed25519 public key is 32 bytes.');
  }
  return crypto.sha256.convert(publicKey).toString().substring(0, 16);
}

/// One delivery signature: `ed25519:<keyId>:<base64url signature>`.
@immutable
final class DeliverySignature {
  /// Creates a signature by [keyId] over a statement.
  DeliverySignature({required this.keyId, required List<int> bytes})
      : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (!_keyIdPattern.hasMatch(keyId)) {
      throw const FormatException('A delivery key id is 16 lowercase hex.');
    }
    if (bytes.length != 64) {
      throw const FormatException('An Ed25519 signature is 64 bytes.');
    }
  }

  /// Parses the wire form.
  factory DeliverySignature.parse(String value) {
    final parts = value.split(':');
    if (parts.length != 3 || parts[0] != kDeliverySignatureScheme) {
      throw const FormatException('Unsupported delivery signature.');
    }
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(parts[2]);
    } on FormatException {
      throw const FormatException('A delivery signature is base64url.');
    }
    final signature = DeliverySignature(keyId: parts[1], bytes: bytes);
    if (signature.toString() != value) {
      throw const FormatException('A delivery signature is not canonical.');
    }
    return signature;
  }

  static final RegExp _keyIdPattern = RegExp(r'^[0-9a-f]{16}$');

  /// The signing key's id, see [deliveryKeyId].
  final String keyId;

  /// The 64 signature bytes.
  final Uint8List bytes;

  @override
  String toString() =>
      '$kDeliverySignatureScheme:$keyId:${base64Url.encode(bytes)}';

  @override
  bool operator ==(Object other) =>
      other is DeliverySignature && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}

/// A public key an app accepts delivered artifacts from.
@immutable
final class DeliveryPublicKey {
  /// Creates a key of [organizationId] from its raw 32 bytes.
  DeliveryPublicKey({required this.organizationId, required List<int> bytes})
      : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
        keyId = deliveryKeyId(bytes);

  /// Parses `<organizationId>:<base64url public key>`, the form codegen and
  /// the CLI print.
  factory DeliveryPublicKey.parse(String value) {
    final separator = value.indexOf(':');
    final organizationId =
        separator < 1 ? null : int.tryParse(value.substring(0, separator));
    if (organizationId == null || organizationId < 1) {
      throw const FormatException(
        'A delivery key is <organizationId>:<base64url public key>.',
      );
    }
    return DeliveryPublicKey(
      organizationId: organizationId,
      bytes: base64Url.decode(value.substring(separator + 1)),
    );
  }

  /// The organization whose artifacts this key signs.
  final int organizationId;

  /// The raw 32-byte Ed25519 public key.
  final Uint8List bytes;

  /// The key's id, see [deliveryKeyId].
  final String keyId;

  @override
  String toString() => '$organizationId:${base64Url.encode(bytes)}';

  @override
  bool operator ==(Object other) =>
      other is DeliveryPublicKey && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}
