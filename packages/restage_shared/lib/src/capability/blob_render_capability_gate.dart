import 'package:meta/meta.dart';
import 'package:restage_shared/src/capability/capability_manifest.dart';
import 'package:restage_shared/src/capability/installed_capability.dart';

/// The revision of BlobRenderCapabilityGate's decision logic. Bump this
/// whenever the gate's accept/reject semantics change; a memoized eligibility
/// verdict computed at a prior revision is stale and must never be read back.
const int kBlobGateLogicRevision = 1;

/// The result of evaluating whether an installed renderer can render a blob.
sealed class BlobRenderVerdict {
  const BlobRenderVerdict();

  /// Whether the blob can be rendered.
  bool get accepted;
}

/// A verdict accepting the blob for rendering.
@immutable
final class BlobRenderAccepted extends BlobRenderVerdict {
  /// Creates an accepted verdict.
  const BlobRenderAccepted();

  @override
  bool get accepted => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BlobRenderAccepted;

  @override
  int get hashCode => (BlobRenderAccepted).hashCode;
}

/// The reason an installed renderer cannot render a blob.
enum BlobRenderRejectionReason {
  /// The blob requires a newer built-in catalog.
  capabilityFloorRaised,

  /// A required custom library is absent, unversioned, or too old.
  requiredLibraryUnsatisfied,
}

/// A verdict rejecting the blob for rendering.
@immutable
final class BlobRenderRejected extends BlobRenderVerdict {
  /// Creates a rejected verdict.
  const BlobRenderRejected({required this.reason, required this.message});

  /// Why the blob was rejected.
  final BlobRenderRejectionReason reason;

  /// A diagnostic describing the capability gap.
  final String message;

  @override
  bool get accepted => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlobRenderRejected &&
          other.reason == reason &&
          other.message == message;

  @override
  int get hashCode => Object.hash(reason, message);
}

/// Evaluates whether an installed renderer satisfies a blob's requirements.
abstract final class BlobRenderCapabilityGate {
  /// Evaluates [required] against [installed].
  static BlobRenderVerdict evaluate({
    required CapabilityManifest required,
    required InstalledCapability installed,
  }) {
    if (required.builtInFloor > installed.builtInCatalogVersion) {
      return BlobRenderRejected(
        reason: BlobRenderRejectionReason.capabilityFloorRaised,
        message: 'requires built-in catalog version ${required.builtInFloor}, '
            'above the installed ${installed.builtInCatalogVersion}',
      );
    }

    for (final requirement in required.requiredLibraries) {
      final library = _findLibrary(installed, requirement.namespace);
      final version = library?.version;
      if (version != null && version >= requirement.minVersion) continue;

      final gap = library == null
          ? 'not registered'
          : library.version == null
              ? 'registered without a capability version'
              : 'installed v${library.version}';
      return BlobRenderRejected(
        reason: BlobRenderRejectionReason.requiredLibraryUnsatisfied,
        message: 'requires library "${requirement.namespace}" '
            '>= v${requirement.minVersion} ($gap)',
      );
    }

    return const BlobRenderAccepted();
  }

  static InstalledLibrary? _findLibrary(
    InstalledCapability installed,
    String namespace,
  ) {
    for (final library in installed.installedLibraries) {
      if (library.namespace == namespace) return library;
    }
    return null;
  }
}
