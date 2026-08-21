// Internal analyzer-to-publication planning seam.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_source_discovery.dart';
import 'package:restage_codegen/src/measurement/measurement_surface_identity.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

/// Exact discovered source assigned to one final publication blob artifact.
final class MeasurementPublicationSourceArtifact {
  const MeasurementPublicationSourceArtifact({
    required this.artifactPath,
    required this.discovery,
  });

  final String artifactPath;
  final MeasurementSourceDiscoveryResult discovery;
}

/// Analyzer and surface publication closure for one target-neutral publication
/// plan.
final class MeasurementPublicationPlanningInput {
  MeasurementPublicationPlanningInput({
    required this.entry,
    required Iterable<MeasurementPublicationSourceArtifact> sourceArtifacts,
  }) : sourceArtifacts = List.unmodifiable(sourceArtifacts);

  final SurfacePublicationManifestEntry entry;
  final List<MeasurementPublicationSourceArtifact> sourceArtifacts;

  MeasurementPublicationSelectorV1 get selector =>
      MeasurementPublicationSelectorV1.fromPublication(entry.publication);
}

/// Reconciled ledger and carrier-independent plans for one compiler pass.
final class MeasurementPublicationPlanningResult {
  MeasurementPublicationPlanningResult({
    required Iterable<String> errors,
    required this.nextIdentitySequence,
    required Iterable<MeasurementCompilerLedgerNode> ledgerNodes,
    required Iterable<MeasurementCompilerLedgerProposal> proposals,
    required Map<String, MeasurementPublicationRoutePlanV1> routePlansByKey,
    required Map<String, CodeIdentityId> codeIdentityByStructuralOccurrenceKey,
  })  : errors = List.unmodifiable(errors),
        ledgerNodes = List.unmodifiable(ledgerNodes),
        proposals = List.unmodifiable(proposals),
        routePlansByKey = Map.unmodifiable(routePlansByKey),
        codeIdentityByStructuralOccurrenceKey =
            Map.unmodifiable(codeIdentityByStructuralOccurrenceKey);

  final List<String> errors;
  final int nextIdentitySequence;
  final List<MeasurementCompilerLedgerNode> ledgerNodes;
  final List<MeasurementCompilerLedgerProposal> proposals;
  final Map<String, MeasurementPublicationRoutePlanV1> routePlansByKey;
  final Map<String, CodeIdentityId> codeIdentityByStructuralOccurrenceKey;

  bool get isValid => errors.isEmpty;
}

/// Reconciles source locators and constructs strict pre-carrier route plans.
abstract final class MeasurementPublicationPlanner {
  static MeasurementPublicationPlanningResult plan({
    required Iterable<MeasurementPublicationPlanningInput> publications,
    required RestageMeasurementCompilerOutputV1 priorOutput,
    required MeasurementCompilerPolicyInput? policy,
  }) {
    final orderedPublications = publications.toList()
      ..sort((left, right) => left.selector.key.compareTo(right.selector.key));
    final descriptors = _sourceDescriptors(orderedPublications);
    final reconciliation = _reconcile(
      descriptors: descriptors,
      priorOutput: priorOutput,
    );
    final errors = <String>[...reconciliation.errors];
    final plans = <String, MeasurementPublicationRoutePlanV1>{};
    if (errors.isEmpty && policy != null) {
      for (final publication in orderedPublications) {
        try {
          plans[publication.selector.key] = _routePlan(
            publication,
            reconciliation: reconciliation,
            priorOutput: priorOutput,
            policy: policy,
          );
        } on Object catch (error) {
          errors.add(
            'Could not construct Measurement route plan for '
            '${publication.selector.surface.wireName}/'
            '${publication.selector.slug}: $error',
          );
        }
      }
    }
    return MeasurementPublicationPlanningResult(
      errors: errors,
      nextIdentitySequence: reconciliation.nextIdentitySequence,
      ledgerNodes: reconciliation.nodes,
      proposals: reconciliation.proposals,
      routePlansByKey: errors.isEmpty ? plans : const {},
      codeIdentityByStructuralOccurrenceKey: {
        for (final node in reconciliation.nodes.where((node) => node.active))
          node.structuralOccurrenceKey: node.codeIdentityId,
      },
    );
  }
}

