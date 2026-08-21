import 'dart:typed_data';

import 'package:restage_codegen/src/measurement/measurement_compiler_input.dart';
import 'package:restage_codegen/src/measurement/measurement_discovered_boundary.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Produces the ordinary compiler-known Measurement boundary for one revision.
///
/// This is a dependency-independent build-time operation. It accepts already
/// resolved compiler context and emits graph, manifest, publication, and
/// lineage documents. It never inspects a runtime widget tree or attaches a
/// carrier to an emitted host.
abstract final class MeasurementCompilerBoundary {
  /// Produces a fully reconciled boundary, or fails closed with no bytes.
  static MeasurementCompilerBoundaryResult produceBoundaryV1(
    MeasurementCompilerBoundaryInput input,
  ) {
    // The entrypoint is an accepted-set boundary: an invalid compiler input
    // must fail closed before any artifact bytes become observable.
    try {
      return _produce(input);
    } on Object catch (error) {
      return MeasurementCompilerBoundaryResult.rejected(
        reason: error.toString(),
      );
    }
  }

  /// Validates a static source-discovery closure, then produces the same
  /// boundary as [produceBoundaryV1].
  ///
  /// This bridge adds no bytes, wire fields, hash inputs, or runtime
  /// delivery behavior. It proves that the ledger-backed compiler input is
  /// exactly the resolved ordinary Flutter source closure before delegating to
  /// the accepted boundary.
  static MeasurementCompilerBoundaryResult produceDiscoveredBoundaryV1(
    MeasurementDiscoveredBoundaryInput input,
  ) {
    try {
      MeasurementDiscoveredBoundaryAdapter.validate(input);
      return produceBoundaryV1(input.boundaryInput);
    } on Object catch (error) {
      return MeasurementCompilerBoundaryResult.rejected(
        reason: error.toString(),
      );
    }
  }

