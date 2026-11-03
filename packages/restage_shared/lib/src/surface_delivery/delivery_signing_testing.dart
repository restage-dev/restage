import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_shared/src/surface_delivery/delivery_signature.dart';
import 'package:restage_shared/src/surface_delivery/ed25519_verify.dart';
import 'package:restage_shared/src/surface_delivery/surface_artifact_descriptor.dart';

/// Signs delivery statements with a fixed key, for tests.
@visibleForTesting
final class TestDeliverySigner {
  /// A signer for [organizationId] whose key derives from [seedByte].
  TestDeliverySigner({this.organizationId = 1, int seedByte = 7})
      : _seed = Uint8List(32)..fillRange(0, 32, seedByte) {
    publicKey = DeliveryPublicKey(
      organizationId: organizationId,
      bytes: ed25519SignForTesting(_seed, const []).$1,
    );
  }

  /// The organization the key signs for.
  final int organizationId;
  final Uint8List _seed;

  /// The public key, as an app is configured with it.
  late final DeliveryPublicKey publicKey;

  /// Signs [statement].
  DeliverySignature sign(List<int> statement) => DeliverySignature(
        keyId: publicKey.keyId,
        bytes: ed25519SignForTesting(_seed, statement).$2,
      );

  /// The signature over [descriptor]'s statement, whatever it carries now.
  DeliverySignature signatureFor(SurfaceArtifactDescriptor descriptor) =>
      sign(descriptor.statementBytes(organizationId));

  /// [descriptor] with this key's signature.
  SurfaceArtifactDescriptor signed(SurfaceArtifactDescriptor descriptor) =>
      SurfaceArtifactDescriptor(
        payloadFormatVersion: descriptor.payloadFormatVersion,
        surfaceType: descriptor.surfaceType,
        surfaceSlug: descriptor.surfaceSlug,
        version: descriptor.version,
        publishedAtMicros: descriptor.publishedAtMicros,
        contentHash: descriptor.contentHash,
        artifactUrl: descriptor.artifactUrl,
        artifactPass: descriptor.artifactPass,
        signature: signatureFor(descriptor),
        authorizedAtMicros: descriptor.authorizedAtMicros,
        payloadKind: descriptor.payloadKind,
        fitRequirementHash: descriptor.fitRequirementHash,
      );

  /// Descriptor JSON with this key's signature over its fields.
  Map<String, Object?> signJson(Map<String, Object?> json) {
    final unsigned = {
      'signature':
          DeliverySignature(keyId: '0' * 16, bytes: Uint8List(64)).toString(),
      'authorizedAtMicros': json['publishedAtMicros'],
      'descriptorVersion': kSurfaceArtifactDescriptorVersion,
      ...json,
    };
    final descriptor = SurfaceArtifactDescriptorV1Codec.decode(unsigned);
    return {...unsigned, 'signature': signatureFor(descriptor).toString()};
  }
}