Map<String, _CurrentNodeDescriptor> _sourceDescriptors(
  List<MeasurementPublicationPlanningInput> publications,
) {
  final descriptors = <String, _CurrentNodeDescriptor>{};
  final discoveries = <String, MeasurementSourceDiscoveryResult>{};
  for (final publication in publications) {
    if (publication.entry.publication.payloadKind == SurfacePayloadKind.flow) {
      final locator = _publicationHostLocator(publication.selector);
      descriptors.putIfAbsent(
        locator,
        () => _CurrentNodeDescriptor(
          structuralOccurrenceKey: locator,
          parentStructuralOccurrenceKey: null,
          reconciliationFingerprint: 'compiler.publication-host.flow',
          events: const [],
        ),
      );
    }
    for (final sourceArtifact in publication.sourceArtifacts) {
      final discovery = sourceArtifact.discovery;
      if (discovery.disposition !=
          MeasurementSourceDiscoveryDisposition.accepted) {
        throw ArgumentError(
          'A rejected source discovery cannot enter publication planning',
        );
      }
      final provenance = discovery.sourceProvenance!;
      discoveries.putIfAbsent(
          provenance.resolvedSourceIdentity, () => discovery);
    }
  }
  for (final discovery in discoveries.values) {
    final eventsByNode = <String, List<MeasurementDiscoveredEvent>>{};
    for (final event in discovery.events) {
      eventsByNode
          .putIfAbsent(event.node.structuralOccurrenceKey, () => [])
          .add(event);
    }
    for (final node in discovery.nodes) {
      final events = eventsByNode[node.structuralOccurrenceKey] ?? const [];
      final eventLocators = events
          .map((event) => event.resolvedEvent.resolvedSemanticIdentity)
          .toList()
        ..sort();
      descriptors[node.structuralOccurrenceKey] = _CurrentNodeDescriptor(
        structuralOccurrenceKey: node.structuralOccurrenceKey,
        parentStructuralOccurrenceKey: node.parentStructuralOccurrenceKey,
        reconciliationFingerprint: _privateId(
          prefix: 'fingerprint.v1.',
          domain: 'restage-measurement-reconciliation-evidence-v1',
          value: {
            'events': eventLocators,
            'inlinedCustomWidgets': node.inlinedCustomWidgetIdentities,
            'widget': node.resolvedWidgetIdentity,
          },
        ),
        events: [
          for (final event in events)
            _CurrentEventDescriptor(
              resolvedEventLocator:
                  event.resolvedEvent.resolvedSemanticIdentity,
              sourceEventIdentity: event.resolvedEvent.sourceEventIdentity,
            ),
        ],
      );
    }
  }
  return descriptors;
}