  static MeasurementCompilerBoundaryResult _produce(
    MeasurementCompilerBoundaryInput input,
  ) {
    _validateBoundaryContext(input);
    _validatePriorLedger(input);

    final artifactDefinitionsById = _artifactDefinitionsById(input.artifacts);
    final artifactsByEdge = _uniqueBy(
      input.artifacts,
      (artifact) => artifact.occurrenceEdgeToken.value,
      'artifact occurrence edges',
    );
    if (input.artifacts.isEmpty) {
      throw ArgumentError('The compiler boundary requires one root artifact');
    }
    final rootArtifacts = input.artifacts
        .where((artifact) => artifact.parentOccurrenceEdgeToken == null)
        .toList(growable: false);
    if (rootArtifacts.length != 1) {
      throw ArgumentError('The compiler boundary requires exactly one root');
    }
    final rootArtifact = rootArtifacts.single;
    for (final artifact in input.artifacts) {
      final parentEdge = artifact.parentOccurrenceEdgeToken;
      if (parentEdge == null) continue;
      if (!artifactsByEdge.containsKey(parentEdge.value)) {
        throw ArgumentError(
          'Every static artifact occurrence must name an exact parent edge',
        );
      }
      if (parentEdge == artifact.occurrenceEdgeToken) {
        throw ArgumentError('An artifact occurrence cannot parent itself');
      }
    }

    final artifactIdentitiesById = <String, PublishedArtifactIdentityV1>{
      for (final artifact in artifactDefinitionsById.values)
        artifact.artifactId.value: PublishedArtifactIdentityV1(
          surfaceRevisionId: input.surfaceRevisionId,
          artifactId: artifact.artifactId,
          artifactKind: artifact.artifactKind,
          contentHash: artifact.contentHash,
        ),
    };
    final exactArtifactGraph = ExactArtifactGraphV1(
      surfaceRevisionId: input.surfaceRevisionId,
      rootEdgeToken: rootArtifact.occurrenceEdgeToken,
      artifactIdentities: artifactIdentitiesById.values.toList(),
      occurrenceEdges: [
        for (final artifact in input.artifacts)
          ArtifactOccurrenceEdgeV1(
            edgeToken: artifact.occurrenceEdgeToken,
            parentEdgeToken: artifact.parentOccurrenceEdgeToken,
            artifactId: artifact.artifactId,
            artifactIdentityHash:
                artifactIdentitiesById[artifact.artifactId.value]!
                    .canonicalDigest,
          ),
      ],
    );

    final childArtifactIdsByParent = <String, Set<ArtifactId>>{
      for (final artifact in artifactDefinitionsById.values)
        artifact.artifactId.value: <ArtifactId>{},
    };
    for (final artifact in input.artifacts) {
      final parentEdge = artifact.parentOccurrenceEdgeToken;
      if (parentEdge == null) continue;
      final parent = artifactsByEdge[parentEdge.value]!;
      childArtifactIdsByParent[parent.artifactId.value]!
          .add(artifact.artifactId);
    }

    final bindingsByCode = _uniqueBy(
      input.codeIdentityLedger.bindings,
      (binding) => binding.codeIdentityId.value,
      'code identity ledger bindings',
    );
    final canonicalTokensByCode = <String, CanonicalNodeTokenV1>{
      for (final binding in bindingsByCode.values)
        binding.codeIdentityId.value: CanonicalNodeTokenV1(
          nodeTokenId: binding.canonicalNodeTokenId,
        ),
    };
    final nodesByCode = _uniqueBy(
      input.nodes,
      (node) => node.codeIdentityId.value,
      'compiler nodes',
    );
    _requireExactKeys(
      expected: bindingsByCode.keys,
      actual: nodesByCode.keys,
      label: 'compiler nodes and the code-identity ledger',
    );
    for (final node in input.nodes) {
      if (!artifactsByEdge
          .containsKey(node.artifactOccurrenceEdgeToken.value)) {
        throw ArgumentError(
          'Every compiler node must join a static artifact occurrence',
        );
      }
      final parentCodeIdentityId = node.parentCodeIdentityId;
      if (parentCodeIdentityId != null &&
          !nodesByCode.containsKey(parentCodeIdentityId.value)) {
        throw ArgumentError(
          'Every compiler node parent must join the code-identity ledger',
        );
      }
    }

    final nodeRefsByCode = <String, AncestryNodeRefV1>{
      for (final node in input.nodes)
        node.codeIdentityId.value: AncestryNodeRefV1(
          artifactOccurrenceEdgeToken: node.artifactOccurrenceEdgeToken,
          canonicalNodeToken:
              canonicalTokensByCode[node.codeIdentityId.value]!.nodeTokenId,
        ),
    };
    final roots = input.nodes
        .where((node) => node.parentCodeIdentityId == null)
        .toList(growable: false);
    if (roots.length != 1) {
      throw ArgumentError(
        'Compiler node ancestry must have exactly one canonical root',
      );
    }
    final nodeAncestryIndex = CanonicalNodeAncestryIndexV1(
      rootNode: nodeRefsByCode[roots.single.codeIdentityId.value]!,
      directParentEdges: [
        for (final node in input.nodes)
          CanonicalNodeParentEdgeV1(
            node: nodeRefsByCode[node.codeIdentityId.value]!,
            parent: switch (node.parentCodeIdentityId) {
              final parentCodeIdentityId? =>
                nodeRefsByCode[parentCodeIdentityId.value]!,
              null => null,
            },
          ),
      ],
    );

    final eventsByNodeCode = <String, List<_ProducedEvent>>{};
    final generatedReferenceIds = <String>{};
    final currentLineages = <String>{};
    final eventSlots = <String>{};
    for (final event in input.events) {
      final node = nodesByCode[event.nodeCodeIdentityId.value];
      if (node == null) {
        throw ArgumentError(
          'Every compiler event must join a ledger-backed node',
        );
      }
      final eventSlot = '${event.nodeCodeIdentityId.value}\u0000'
          '${event.resolvedEvent.sourceEventIdentity.value}';
      if (!eventSlots.add(eventSlot)) {
        throw ArgumentError(
          'Each canonical node may claim one exact event slot once',
        );
      }
      if (!generatedReferenceIds.add(event.generatedReferenceId.value)) {
        throw ArgumentError('Generated point references must be unique');
      }
      if (!currentLineages.add(event.lineageId.value)) {
        throw ArgumentError(
          'The current compiler event set may claim a lineage once',
        );
      }

      final artifact = artifactsByEdge[node.artifactOccurrenceEdgeToken.value]!;
      // The contract freezes the occurrence preimage to the code-ledger node
      // token and exact resolved event slot. Declaration provenance remains
      // compiler evidence, not a new wire/hash field.
      final point = MeasurementPointOccurrenceV1(
        target: input.target,
        surfaceRevisionId: input.surfaceRevisionId,
        artifactGraphHash: exactArtifactGraph.canonicalDigest,
        artifactId: artifact.artifactId,
        artifactOccurrenceEdgeToken: artifact.occurrenceEdgeToken,
        artifactContentHash: artifact.contentHash,
        canonicalNodeToken:
            canonicalTokensByCode[event.nodeCodeIdentityId.value]!.nodeTokenId,
        capabilityKind: MeasurementCapabilityKind.sourceInteraction,
        sourceEventIdentity: event.resolvedEvent.sourceEventIdentity,
        normalizedInteractionKind: event.normalizedInteractionKind,
        privacyClass: event.privacyClass,
        semanticValueClass: event.semanticValueClass,
        collectionClass: event.collectionClass,
        lineageId: event.lineageId,
        displayMetadataRef: event.displayMetadataRef,
      );
      final reference = GeneratedPointReferenceV1(
        referenceId: event.generatedReferenceId,
        target: input.target,
        surfaceRevisionId: input.surfaceRevisionId,
        artifactGraphHash: exactArtifactGraph.canonicalDigest,
        occurrenceId: point.occurrenceId,
        lineageId: point.lineageId,
        sourceEventIdentity: event.resolvedEvent.sourceEventIdentity,
        dartSymbol: event.dartSymbol,
      );
      final produced = _ProducedEvent(
        event: event,
        artifactId: artifact.artifactId,
        point: point,
        reference: reference,
      );
      eventsByNodeCode
          .putIfAbsent(event.nodeCodeIdentityId.value, () => [])
          .add(produced);
    }

    final localMeasurementManifests = artifactDefinitionsById.values.toList()
      ..sort(
        (left, right) => left.artifactId.value.compareTo(
          right.artifactId.value,
        ),
      );
    final localManifests = <LocalMeasurementManifestV1>[
      for (final artifact in localMeasurementManifests)
        LocalMeasurementManifestV1(
          manifestId: artifact.localManifestId,
          target: input.target,
          surfaceRevisionId: input.surfaceRevisionId,
          artifactGraphHash: exactArtifactGraph.canonicalDigest,
          artifactId: artifact.artifactId,
          artifactContentHash: artifact.contentHash,
          childArtifactIds:
              childArtifactIdsByParent[artifact.artifactId.value]!.toList(),
          points: [
            for (final events in eventsByNodeCode.values)
              for (final event in events)
                if (event.artifactId == artifact.artifactId) event.point,
          ],
          generatedReferences: [
            for (final events in eventsByNodeCode.values)
              for (final event in events)
                if (event.artifactId == artifact.artifactId) event.reference,
          ],
          privacyPolicyRevisionId: input.privacyPolicyRevisionId,
          collectionBudgetRevisionId: input.collectionBudgetRevisionId,
        ),
    ];

    final completeMeasurementManifest = CompleteMeasurementManifestV1(
      manifestId: input.completeManifestId,
      target: input.target,
      surfaceId: input.surfaceId,
      surfaceRevisionId: input.surfaceRevisionId,
      rootArtifactId: rootArtifact.artifactId,
      artifactGraphHash: exactArtifactGraph.canonicalDigest,
      localManifests: localManifests,
      nodeAncestryIndex: nodeAncestryIndex,
      privacyPolicyRevisionId: input.privacyPolicyRevisionId,
      collectionBudgetRevisionId: input.collectionBudgetRevisionId,
    );
    final publishedSurfaceRevision = PublishedSurfaceRevisionV1(
      revisionId: input.surfaceRevisionId,
      surfaceIdentity: PublishedSurfaceIdentityV1(
        target: input.target,
        surfaceId: input.surfaceId,
      ),
      analyticsSurfaceKey: input.analyticsSurfaceKey,
      deliverySurfaceType: input.deliverySurfaceType,
      revisionOrdinal: input.revisionOrdinal,
      rootArtifactId: rootArtifact.artifactId,
      rootArtifactOccurrenceEdgeToken: rootArtifact.occurrenceEdgeToken,
      artifactGraphHash: exactArtifactGraph.canonicalDigest,
      measurementManifestHash: completeMeasurementManifest.canonicalDigest,
      measurementSchemaVersion: kMeasurementSchemaVersion,
      minimumMeasurementClient: input.minimumMeasurementClient,
    );

    final localManifestsByArtifact = {
      for (final manifest in localManifests)
        manifest.artifactId.value: manifest,
    };
    validatePublishedMeasurementBundleV1(
      surfaceRevision: publishedSurfaceRevision,
      artifactGraph: exactArtifactGraph,
      publishedArtifacts: [
        for (final artifact in localMeasurementManifests)
          PublishedArtifactV1(
            identity: artifactIdentitiesById[artifact.artifactId.value]!,
            childArtifactIds:
                childArtifactIdsByParent[artifact.artifactId.value]!.toList(),
            localMeasurementManifest:
                localManifestsByArtifact[artifact.artifactId.value]!,
          ),
      ],
      completeManifest: completeMeasurementManifest,
    );

    final lineageTransitions = [
      for (final draft in input.lineageTransitions)
        _materializeTransition(
          draft: draft,
          eventsByNodeCode: eventsByNodeCode,
          surfaceRevisionId: input.surfaceRevisionId,
        ),
    ];
    validateLineageTransitionGraph(lineageTransitions);
    _reconcileEndpoints(
      label: 'prior-active ledger and transition prior endpoints',
      expected: input.priorActiveLedger.endpoints,
      actual: [
        for (final transition in lineageTransitions) ...transition.prior,
      ],
    );
    _reconcileEndpoints(
      label: 'complete manifest and transition next endpoints',
      expected: [
        for (final point in completeMeasurementManifest.points)
          LineageEndpointV1(
            occurrenceId: point.occurrenceId,
            lineageId: point.lineageId,
          ),
      ],
      actual: [
        for (final transition in lineageTransitions) ...transition.next,
      ],
    );

    final documents = <String, Uint8List>{
      'exactArtifactGraph': exactArtifactGraph.canonicalBytes,
      for (final manifest in localManifests)
        'localMeasurementManifest.${manifest.artifactId.value}':
            manifest.canonicalBytes,
      'completeMeasurementManifest': completeMeasurementManifest.canonicalBytes,
      'publishedSurfaceRevision': publishedSurfaceRevision.canonicalBytes,
      for (final transition in lineageTransitions)
        'lineageTransition.${transition.transitionId.value}':
            transition.canonicalBytes,
    };
    return MeasurementCompilerBoundaryResult.accepted(
      exactArtifactGraph: exactArtifactGraph,
      localMeasurementManifests: localManifests,
      completeMeasurementManifest: completeMeasurementManifest,
      publishedSurfaceRevision: publishedSurfaceRevision,
      lineageTransitions: lineageTransitions,
      documents: documents,
    );
  }

