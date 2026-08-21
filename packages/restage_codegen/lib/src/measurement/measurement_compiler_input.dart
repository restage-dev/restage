import 'dart:typed_data';

import 'package:restage_codegen/src/measurement/measurement_resolved_event.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// One static artifact occurrence admitted to the ordinary compiler boundary.
///
/// The optional parent edge describes only the compile-time artifact closure;
/// it is not a runtime widget-tree relation.
final class MeasurementArtifactInput {
  /// Creates one statically resolved artifact occurrence.
  MeasurementArtifactInput({
    required this.artifactId,
    required this.artifactKind,
    required this.contentHash,
    required this.occurrenceEdgeToken,
    required this.localManifestId,
    this.parentOccurrenceEdgeToken,
  });

  /// Stable identity of the artifact definition.
  final ArtifactId artifactId;

  /// Registered static artifact kind.
  final ArtifactKindId artifactKind;

  /// Immutable content digest of the artifact.
  final CanonicalDigest contentHash;

  /// Exact occurrence edge in this compiled revision.
  final ArtifactOccurrenceEdgeToken occurrenceEdgeToken;

  /// Compiler-assigned local manifest identity.
  final MeasurementManifestId localManifestId;

  /// Parent occurrence edge, absent only for the graph root.
  final ArtifactOccurrenceEdgeToken? parentOccurrenceEdgeToken;
}

/// One exact code-identity node in the static compiler closure.
final class MeasurementCompilerNodeInput {
  /// Creates a ledger-backed canonical node in the static closure.
  MeasurementCompilerNodeInput({
    required this.codeIdentityId,
    required this.artifactOccurrenceEdgeToken,
    this.parentCodeIdentityId,
  });

  /// code identity bound to this node.
  final CodeIdentityId codeIdentityId;

  /// Artifact occurrence containing this node.
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;

  /// Direct canonical parent code identity, absent only for the root.
  final CodeIdentityId? parentCodeIdentityId;
}

/// Metadata attached to one compiler-known static event slot.
final class MeasurementCompilerEventInput {
  /// Creates metadata for one compiler-known static event slot.
  MeasurementCompilerEventInput({
    required this.nodeCodeIdentityId,
    required this.resolvedEvent,
    required this.lineageId,
    required this.generatedReferenceId,
    required this.dartSymbol,
    required this.displayMetadataRef,
    required this.normalizedInteractionKind,
    required this.privacyClass,
    required this.semanticValueClass,
    required this.collectionClass,
  });

  /// Ledger-backed node containing the callback.
  final CodeIdentityId nodeCodeIdentityId;

  /// Strict analyzer-derived event provenance and frozen source selector.
  final MeasurementResolvedEvent resolvedEvent;

  /// Current reviewed lineage of the callback occurrence.
  final PointLineageId lineageId;

  /// Generated-reference identity for emitted code.
  final GeneratedReferenceId generatedReferenceId;

  /// Generated Dart symbol for the source-level reference.
  final GeneratedDartSymbol dartSymbol;

  /// Non-identity display metadata reference.
  final DisplayMetadataRef displayMetadataRef;

  /// Catalog-normalized interaction semantics.
  final NormalizedInteractionKind normalizedInteractionKind;

  /// Policy-derived privacy classification.
  final MeasurementPrivacyClass privacyClass;

  /// Admitted semantic-value category.
  final SemanticValueClass semanticValueClass;

  /// Policy-derived collection treatment.
  final MeasurementCollectionClass collectionClass;