_LedgerReconciliation _reconcile({
  required Map<String, _CurrentNodeDescriptor> descriptors,
  required RestageMeasurementCompilerOutputV1 priorOutput,
}) {
  var nextSequence = priorOutput.nextIdentitySequence;
  final priorByLocator = <String, MeasurementCompilerLedgerNode>{};
  final priorByCode = <String, MeasurementCompilerLedgerNode>{};
  for (final node in priorOutput.ledgerNodes) {
    if (priorByLocator.putIfAbsent(node.structuralOccurrenceKey, () => node) !=
        node) {
      throw const FormatException(
          'Prior Measurement ledger repeats a locator.');
    }
    if (priorByCode.putIfAbsent(node.codeIdentityId.value, () => node) !=
        node) {
      throw const FormatException(
        'Prior Measurement ledger repeats a code identity.',
      );
    }
  }
  final currentKeys = descriptors.keys.toSet();
  final removed = priorOutput.ledgerNodes
      .where((node) =>
          node.active && !currentKeys.contains(node.structuralOccurrenceKey))
      .toList();
  final relocationsByTarget = <String, MeasurementCompilerLedgerRelocation>{};
  for (final relocation in priorOutput.acceptedRelocations) {
    if (relocationsByTarget.putIfAbsent(
          relocation.toStructuralOccurrenceKey,
          () => relocation,
        ) !=
        relocation) {
      throw const FormatException(
        'Prior Measurement ledger repeats a relocation target.',
      );
    }
  }

  final result = <MeasurementCompilerLedgerNode>[];
  final consumedPriorCodes = <String>{};
  final proposals = <MeasurementCompilerLedgerProposal>[];
  final errors = <String>[];

  String sequence() => (nextSequence++).toRadixString(16).padLeft(16, '0');

  MeasurementCompilerLedgerEvent newEvent(
    _CurrentEventDescriptor event,
  ) {
    final id = sequence();
    return MeasurementCompilerLedgerEvent(
      resolvedEventLocator: event.resolvedEventLocator,
      sourceEventIdentity: event.sourceEventIdentity,
      generatedReferenceId: GeneratedReferenceId('reference.auto.$id'),
      lineageId: PointLineageId('lineage.auto.$id'),
      dartSymbol: GeneratedDartSymbol('measurementPoint$id'),
      displayMetadataRef: DisplayMetadataRef('display.auto.$id'),
      active: true,
    );
  }

  MeasurementCompilerLedgerNode updateNode(
    MeasurementCompilerLedgerNode prior,
    _CurrentNodeDescriptor current,
  ) {
    consumedPriorCodes.add(prior.codeIdentityId.value);
    final priorEvents = {
      for (final event in prior.events) event.resolvedEventLocator: event,
    };
    final currentEventLocators =
        current.events.map((event) => event.resolvedEventLocator).toSet();
    final events = <MeasurementCompilerLedgerEvent>[
      for (final event in prior.events)
        if (!currentEventLocators.contains(event.resolvedEventLocator))
          event.copyWith(active: false),
      for (final event in current.events)
        if (priorEvents[event.resolvedEventLocator] case final existing?)
          existing.copyWith(active: true)
        else
          newEvent(event),
    ]..sort(
        (left, right) =>
            left.resolvedEventLocator.compareTo(right.resolvedEventLocator),
      );
    return prior.copyWith(
      structuralOccurrenceKey: current.structuralOccurrenceKey,
      parentStructuralOccurrenceKey: current.parentStructuralOccurrenceKey,
      clearParent: current.parentStructuralOccurrenceKey == null,
      reconciliationFingerprint: current.reconciliationFingerprint,
      active: true,
      events: events,
    );
  }

  final ordered = descriptors.values.toList()
    ..sort(
      (left, right) => left.structuralOccurrenceKey.compareTo(
        right.structuralOccurrenceKey,
      ),
    );
  for (final descriptor in ordered) {
    final exact = priorByLocator[descriptor.structuralOccurrenceKey];
    if (exact != null) {
      result.add(updateNode(exact, descriptor));
      continue;
    }
    final candidates = removed
        .where(
          (node) =>
              node.reconciliationFingerprint ==
                  descriptor.reconciliationFingerprint &&
              !consumedPriorCodes.contains(node.codeIdentityId.value),
        )
        .toList()
      ..sort(
        (left, right) => left.structuralOccurrenceKey.compareTo(
          right.structuralOccurrenceKey,
        ),
      );
    if (candidates.isNotEmpty) {
      final relocation =
          relocationsByTarget[descriptor.structuralOccurrenceKey];
      final selected = candidates
          .where(
            (candidate) =>
                relocation?.fromStructuralOccurrenceKey ==
                    candidate.structuralOccurrenceKey &&
                relocation?.codeIdentityId == candidate.codeIdentityId,
          )
          .firstOrNull;
      if (selected == null) {
        proposals.add(
          MeasurementCompilerLedgerProposal(
            toStructuralOccurrenceKey: descriptor.structuralOccurrenceKey,
            candidatePriorStructuralOccurrenceKeys: candidates
                .map((candidate) => candidate.structuralOccurrenceKey),
          ),
        );
        errors.add(
          'Measurement identity reconciliation requires review for '
          '${descriptor.structuralOccurrenceKey}; candidates='
          '${candidates.map((candidate) => candidate.structuralOccurrenceKey).toList()}.',
        );
        continue;
      }
      result.add(updateNode(selected, descriptor));
      continue;
    }
    final id = sequence();
    result.add(
      MeasurementCompilerLedgerNode(
        structuralOccurrenceKey: descriptor.structuralOccurrenceKey,
        parentStructuralOccurrenceKey: descriptor.parentStructuralOccurrenceKey,
        reconciliationFingerprint: descriptor.reconciliationFingerprint,
        codeIdentityId: CodeIdentityId('code.auto.$id'),
        canonicalNodeTokenId: NodeTokenId('node.auto.$id'),
        active: true,
        events: [for (final event in descriptor.events) newEvent(event)],
      ),
    );
  }
  for (final prior in priorOutput.ledgerNodes) {
    if (consumedPriorCodes.contains(prior.codeIdentityId.value)) continue;
    result.add(
      prior.copyWith(
        active: false,
        events: [
          for (final event in prior.events) event.copyWith(active: false),
        ],
      ),
    );
  }
  result.sort(
    (left, right) =>
        left.codeIdentityId.value.compareTo(right.codeIdentityId.value),
  );
  proposals.sort(
    (left, right) => left.toStructuralOccurrenceKey.compareTo(
      right.toStructuralOccurrenceKey,
    ),
  );
  return _LedgerReconciliation(
    nodes: result,
    proposals: proposals,
    errors: errors,
    nextIdentitySequence: nextSequence,
  );
}