  static void _validateBoundaryContext(
    MeasurementCompilerBoundaryInput input,
  ) {
    final expectedSurfaceIdentity = PublishedSurfaceIdentityV1(
      target: input.target,
      surfaceId: input.surfaceId,
    );
    if (input.codeIdentityLedger.surfaceIdentity != expectedSurfaceIdentity) {
      throw ArgumentError(
        'The code-identity ledger must join the exact target and surface',
      );
    }
  }

  static void _validatePriorLedger(MeasurementCompilerBoundaryInput input) {
    final ledger = input.priorActiveLedger;
    if (ledger.surfaceId != input.surfaceId ||
        ledger.surfaceRevisionId == input.surfaceRevisionId) {
      throw ArgumentError(
        'The prior-active ledger must join this surface and precede the '
        'current revision',
      );
    }
    _endpointIndex(
      ledger.endpoints,
      label: 'prior-active ledger endpoints',
    );
  }

  static LineageTransitionV1 _materializeTransition({
    required MeasurementLineageTransitionDraft draft,
    required Map<String, List<_ProducedEvent>> eventsByNodeCode,
    required SurfaceRevisionId surfaceRevisionId,
  }) {
    return LineageTransitionV1(
      transitionId: draft.transitionId,
      publishedSurfaceRevisionId: surfaceRevisionId,
      operation: draft.operation,
      authority: draft.authority,
      prior: draft.prior,
      next: [
        for (final claim in draft.next)
          _resolveCurrentEndpoint(claim, eventsByNodeCode),
      ],
    );
  }

