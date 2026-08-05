import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

import 'flow_resolver.dart';

/// Immutable metadata associated with an already validated [ResolvedFlow].
///
/// Resolver results expose this type from `metadataFor`; the library list is
/// defensively copied and cannot be mutated through the returned value. The
/// type itself is the payload-integrity witness: only the internal exact-owner
/// authority can mint an instance.
@immutable
final class FlowExperimentArtifactMetadata {
  const FlowExperimentArtifactMetadata._({
    required this.requiredLibraries,
  });

  /// Custom-library capability requirements verified for the flow artifact.
  final List<LibraryRequirement> requiredLibraries;

  /// The resolver verified the delivered payload's integrity before minting.
  bool get payloadIntegrityVerified => true;
}

/// Internal resolver capability for recovering validated envelope metadata.
///
/// Built-in asset and server resolvers expose metadata only for the exact flow
/// object they produced.
@internal
abstract interface class FlowExperimentArtifactMetadataProvider {
  FlowExperimentArtifactMetadata metadataFor(ResolvedFlow flow);
}

/// Object-exact weak ownership registry for resolver-produced artifacts.
///
/// The Expando does not retain cache-hit result objects. Resolver identity is
/// stored alongside metadata so an equal artifact from another resolver cannot
/// borrow metadata that was validated for a different object/producer pair.
@internal
abstract final class FlowExperimentArtifactOwnership {
  static final Expando<
      ({
        Object owner,
        FlowExperimentArtifactMetadata metadata,
      })> _associations = Expando();

  /// Mints metadata only for a resolver-owned, integrity-verified artifact.
  static FlowExperimentArtifactMetadata verifiedMetadata({
    required List<LibraryRequirement> requiredLibraries,
  }) =>
      FlowExperimentArtifactMetadata._(
        requiredLibraries: List.unmodifiable(requiredLibraries),
      );

  /// Associates [flow] with the exact resolver that produced it.
  static void attach({
    required Object owner,
    required ResolvedFlow flow,
    required FlowExperimentArtifactMetadata metadata,
  }) {
    final existing = _associations[flow];
    if (existing != null && !identical(existing.owner, owner)) {
      throw StateError('ResolvedFlow already belongs to another resolver.');
    }
    _associations[flow] = (owner: owner, metadata: metadata);
  }

  /// Returns metadata only for the exact `(owner, flow object)` association.
  static FlowExperimentArtifactMetadata metadataFor({
    required Object owner,
    required ResolvedFlow flow,
  }) {
    final association = _associations[flow];
    if (association == null || !identical(association.owner, owner)) {
      throw StateError('ResolvedFlow was not produced by this resolver.');
    }
    return association.metadata;
  }
}