MeasurementPublicationRoutePlanV1 _routePlan(
  MeasurementPublicationPlanningInput input, {
  required _LedgerReconciliation reconciliation,
  required RestageMeasurementCompilerOutputV1 priorOutput,
  required MeasurementCompilerPolicyInput policy,
}) {
  final selector = input.selector;
  final routeArtifacts = _routeArtifacts(input.entry);
  final edgeByArtifactPath = {
    for (var index = 0; index < input.entry.artifacts.length; index++)
      input.entry.artifacts[index].path: routeArtifacts
          .singleWhere(
            (candidate) =>
                candidate.artifactId ==
                measurementArtifactIdForPublicationArtifactV1(
                  selector,
                  input.entry.artifacts[index],
                ),
          )
          .occurrenceEdgeToken,
  };
  final ledgerByLocator = {
    for (final node in reconciliation.nodes.where((node) => node.active))
      node.structuralOccurrenceKey: node,
  };
  final host = input.entry.publication.payloadKind == SurfacePayloadKind.flow
      ? ledgerByLocator[_publicationHostLocator(selector)]
      : null;
  final nodes = <MeasurementPublicationDraftNodeV1>[];
  final bindings = <CodeIdentityBindingV1>[];
  final events = <MeasurementPublicationDraftEventV1>[];
  final routeSeeds = <MeasurementPublicationDraftRouteSeedV1>[];
  if (host != null) {
    final rootEdge = routeArtifacts.singleWhere(
      (artifact) => artifact.parentOccurrenceEdgeToken == null,
    );
    bindings.add(
      CodeIdentityBindingV1(
        codeIdentityId: host.codeIdentityId,
        canonicalNodeTokenId: host.canonicalNodeTokenId,
      ),
    );
    nodes.add(
      MeasurementPublicationDraftNodeV1(
        codeIdentityId: host.codeIdentityId,
        artifactOccurrenceEdgeToken: rootEdge.occurrenceEdgeToken,
      ),
    );
  }

  for (final sourceArtifact in input.sourceArtifacts) {
    final edge = edgeByArtifactPath[sourceArtifact.artifactPath];
    if (edge == null) {
      throw StateError(
        'A Measurement source artifact is absent from publication topology.',
      );
    }
    final discovery = sourceArtifact.discovery;
    for (final discoveredNode in discovery.nodes) {
      final ledger = ledgerByLocator[discoveredNode.structuralOccurrenceKey];
      if (ledger == null) {
        throw StateError('A discovered node has no active ledger binding.');
      }
      final parentLocator = discoveredNode.parentStructuralOccurrenceKey;
      final parentCode = parentLocator == null
          ? host?.codeIdentityId
          : ledgerByLocator[parentLocator]?.codeIdentityId;
      if (parentLocator != null && parentCode == null) {
        throw StateError('A discovered node parent has no ledger binding.');
      }
      bindings.add(
        CodeIdentityBindingV1(
          codeIdentityId: ledger.codeIdentityId,
          canonicalNodeTokenId: ledger.canonicalNodeTokenId,
        ),
      );
      nodes.add(
        MeasurementPublicationDraftNodeV1(
          codeIdentityId: ledger.codeIdentityId,
          artifactOccurrenceEdgeToken: edge,
          parentCodeIdentityId: parentCode,
        ),
      );
      final discoveredEvents = discovery.events.where(
        (event) =>
            event.node.structuralOccurrenceKey ==
            discoveredNode.structuralOccurrenceKey,
      );
      final ledgerEvents = {
        for (final event in ledger.events.where((event) => event.active))
          event.resolvedEventLocator: event,
      };
      for (final discoveredEvent in discoveredEvents) {
        final event = ledgerEvents[
            discoveredEvent.resolvedEvent.resolvedSemanticIdentity];
        if (event == null) {
          throw StateError('A discovered event has no active ledger binding.');
        }
        final treatment = _automaticTreatment(event.sourceEventIdentity);
        events.add(
          MeasurementPublicationDraftEventV1(
            nodeCodeIdentityId: ledger.codeIdentityId,
            sourceEventIdentity: event.sourceEventIdentity,
            lineageId: event.lineageId,
            generatedReferenceId: event.generatedReferenceId,
            dartSymbol: event.dartSymbol,
            displayMetadataRef: event.displayMetadataRef,
            normalizedInteractionKind: treatment.normalizedInteractionKind,
            privacyClass: treatment.privacyClass,
            semanticValueClass: treatment.semanticValueClass,
            collectionClass: treatment.collectionClass,
          ),
        );
        if (treatment.collectionClass !=
            MeasurementCollectionClass.prohibited) {
          routeSeeds.add(
            MeasurementPublicationDraftRouteSeedV1(
              generatedReferenceId: event.generatedReferenceId,
              artifactOccurrenceEdgeToken: edge,
            ),
          );
        }
      }
    }
  }

  final priorPublication = priorOutput.publications
      .where((publication) => publication.selector.key == selector.key)
      .firstOrNull;
  final priorEvents = {
    for (final event in priorPublication?.draft.events ??
        const <MeasurementPublicationDraftEventV1>[])
      event.generatedReferenceId.value: event,
  };
  final currentEvents = {
    for (final event in events) event.generatedReferenceId.value: event,
  };
  final intents = <MeasurementPublicationLineageIntentV1>[];
  for (final event in events) {
    final prior = priorEvents[event.generatedReferenceId.value];
    intents.add(
      MeasurementPublicationLineageIntentV1(
        transitionId: LineageTransitionId(
          _privateId(
            prefix: 'transition.v1.',
            domain: 'restage-measurement-lineage-intent-v1',
            value: {
              'generatedReferenceId': event.generatedReferenceId.value,
              'operation': prior == null ? 'create' : 'continue',
              'surfaceId': measurementSurfaceIdForSelectorV1(selector).value,
            },
          ),
        ),
        operation: prior == null
            ? LineageOperation.create
            : LineageOperation.continueLineage,
        authority: LineageTransitionAuthority.exactToken,
        priorLineageIds: prior == null ? const [] : [prior.lineageId],
        next: [
          MeasurementPublicationCurrentEndpointIntentV1(
            generatedReferenceId: event.generatedReferenceId,
            lineageId: event.lineageId,
          ),
        ],
      ),
    );
  }
  for (final prior in priorEvents.values) {
    if (currentEvents.containsKey(prior.generatedReferenceId.value)) continue;
    intents.add(
      MeasurementPublicationLineageIntentV1(
        transitionId: LineageTransitionId(
          _privateId(
            prefix: 'transition.v1.',
            domain: 'restage-measurement-lineage-intent-v1',
            value: {
              'generatedReferenceId': prior.generatedReferenceId.value,
              'operation': 'retire',
              'surfaceId': measurementSurfaceIdForSelectorV1(selector).value,
            },
          ),
        ),
        operation: LineageOperation.retire,
        authority: LineageTransitionAuthority.exactToken,
        priorLineageIds: [prior.lineageId],
      ),
    );
  }

  return MeasurementPublicationRoutePlanV1(
    surfaceId: measurementSurfaceIdForSelectorV1(selector),
    analyticsSurfaceKey: AnalyticsSurfaceKey(
      '${selector.surface.wireName}.${selector.slug}',
    ),
    deliverySurfaceType: DeliverySurfaceTypeId(selector.surface.wireName),
    minimumMeasurementClient: policy.minimumMeasurementClient,
    completeManifestId: MeasurementManifestId(
      _privateId(
        prefix: 'manifest.v1.',
        domain: 'restage-measurement-target-neutral-manifest-v1',
        value: {
          'artifacts': [
            for (final artifact in routeArtifacts) artifact.toJson()
          ],
          'surfaceId': measurementSurfaceIdForSelectorV1(selector).value,
        },
      ),
    ),
    privacyPolicyRevisionId: policy.privacyPolicyRevisionId,
    collectionBudgetRevisionId: policy.collectionBudgetRevisionId,
    artifacts: routeArtifacts,
    codeIdentityBindings: bindings,
    nodes: nodes,
    events: events,
    routeSeeds: routeSeeds,
    lineageIntents: intents,
  );
}