  static LineageEndpointV1 _resolveCurrentEndpoint(
    MeasurementCurrentEndpointClaim claim,
    Map<String, List<_ProducedEvent>> eventsByNodeCode,
  ) {
    final candidates = eventsByNodeCode[claim.codeIdentityId.value];
    if (candidates == null || candidates.isEmpty) {
      throw ArgumentError(
        'A transition next endpoint must name one current compiler event',
      );
    }
    final selected = switch (claim.sourceEventIdentity) {
      final sourceEventIdentity? => candidates
          .where(
            (candidate) =>
                candidate.event.resolvedEvent.sourceEventIdentity ==
                sourceEventIdentity,
          )
          .toList(growable: false),
      null => candidates,
    };
    if (selected.length != 1) {
      throw ArgumentError(
        'A transition next endpoint must identify one exact current '
        'compiler event',
      );
    }
    final event = selected.single;
    if (event.point.lineageId != claim.lineageId) {
      throw ArgumentError(
        'A transition next claim must match the current event lineage',
      );
    }
    return LineageEndpointV1(
      occurrenceId: event.point.occurrenceId,
      lineageId: event.point.lineageId,
    );
  }

  static void _reconcileEndpoints({
    required String label,
    required List<LineageEndpointV1> expected,
    required List<LineageEndpointV1> actual,
  }) {
    final expectedByKey = _endpointIndex(expected, label: 'expected $label');
    final actualByKey = _endpointIndex(actual, label: 'actual $label');
    _requireExactKeys(
      expected: expectedByKey.keys,
      actual: actualByKey.keys,
      label: label,
    );
  }
}