  /// Replaces non-identity metadata or a reviewed lineage decision.
  MeasurementCompilerEventInput copyWith({
    PointLineageId? lineageId,
    GeneratedReferenceId? generatedReferenceId,
    GeneratedDartSymbol? dartSymbol,
    DisplayMetadataRef? displayMetadataRef,
    NormalizedInteractionKind? normalizedInteractionKind,
    MeasurementPrivacyClass? privacyClass,
    SemanticValueClass? semanticValueClass,
    MeasurementCollectionClass? collectionClass,
  }) =>
      MeasurementCompilerEventInput(
        nodeCodeIdentityId: nodeCodeIdentityId,
        resolvedEvent: resolvedEvent,
        lineageId: lineageId ?? this.lineageId,
        generatedReferenceId: generatedReferenceId ?? this.generatedReferenceId,
        dartSymbol: dartSymbol ?? this.dartSymbol,
        displayMetadataRef: displayMetadataRef ?? this.displayMetadataRef,
        normalizedInteractionKind:
            normalizedInteractionKind ?? this.normalizedInteractionKind,
        privacyClass: privacyClass ?? this.privacyClass,
        semanticValueClass: semanticValueClass ?? this.semanticValueClass,
        collectionClass: collectionClass ?? this.collectionClass,
      );
}

/// Typed prior-active endpoint ledger supplied by the compiler's prior state.
///
/// The codegen package owns this boundary input rather than extending a
/// wire/hash domain. Its canonical bytes make the exact ledger material
/// inspectable without changing contracts.
final class PriorActiveLineageLedgerV1 {
  /// Creates a prior active lineage set for one previous revision.
  PriorActiveLineageLedgerV1({
    required this.surfaceId,
    required this.surfaceRevisionId,
    required List<LineageEndpointV1> endpoints,
  }) : endpoints = List.unmodifiable(endpoints);

  /// Stable surface owning the prior active set.
  final SurfaceId surfaceId;

  /// Revision from which the prior endpoints came.
  final SurfaceRevisionId surfaceRevisionId;

  /// Complete prior active endpoint set before transition reconciliation.
  final List<LineageEndpointV1> endpoints;

  /// Deterministic, non-contract-domain bytes for boundary input inspection.
  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  /// Canonical inspection representation, outside hash domains.
  Map<String, Object?> toJson() => {
        'endpoints': [
          for (final endpoint in _sortedEndpoints(endpoints)) endpoint.toJson(),
        ],
        'kind': 'priorActiveLineageLedger',
        'schemaVersion': kMeasurementSchemaVersion,
        'surfaceId': surfaceId.value,
        'surfaceRevisionId': surfaceRevisionId.value,
      };
}

/// A next-endpoint claim expressed against compiler code identity.
///
/// [sourceEventIdentity] is required only when a single canonical node owns
/// multiple event slots; omitting it is accepted solely when the node has one
/// unambiguous current event.
final class MeasurementCurrentEndpointClaim {
  /// Creates one current endpoint claim against compiler identity.
  MeasurementCurrentEndpointClaim({
    required this.codeIdentityId,
    required this.lineageId,
    this.sourceEventIdentity,
  });

  /// Canonical node code identity for the claimed event.
  final CodeIdentityId codeIdentityId;

  /// Lineage the claimed current occurrence must carry.
  final PointLineageId lineageId;

  /// Explicit event slot when the canonical node has multiple callbacks.
  final SourceEventIdentity? sourceEventIdentity;
}

/// One compiler-provided lineage decision before occurrence IDs are
/// materialized.
final class MeasurementLineageTransitionDraft {
  /// Creates one unmaterialized lineage transition decision.
  MeasurementLineageTransitionDraft({
    required this.transitionId,
    required this.operation,
    required this.authority,
    List<LineageEndpointV1> prior = const [],
    List<MeasurementCurrentEndpointClaim> next = const [],
  })  : prior = List.unmodifiable(prior),
        next = List.unmodifiable(next);

  /// Stable transition identity.
  final LineageTransitionId transitionId;

  /// Reviewed operation shape.
  final LineageOperation operation;

  /// Authority that admitted this operation.
  final LineageTransitionAuthority authority;

  /// Exact prior endpoints from the prior-active ledger.
  final List<LineageEndpointV1> prior;