List<MeasurementPublicationRouteArtifactV1> _routeArtifacts(
  SurfacePublicationManifestEntry entry,
) {
  final selector = MeasurementPublicationSelectorV1.fromPublication(
    entry.publication,
  );
  final root = entry.publication.payloadKind == SurfacePayloadKind.flow
      ? entry.artifacts.singleWhere(
          (artifact) =>
              artifact.role == SurfacePublicationArtifactRole.flowDocument,
        )
      : entry.artifacts.singleWhere(
          (artifact) =>
              artifact.role == SurfacePublicationArtifactRole.screenBlob,
        );
  final edgeById = <String, ArtifactOccurrenceEdgeToken>{};
  for (final artifact in entry.artifacts) {
    edgeById[_artifactSlot(artifact)] = _artifactEdge(selector, artifact);
  }
  return [
    for (final artifact in entry.artifacts)
      MeasurementPublicationRouteArtifactV1(
        artifactId:
            measurementArtifactIdForPublicationArtifactV1(selector, artifact),
        artifactKind: _artifactKind(artifact.role),
        occurrenceEdgeToken: edgeById[_artifactSlot(artifact)]!,
        localManifestId: MeasurementManifestId(
          _privateId(
            prefix: 'manifest.local.v1.',
            domain: 'restage-measurement-local-manifest-v1',
            value: {
              'artifactId': measurementArtifactIdForPublicationArtifactV1(
                selector,
                artifact,
              ).value,
            },
          ),
        ),
        parentOccurrenceEdgeToken: artifact == root
            ? null
            : artifact.role == SurfacePublicationArtifactRole.capabilitySidecar
                ? edgeById['screenBlob:${artifact.id}']
                : edgeById[_artifactSlot(root)],
      ),
  ];
}