final class _ProducedEvent {
  const _ProducedEvent({
    required this.event,
    required this.artifactId,
    required this.point,
    required this.reference,
  });

  final MeasurementCompilerEventInput event;
  final ArtifactId artifactId;
  final MeasurementPointOccurrenceV1 point;
  final GeneratedPointReferenceV1 reference;
}

Map<String, T> _uniqueBy<T>(
  Iterable<T> values,
  String Function(T value) keyOf,
  String label,
) {
  final byKey = <String, T>{};
  for (final value in values) {
    final key = keyOf(value);
    if (byKey.containsKey(key)) {
      throw ArgumentError('$label must be unique');
    }
    byKey[key] = value;
  }
  return byKey;
}

/// Collapses repeated occurrence inputs to their one immutable artifact
/// definition while preserving every distinct occurrence edge separately.
Map<String, MeasurementArtifactInput> _artifactDefinitionsById(
  Iterable<MeasurementArtifactInput> artifacts,
) {
  final definitions = <String, MeasurementArtifactInput>{};
  for (final artifact in artifacts) {
    final existing = definitions[artifact.artifactId.value];
    if (existing == null) {
      definitions[artifact.artifactId.value] = artifact;
      continue;
    }
    if (existing.artifactKind != artifact.artifactKind ||
        existing.contentHash != artifact.contentHash ||
        existing.localManifestId != artifact.localManifestId) {
      throw ArgumentError(
        'Repeated artifact occurrences must preserve one exact artifact '
        'definition and local manifest provenance',
      );
    }
  }
  return definitions;
}

Map<String, LineageEndpointV1> _endpointIndex(
  Iterable<LineageEndpointV1> endpoints, {
  required String label,
}) {
  final byEndpoint = <String, LineageEndpointV1>{};
  final lineageByOccurrence = <String, String>{};
  final occurrenceByLineage = <String, String>{};
  for (final endpoint in endpoints) {
    final occurrenceId = endpoint.occurrenceId.hex;
    final lineageId = endpoint.lineageId.value;
    final existingLineage = lineageByOccurrence[occurrenceId];
    if (existingLineage != null) {
      if (existingLineage != lineageId) {
        throw ArgumentError('$label conflicts on one occurrence identity');
      }
      throw ArgumentError('$label duplicates one occurrence identity');
    }
    final existingOccurrence = occurrenceByLineage[lineageId];
    if (existingOccurrence != null) {
      throw ArgumentError('$label duplicates one active lineage identity');
    }
    lineageByOccurrence[occurrenceId] = lineageId;
    occurrenceByLineage[lineageId] = occurrenceId;
    byEndpoint[_endpointKey(endpoint)] = endpoint;
  }
  return byEndpoint;
}

String _endpointKey(LineageEndpointV1 endpoint) =>
    '${endpoint.occurrenceId.hex}\u0000${endpoint.lineageId.value}';

void _requireExactKeys({
  required Iterable<String> expected,
  required Iterable<String> actual,
  required String label,
}) {
  final expectedSet = expected.toSet();
  final actualSet = actual.toSet();
  if (expectedSet.length != actualSet.length ||
      !expectedSet.containsAll(actualSet) ||
      !actualSet.containsAll(expectedSet)) {
    throw ArgumentError('$label must reconcile as one exact accepted set');
  }
}
