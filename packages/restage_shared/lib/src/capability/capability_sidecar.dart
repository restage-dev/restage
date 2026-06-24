import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_shared/src/capability/capability_manifest.dart';

/// The build-time sidecar emitted next to a compiled surface blob: the derived
/// [CapabilityManifest] plus the `sha256:` content hash of the blob it was
/// derived from.
///
/// The hash ties the sidecar to its blob by construction. A consumer that reads
/// the sidecar to stamp a publish recomputes the blob's hash and rejects a
/// mismatch — so a stale sidecar can never under-stamp a blob that changed
/// without it (a partial build, a hand-edit, a committed sidecar gone stale).
@immutable
final class CapabilitySidecar {
  /// Creates a sidecar pairing [manifest] with the [blobSha256] of its blob.
  /// [blobSha256] must be in `sha256:<64 lowercase hex>` form.
  CapabilitySidecar({required this.blobSha256, required this.manifest})
      : assert(
          _sha256Pattern.hasMatch(blobSha256),
          'blobSha256 must be sha256:<64 lowercase hex>',
        );

  /// Decodes a sidecar from its JSON wire form.
  factory CapabilitySidecar.fromJson(Map<String, dynamic> json) {
    final blobSha256 = json['blobSha256'];
    final manifest = json['manifest'];
    if (blobSha256 is! String || manifest is! Map<String, dynamic>) {
      throw FormatException('malformed CapabilitySidecar: $json');
    }
    if (!_sha256Pattern.hasMatch(blobSha256)) {
      throw FormatException(
        'malformed CapabilitySidecar blobSha256: $blobSha256',
      );
    }
    return CapabilitySidecar(
      blobSha256: blobSha256,
      manifest: CapabilityManifest.fromJson(manifest),
    );
  }

  /// The `sha256:<64 hex>` content hash of [blob] — the value a sidecar records
  /// so a consumer can reject a sidecar that has drifted from its blob. Lives
  /// here so the codegen and the publisher hash blobs identically without each
  /// depending on a crypto library directly.
  static String hashBlob(List<int> blob) =>
      'sha256:${crypto.sha256.convert(blob)}';

  static final RegExp _sha256Pattern = RegExp(r'^sha256:[0-9a-f]{64}$');

  /// The `sha256:<64 hex>` content hash of the blob this sidecar describes.
  final String blobSha256;

  /// The derived capability manifest for the paired blob.
  final CapabilityManifest manifest;

  /// JSON wire form.
  Map<String, dynamic> toJson() => {
        'blobSha256': blobSha256,
        'manifest': manifest.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CapabilitySidecar &&
          other.blobSha256 == blobSha256 &&
          other.manifest == manifest;

  @override
  int get hashCode => Object.hash(blobSha256, manifest);
}