/// Derives the target-neutral artifact definition for one publication artifact
/// slot.
ArtifactId measurementArtifactIdForPublicationArtifactV1(
  MeasurementPublicationSelectorV1 selector,
  SurfacePublicationArtifact artifact,
) =>
    ArtifactId(
      _privateId(
        prefix: 'artifact.v1.',
        domain: 'restage-measurement-artifact-definition-v1',
        value: {
          'artifactSlot': _artifactSlot(artifact),
          'publication': selector.toJson(),
        },
      ),
    );

ArtifactOccurrenceEdgeToken _artifactEdge(
  MeasurementPublicationSelectorV1 selector,
  SurfacePublicationArtifact artifact,
) =>
    ArtifactOccurrenceEdgeToken(
      _privateId(
        prefix: 'edge.v1.',
        domain: 'restage-measurement-artifact-occurrence-edge-v1',
        value: {
          'artifactSlot': _artifactSlot(artifact),
          'publication': selector.toJson(),
        },
      ),
    );

String _artifactSlot(SurfacePublicationArtifact artifact) =>
    '${artifact.role.wireName}:${artifact.id ?? ''}';

ArtifactKindId _artifactKind(SurfacePublicationArtifactRole role) =>
    ArtifactKindId(
      switch (role) {
        SurfacePublicationArtifactRole.flowDocument =>
          'publication.flow-document',
        SurfacePublicationArtifactRole.screenBlob => 'rfw.blob',
        SurfacePublicationArtifactRole.capabilitySidecar =>
          'publication.capability-sidecar',
      },
    );