  /// Current endpoints before occurrence IDs are materialized.
  final List<MeasurementCurrentEndpointClaim> next;
}

/// Complete resolved compiler input for the dependency-independent boundary.
final class MeasurementCompilerBoundaryInput {
  /// Creates the complete resolved input to the production boundary.
  MeasurementCompilerBoundaryInput({
    required this.target,
    required this.surfaceId,
    required this.surfaceRevisionId,
    required this.revisionOrdinal,
    required this.analyticsSurfaceKey,
    required this.deliverySurfaceType,
    required this.minimumMeasurementClient,
    required this.completeManifestId,
    required this.privacyPolicyRevisionId,
    required this.collectionBudgetRevisionId,
    required List<MeasurementArtifactInput> artifacts,
    required this.codeIdentityLedger,
    required List<MeasurementCompilerNodeInput> nodes,
    required List<MeasurementCompilerEventInput> events,
    required this.priorActiveLedger,
    required List<MeasurementLineageTransitionDraft> lineageTransitions,
  })  : artifacts = List.unmodifiable(artifacts),
        nodes = List.unmodifiable(nodes),
        events = List.unmodifiable(events),
        lineageTransitions = List.unmodifiable(lineageTransitions);

  /// Exact target authority for the resulting documents.
  final TargetCoordinate target;

  /// Stable surface identity for the resulting revision.
  final SurfaceId surfaceId;

  /// Immutable revision being compiled.
  final SurfaceRevisionId surfaceRevisionId;

  /// Positive ordinal of [surfaceRevisionId].
  final int revisionOrdinal;

  /// Analytics key sealed into the publication revision.
  final AnalyticsSurfaceKey analyticsSurfaceKey;

  /// Registered delivery-surface adapter identity.
  final DeliverySurfaceTypeId deliverySurfaceType;

  /// Minimum Measurement client capability revision.
  final int minimumMeasurementClient;

  /// Identity for the complete manifest closure.
  final MeasurementManifestId completeManifestId;

  /// Immutable privacy policy revision.
  final AuthorityRevisionId privacyPolicyRevisionId;

  /// Immutable collection budget revision.
  final AuthorityRevisionId collectionBudgetRevisionId;

  /// Complete static artifact occurrence closure.
  final List<MeasurementArtifactInput> artifacts;

  /// Strict code-to-canonical-node identity ledger.
  final CodeIdentityLedgerV1 codeIdentityLedger;

  /// Complete canonical node ancestry input.
  final List<MeasurementCompilerNodeInput> nodes;

  /// Compiler-known static event slot inputs.
  final List<MeasurementCompilerEventInput> events;

  /// Complete active set from the prior revision.
  final PriorActiveLineageLedgerV1 priorActiveLedger;

  /// Complete reviewed transition set to the current revision.
  final List<MeasurementLineageTransitionDraft> lineageTransitions;

  /// Copies the input for compiler-only mutation and negative testing.
  MeasurementCompilerBoundaryInput copyWith({
    List<MeasurementArtifactInput>? artifacts,
    CodeIdentityLedgerV1? codeIdentityLedger,
    List<MeasurementCompilerNodeInput>? nodes,
    List<MeasurementCompilerEventInput>? events,
    PriorActiveLineageLedgerV1? priorActiveLedger,
    List<MeasurementLineageTransitionDraft>? lineageTransitions,
  }) =>
      MeasurementCompilerBoundaryInput(
        target: target,
        surfaceId: surfaceId,
        surfaceRevisionId: surfaceRevisionId,
        revisionOrdinal: revisionOrdinal,
        analyticsSurfaceKey: analyticsSurfaceKey,
        deliverySurfaceType: deliverySurfaceType,
        minimumMeasurementClient: minimumMeasurementClient,
        completeManifestId: completeManifestId,
        privacyPolicyRevisionId: privacyPolicyRevisionId,
        collectionBudgetRevisionId: collectionBudgetRevisionId,
        artifacts: artifacts ?? this.artifacts,
        codeIdentityLedger: codeIdentityLedger ?? this.codeIdentityLedger,
        nodes: nodes ?? this.nodes,
        events: events ?? this.events,
        priorActiveLedger: priorActiveLedger ?? this.priorActiveLedger,
        lineageTransitions: lineageTransitions ?? this.lineageTransitions,
      );
}