String _publicationHostLocator(MeasurementPublicationSelectorV1 selector) =>
    'compiler-publication-host:${selector.key}';

_AutomaticTreatment _automaticTreatment(SourceEventIdentity event) {
  final normalized = switch (event.value) {
    'onDismissed' ||
    'onClose' ||
    'onCancel' =>
      NormalizedInteractionKind.dismiss,
    'onSelected' || 'onSelectionChanged' => NormalizedInteractionKind.select,
    'onSubmitted' || 'onSubmit' => NormalizedInteractionKind.submit,
    'onChanged' => NormalizedInteractionKind.change,
    _ => NormalizedInteractionKind.activate,
  };
  return _AutomaticTreatment(
    normalizedInteractionKind: normalized,
    privacyClass: MeasurementPrivacyClass.nonSensitive,
    semanticValueClass: SemanticValueClass.activityOnly,
    collectionClass: MeasurementCollectionClass.tier2Coalesced,
  );
}

String _privateId({
  required String prefix,
  required String domain,
  required Object? value,
}) {
  final bytes = <int>[
    ...utf8.encode('$domain\u0000'),
    ...CanonicalJsonCodec.encode(value),
  ];
  return '$prefix${crypto.sha256.convert(bytes)}';
}

final class _CurrentNodeDescriptor {
  const _CurrentNodeDescriptor({
    required this.structuralOccurrenceKey,
    required this.parentStructuralOccurrenceKey,
    required this.reconciliationFingerprint,
    required this.events,
  });

  final String structuralOccurrenceKey;
  final String? parentStructuralOccurrenceKey;
  final String reconciliationFingerprint;
  final List<_CurrentEventDescriptor> events;
}

final class _CurrentEventDescriptor {
  const _CurrentEventDescriptor({
    required this.resolvedEventLocator,
    required this.sourceEventIdentity,
  });

  final String resolvedEventLocator;
  final SourceEventIdentity sourceEventIdentity;
}

final class _LedgerReconciliation {
  const _LedgerReconciliation({
    required this.nodes,
    required this.proposals,
    required this.errors,
    required this.nextIdentitySequence,
  });

  final List<MeasurementCompilerLedgerNode> nodes;
  final List<MeasurementCompilerLedgerProposal> proposals;
  final List<String> errors;
  final int nextIdentitySequence;
}

final class _AutomaticTreatment {
  const _AutomaticTreatment({
    required this.normalizedInteractionKind,
    required this.privacyClass,
    required this.semanticValueClass,
    required this.collectionClass,
  });

  final NormalizedInteractionKind normalizedInteractionKind;
  final MeasurementPrivacyClass privacyClass;
  final SemanticValueClass semanticValueClass;
  final MeasurementCollectionClass collectionClass;
}