/// Whether the production boundary accepted or rejected the complete closure.
enum MeasurementCompilerBoundaryDisposition {
  /// The complete closure reconciled and produced documents.
  accepted,

  /// One governing invariant failed before output became observable.
  rejected,
}

/// Typed products and byte-exact documents produced by the compiler boundary.
final class MeasurementCompilerBoundaryResult {
  /// Creates an accepted typed boundary result and exact document bytes.
  MeasurementCompilerBoundaryResult.accepted({
    required this.exactArtifactGraph,
    required List<LocalMeasurementManifestV1> localMeasurementManifests,
    required this.completeMeasurementManifest,
    required this.publishedSurfaceRevision,
    required List<LineageTransitionV1> lineageTransitions,
    required Map<String, Uint8List> documents,
  })  : disposition = MeasurementCompilerBoundaryDisposition.accepted,
        rejectionReason = null,
        localMeasurementManifests =
            List.unmodifiable(localMeasurementManifests),
        lineageTransitions = List.unmodifiable(lineageTransitions),
        _documents = _immutableDocuments(documents);

  /// Creates a rejected result with no typed products or emitted bytes.
  MeasurementCompilerBoundaryResult.rejected({
    required String reason,
  })  : disposition = MeasurementCompilerBoundaryDisposition.rejected,
        rejectionReason = reason,
        exactArtifactGraph = null,
        localMeasurementManifests = const [],
        completeMeasurementManifest = null,
        publishedSurfaceRevision = null,
        lineageTransitions = const [],
        _documents = const {};

  /// Stable discriminator used by the schema contract adapter.
  static const String productionEntrypointName =
      'compiler.measurement.produceBoundaryV1';

  /// Whether the complete accepted set was produced.
  final MeasurementCompilerBoundaryDisposition disposition;

  /// Exact artifact graph on acceptance.
  final ExactArtifactGraphV1? exactArtifactGraph;

  /// Complete artifact-local manifest closure on acceptance.
  final List<LocalMeasurementManifestV1> localMeasurementManifests;

  /// Complete manifest on acceptance.
  final CompleteMeasurementManifestV1? completeMeasurementManifest;

  /// Publication revision sealing the graph and complete manifest.
  final PublishedSurfaceRevisionV1? publishedSurfaceRevision;

  /// Complete materialized lineage transition set on acceptance.
  final List<LineageTransitionV1> lineageTransitions;

  /// Canonical document bytes, empty on rejection.
  ///
  /// Each read returns defensive byte copies so callers cannot mutate the
  /// accepted compiler result through a [Uint8List] value.
  Map<String, Uint8List> get documents => _immutableDocuments(_documents);

  final Map<String, Uint8List> _documents;

  /// Fail-closed reason when [disposition] is rejected.
  final String? rejectionReason;

  /// Identifies the production compiler entrypoint, even on rejection.
  String get productionEntrypoint => productionEntrypointName;
}

Map<String, Uint8List> _immutableDocuments(Map<String, Uint8List> documents) =>
    Map.unmodifiable({
      for (final entry in documents.entries)
        entry.key: Uint8List.fromList(entry.value),
    });

List<LineageEndpointV1> _sortedEndpoints(List<LineageEndpointV1> endpoints) {
  final sorted = endpoints.toList()
    ..sort(
      (left, right) =>
          '${left.occurrenceId.hex}\u0000${left.lineageId.value}'.compareTo(
        '${right.occurrenceId.hex}\u0000${right.lineageId.value}',
      ),
    );
  return sorted;
}
