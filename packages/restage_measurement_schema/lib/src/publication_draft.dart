import 'dart:convert';

import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/identifiers.dart';
import 'package:restage_measurement_schema/src/lineage.dart';
import 'package:restage_measurement_schema/src/manifest.dart';
import 'package:restage_measurement_schema/src/publication_route.dart';
import 'package:restage_measurement_schema/src/published_identity.dart';

/// Maximum artifact occurrences admitted to one target-neutral draft.
const int kMaximumMeasurementPublicationDraftArtifactCount = 1024;

/// Maximum canonical nodes admitted to one target-neutral draft.
const int kMaximumMeasurementPublicationDraftNodeCount = 65536;

/// Frozen maximum for delivered runtime carrier routes.
///
/// Canonical graph and node closures have independent, larger bounds. They do
/// not enlarge this runtime delivery budget.
const int kMaximumMeasurementPublicationRuntimeRouteCount = 1024;

/// Maximum runtime source-event slots admitted to one target-neutral draft.
///
/// Every non-prohibited event produces one carrier route, and every event must
/// reconcile to one lineage intent. This preserves the frozen runtime-route
/// accepted set independently of the larger canonical-node closure bound.
const int kMaximumMeasurementPublicationDraftEventCount =
    kMaximumMeasurementPublicationRuntimeRouteCount;

/// Maximum derived runtime carrier routes admitted to one target-neutral draft.
const int kMaximumMeasurementPublicationDraftRouteCount =
    kMaximumMeasurementPublicationRuntimeRouteCount;

/// Maximum runtime lineage intents admitted to one target-neutral draft.
const int kMaximumMeasurementPublicationDraftLineageIntentCount =
    kMaximumMeasurementPublicationRuntimeRouteCount;

/// One target-neutral artifact occurrence in a generated publication draft.
final class MeasurementPublicationDraftArtifactV1 extends CanonicalValue {
  /// Creates one artifact occurrence without final publication identity.
  const MeasurementPublicationDraftArtifactV1({
    required this.artifactId,
    required this.artifactKind,
    required this.contentHash,
    required this.occurrenceEdgeToken,
    required this.localManifestId,
    this.parentOccurrenceEdgeToken,
  });

  /// Decodes one strict target-neutral artifact occurrence.
  factory MeasurementPublicationDraftArtifactV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactId',
        'artifactKind',
        'contentHash',
        'kind',
        'localManifestId',
        'occurrenceEdgeToken',
        'parentOccurrenceEdgeToken',
      },
      requiredKeys: const {
        'artifactId',
        'artifactKind',
        'contentHash',
        'kind',
        'localManifestId',
        'occurrenceEdgeToken',
      },
      path: 'measurementPublicationDraftArtifact',
    );
    if (reader.string('kind') != 'measurementPublicationDraftArtifact') {
      throw const CanonicalFormatException(
        'measurementPublicationDraftArtifact.kind must be '
        '"measurementPublicationDraftArtifact"',
      );
    }
    return _constructDraft(
      'measurementPublicationDraftArtifact',
      () => MeasurementPublicationDraftArtifactV1(
        artifactId: ArtifactId(reader.string('artifactId')),
        artifactKind: ArtifactKindId(reader.string('artifactKind')),
        contentHash: CanonicalDigest(reader.string('contentHash')),
        occurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
          reader.string('occurrenceEdgeToken'),
        ),
        localManifestId: MeasurementManifestId(
          reader.string('localManifestId'),
        ),
        parentOccurrenceEdgeToken: switch (reader.optionalString(
          'parentOccurrenceEdgeToken',
        )) {
          final value? => ArtifactOccurrenceEdgeToken(value),
          null => null,
        },
      ),
    );
  }

  /// Stable artifact definition identity.
  final ArtifactId artifactId;

  /// Registered artifact kind identity.
  final ArtifactKindId artifactKind;

  /// Exact generated artifact content digest.
  final CanonicalDigest contentHash;

  /// Exact occurrence edge in the generated closure.
  final ArtifactOccurrenceEdgeToken occurrenceEdgeToken;

  /// Target-neutral local manifest identity.
  final MeasurementManifestId localManifestId;

  /// Parent occurrence edge, absent only for the closure root.
  final ArtifactOccurrenceEdgeToken? parentOccurrenceEdgeToken;

  @override
  Map<String, Object?> toJson() => {
        'artifactId': artifactId.value,
        'artifactKind': artifactKind.value,
        'contentHash': contentHash.hex,
        'kind': 'measurementPublicationDraftArtifact',
        'localManifestId': localManifestId.value,
        'occurrenceEdgeToken': occurrenceEdgeToken.value,
        if (parentOccurrenceEdgeToken != null)
          'parentOccurrenceEdgeToken': parentOccurrenceEdgeToken!.value,
      };
}

/// Carrier-independent topology for one generated artifact occurrence.
///
/// This is a positive projection: only fields that exist before route-carrier
/// injection are admitted. In particular, final artifact content hashes never
/// enter route derivation.
final class MeasurementPublicationRouteArtifactV1 extends CanonicalValue {
  /// Creates one artifact occurrence for pre-carrier route derivation.
  const MeasurementPublicationRouteArtifactV1({
    required this.artifactId,
    required this.artifactKind,
    required this.occurrenceEdgeToken,
    required this.localManifestId,
    this.parentOccurrenceEdgeToken,
  });

  /// Decodes one strict carrier-independent artifact occurrence.
  factory MeasurementPublicationRouteArtifactV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactId',
        'artifactKind',
        'kind',
        'localManifestId',
        'occurrenceEdgeToken',
        'parentOccurrenceEdgeToken',
      },
      requiredKeys: const {
        'artifactId',
        'artifactKind',
        'kind',
        'localManifestId',
        'occurrenceEdgeToken',
      },
      path: 'measurementPublicationRouteArtifact',
    );
    if (reader.string('kind') != 'measurementPublicationRouteArtifact') {
      throw const CanonicalFormatException(
        'measurementPublicationRouteArtifact.kind must be '
        '"measurementPublicationRouteArtifact"',
      );
    }
    return _constructDraft(
      'measurementPublicationRouteArtifact',
      () => MeasurementPublicationRouteArtifactV1(
        artifactId: ArtifactId(reader.string('artifactId')),
        artifactKind: ArtifactKindId(reader.string('artifactKind')),
        occurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
          reader.string('occurrenceEdgeToken'),
        ),
        localManifestId: MeasurementManifestId(
          reader.string('localManifestId'),
        ),
        parentOccurrenceEdgeToken: switch (reader.optionalString(
          'parentOccurrenceEdgeToken',
        )) {
          final value? => ArtifactOccurrenceEdgeToken(value),
          null => null,
        },
      ),
    );
  }

  /// Stable artifact definition identity.
  final ArtifactId artifactId;

  /// Registered artifact kind identity.
  final ArtifactKindId artifactKind;

  /// Exact occurrence edge in the generated closure.
  final ArtifactOccurrenceEdgeToken occurrenceEdgeToken;

  /// Target-neutral local manifest identity.
  final MeasurementManifestId localManifestId;

  /// Parent occurrence edge, absent only for the closure root.
  final ArtifactOccurrenceEdgeToken? parentOccurrenceEdgeToken;

  @override
  Map<String, Object?> toJson() => {
        'artifactId': artifactId.value,
        'artifactKind': artifactKind.value,
        'kind': 'measurementPublicationRouteArtifact',
        'localManifestId': localManifestId.value,
        'occurrenceEdgeToken': occurrenceEdgeToken.value,
        if (parentOccurrenceEdgeToken != null)
          'parentOccurrenceEdgeToken': parentOccurrenceEdgeToken!.value,
      };
}

/// One target-neutral canonical node in a generated publication draft.
final class MeasurementPublicationDraftNodeV1 extends CanonicalValue {
  /// Creates one canonical node closure entry.
  const MeasurementPublicationDraftNodeV1({
    required this.codeIdentityId,
    required this.artifactOccurrenceEdgeToken,
    this.parentCodeIdentityId,
  });

  /// Decodes one strict target-neutral canonical node entry.
  factory MeasurementPublicationDraftNodeV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactOccurrenceEdgeToken',
        'codeIdentityId',
        'kind',
        'parentCodeIdentityId',
      },
      requiredKeys: const {
        'artifactOccurrenceEdgeToken',
        'codeIdentityId',
        'kind',
      },
      path: 'measurementPublicationDraftNode',
    );
    if (reader.string('kind') != 'measurementPublicationDraftNode') {
      throw const CanonicalFormatException(
        'measurementPublicationDraftNode.kind must be '
        '"measurementPublicationDraftNode"',
      );
    }
    return _constructDraft(
      'measurementPublicationDraftNode',
      () => MeasurementPublicationDraftNodeV1(
        codeIdentityId: CodeIdentityId(reader.string('codeIdentityId')),
        artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
          reader.string('artifactOccurrenceEdgeToken'),
        ),
        parentCodeIdentityId: switch (reader.optionalString(
          'parentCodeIdentityId',
        )) {
          final value? => CodeIdentityId(value),
          null => null,
        },
      ),
    );
  }

  /// Stable compiler code identity.
  final CodeIdentityId codeIdentityId;

  /// Exact artifact occurrence containing this node.
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;

  /// Direct parent canonical node, absent only for the canonical root.
  final CodeIdentityId? parentCodeIdentityId;

  @override
  Map<String, Object?> toJson() => {
        'artifactOccurrenceEdgeToken': artifactOccurrenceEdgeToken.value,
        'codeIdentityId': codeIdentityId.value,
        'kind': 'measurementPublicationDraftNode',
        if (parentCodeIdentityId != null)
          'parentCodeIdentityId': parentCodeIdentityId!.value,
      };
}

/// One compiler-resolved source-event slot without target or revision identity.
final class MeasurementPublicationDraftEventV1 extends CanonicalValue {
  /// Creates one strict event slot in a target-neutral draft.
  const MeasurementPublicationDraftEventV1({
    required this.nodeCodeIdentityId,
    required this.sourceEventIdentity,
    required this.lineageId,
    required this.generatedReferenceId,
    required this.dartSymbol,
    required this.displayMetadataRef,
    required this.normalizedInteractionKind,
    required this.privacyClass,
    required this.semanticValueClass,
    required this.collectionClass,
  });

  /// Decodes one closed compiler event representation.
  factory MeasurementPublicationDraftEventV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'collectionClass',
        'dartSymbol',
        'displayMetadataRef',
        'generatedReferenceId',
        'kind',
        'lineageId',
        'nodeCodeIdentityId',
        'normalizedInteractionKind',
        'privacyClass',
        'semanticValueClass',
        'sourceEventIdentity',
      },
      requiredKeys: const {
        'collectionClass',
        'dartSymbol',
        'displayMetadataRef',
        'generatedReferenceId',
        'kind',
        'lineageId',
        'nodeCodeIdentityId',
        'normalizedInteractionKind',
        'privacyClass',
        'semanticValueClass',
        'sourceEventIdentity',
      },
      path: 'measurementPublicationDraftEvent',
    );
    if (reader.string('kind') != 'measurementPublicationDraftEvent') {
      throw const CanonicalFormatException(
        'measurementPublicationDraftEvent.kind must be '
        '"measurementPublicationDraftEvent"',
      );
    }
    return _constructDraft(
      'measurementPublicationDraftEvent',
      () => MeasurementPublicationDraftEventV1(
        nodeCodeIdentityId: CodeIdentityId(reader.string('nodeCodeIdentityId')),
        sourceEventIdentity: SourceEventIdentity(
          reader.string('sourceEventIdentity'),
        ),
        lineageId: PointLineageId(reader.string('lineageId')),
        generatedReferenceId: GeneratedReferenceId(
          reader.string('generatedReferenceId'),
        ),
        dartSymbol: GeneratedDartSymbol(reader.string('dartSymbol')),
        displayMetadataRef: DisplayMetadataRef(
          reader.string('displayMetadataRef'),
        ),
        normalizedInteractionKind: _normalizedInteractionKindFromWire(
          reader.string('normalizedInteractionKind'),
        ),
        privacyClass: _privacyClassFromWire(reader.string('privacyClass')),
        semanticValueClass: _semanticValueClassFromWire(
          reader.string('semanticValueClass'),
        ),
        collectionClass: _collectionClassFromWire(
          reader.string('collectionClass'),
        ),
      ),
    );
  }

  /// Canonical node that owns the event slot.
  final CodeIdentityId nodeCodeIdentityId;

  /// Exact compiler-resolved event selector.
  final SourceEventIdentity sourceEventIdentity;

  /// Current reviewed continuity identity.
  final PointLineageId lineageId;

  /// Generated source reference for this exact event occurrence.
  final GeneratedReferenceId generatedReferenceId;

  /// Generated source symbol emitted for the occurrence.
  final GeneratedDartSymbol dartSymbol;

  /// Non-identity display metadata reference.
  final DisplayMetadataRef displayMetadataRef;

  /// Catalog-normalized interaction semantics.
  final NormalizedInteractionKind normalizedInteractionKind;

  /// Compiler-resolved privacy treatment.
  final MeasurementPrivacyClass privacyClass;

  /// Compiler-resolved semantic-value treatment.
  final SemanticValueClass semanticValueClass;

  /// Compiler-resolved collection treatment.
  final MeasurementCollectionClass collectionClass;

  @override
  Map<String, Object?> toJson() => {
        'collectionClass': collectionClass.wireName,
        'dartSymbol': dartSymbol.value,
        'displayMetadataRef': displayMetadataRef.value,
        'generatedReferenceId': generatedReferenceId.value,
        'kind': 'measurementPublicationDraftEvent',
        'lineageId': lineageId.value,
        'nodeCodeIdentityId': nodeCodeIdentityId.value,
        'normalizedInteractionKind': normalizedInteractionKind.wireName,
        'privacyClass': privacyClass.wireName,
        'semanticValueClass': semanticValueClass.wireName,
        'sourceEventIdentity': sourceEventIdentity.value,
      };
}

/// One target-neutral request to derive a full private route carrier.
final class MeasurementPublicationDraftRouteSeedV1 extends CanonicalValue {
  /// Creates one route derivation seed.
  const MeasurementPublicationDraftRouteSeedV1({
    required this.generatedReferenceId,
    required this.artifactOccurrenceEdgeToken,
  });

  /// Decodes one strict route derivation seed.
  factory MeasurementPublicationDraftRouteSeedV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactOccurrenceEdgeToken',
        'generatedReferenceId',
        'kind',
      },
      requiredKeys: const {
        'artifactOccurrenceEdgeToken',
        'generatedReferenceId',
        'kind',
      },
      path: 'measurementPublicationDraftRouteSeed',
    );
    if (reader.string('kind') != 'measurementPublicationDraftRouteSeed') {
      throw const CanonicalFormatException(
        'measurementPublicationDraftRouteSeed.kind must be '
        '"measurementPublicationDraftRouteSeed"',
      );
    }
    return _constructDraft(
      'measurementPublicationDraftRouteSeed',
      () => MeasurementPublicationDraftRouteSeedV1(
        generatedReferenceId: GeneratedReferenceId(
          reader.string('generatedReferenceId'),
        ),
        artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
          reader.string('artifactOccurrenceEdgeToken'),
        ),
      ),
    );
  }

  /// Generated source reference selected by the carrier.
  final GeneratedReferenceId generatedReferenceId;

  /// Exact mounted artifact occurrence encoded into the carrier.
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;

  @override
  Map<String, Object?> toJson() => {
        'artifactOccurrenceEdgeToken': artifactOccurrenceEdgeToken.value,
        'generatedReferenceId': generatedReferenceId.value,
        'kind': 'measurementPublicationDraftRouteSeed',
      };
}

/// One derived full private route carrier retained in the generated draft.
final class MeasurementPublicationDraftRouteV1 extends CanonicalValue {
  /// Creates one fully derived route and verifies every coupled value.
  MeasurementPublicationDraftRouteV1({
    required this.generatedReferenceId,
    required this.artifactOccurrenceEdgeToken,
    required this.carrier,
    required this.opaqueRouteToken,
  }) {
    final parsed = MeasurementPublicationRouteCarrierV1.parse(carrier);
    if (parsed.artifactOccurrenceEdgeToken != artifactOccurrenceEdgeToken ||
        OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(carrier) !=
            opaqueRouteToken) {
      throw ArgumentError(
        'A publication draft route must retain the exact carrier edge and '
        'full-carrier fingerprint',
      );
    }
  }

  /// Decodes one strict derived route.
  factory MeasurementPublicationDraftRouteV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactOccurrenceEdgeToken',
        'carrier',
        'generatedReferenceId',
        'kind',
        'opaqueRouteToken',
      },
      requiredKeys: const {
        'artifactOccurrenceEdgeToken',
        'carrier',
        'generatedReferenceId',
        'kind',
        'opaqueRouteToken',
      },
      path: 'measurementPublicationDraftRoute',
    );
    if (reader.string('kind') != 'measurementPublicationDraftRoute') {
      throw const CanonicalFormatException(
        'measurementPublicationDraftRoute.kind must be '
        '"measurementPublicationDraftRoute"',
      );
    }
    return _constructDraft(
      'measurementPublicationDraftRoute',
      () => MeasurementPublicationDraftRouteV1(
        generatedReferenceId: GeneratedReferenceId(
          reader.string('generatedReferenceId'),
        ),
        artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
          reader.string('artifactOccurrenceEdgeToken'),
        ),
        carrier: reader.string('carrier'),
        opaqueRouteToken: OpaqueMeasurementRouteTokenV1.fromJson(
          reader.object('opaqueRouteToken'),
        ),
      ),
    );
  }

  /// Generated reference selected by the carrier.
  final GeneratedReferenceId generatedReferenceId;

  /// Exact mounted edge encoded into [carrier].
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;

  /// Strict full carrier spelling inserted into generated artifact data.
  final String carrier;

  /// Domain-separated fingerprint of the complete carrier spelling.
  final OpaqueMeasurementRouteTokenV1 opaqueRouteToken;

  @override
  Map<String, Object?> toJson() => {
        'artifactOccurrenceEdgeToken': artifactOccurrenceEdgeToken.value,
        'carrier': carrier,
        'generatedReferenceId': generatedReferenceId.value,
        'kind': 'measurementPublicationDraftRoute',
        'opaqueRouteToken': opaqueRouteToken.toJson(),
      };
}

/// One target-neutral current endpoint claim in a lineage intent.
final class MeasurementPublicationCurrentEndpointIntentV1
    extends CanonicalValue {
  /// Creates one claim against an exact generated reference.
  const MeasurementPublicationCurrentEndpointIntentV1({
    required this.generatedReferenceId,
    required this.lineageId,
  });

  /// Decodes one closed current endpoint claim.
  factory MeasurementPublicationCurrentEndpointIntentV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'generatedReferenceId', 'kind', 'lineageId'},
      requiredKeys: const {'generatedReferenceId', 'kind', 'lineageId'},
      path: 'measurementPublicationCurrentEndpointIntent',
    );
    if (reader.string('kind') !=
        'measurementPublicationCurrentEndpointIntent') {
      throw const CanonicalFormatException(
        'measurementPublicationCurrentEndpointIntent.kind must be '
        '"measurementPublicationCurrentEndpointIntent"',
      );
    }
    return _constructDraft(
      'measurementPublicationCurrentEndpointIntent',
      () => MeasurementPublicationCurrentEndpointIntentV1(
        generatedReferenceId: GeneratedReferenceId(
          reader.string('generatedReferenceId'),
        ),
        lineageId: PointLineageId(reader.string('lineageId')),
      ),
    );
  }

  /// Exact generated source reference selected as a next endpoint.
  final GeneratedReferenceId generatedReferenceId;

  /// Lineage that the selected generated occurrence must carry.
  final PointLineageId lineageId;

  @override
  Map<String, Object?> toJson() => {
        'generatedReferenceId': generatedReferenceId.value,
        'kind': 'measurementPublicationCurrentEndpointIntent',
        'lineageId': lineageId.value,
      };
}

/// One complete target-neutral lineage operation intent.
///
/// Prior values carry only stable lineage IDs. Exact prior occurrence IDs are
/// supplied by the finalization input and never occur in draft bytes.
final class MeasurementPublicationLineageIntentV1 extends CanonicalValue {
  /// Creates and validates one closed lineage operation intent.
  MeasurementPublicationLineageIntentV1({
    required this.transitionId,
    required this.operation,
    required this.authority,
    List<PointLineageId> priorLineageIds = const [],
    List<MeasurementPublicationCurrentEndpointIntentV1> next = const [],
  })  : priorLineageIds = _sortedUniqueLineageIds(priorLineageIds),
        next = _sortedUniqueCurrentEndpointIntents(next) {
    _validateIntentShape();
  }

  /// Decodes one strict lineage intent.
  factory MeasurementPublicationLineageIntentV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'authority',
        'kind',
        'next',
        'operation',
        'priorLineageIds',
        'transitionId',
      },
      requiredKeys: const {
        'authority',
        'kind',
        'next',
        'operation',
        'priorLineageIds',
        'transitionId',
      },
      path: 'measurementPublicationLineageIntent',
    );
    if (reader.string('kind') != 'measurementPublicationLineageIntent') {
      throw const CanonicalFormatException(
        'measurementPublicationLineageIntent.kind must be '
        '"measurementPublicationLineageIntent"',
      );
    }
    return _constructDraft(
      'measurementPublicationLineageIntent',
      () => MeasurementPublicationLineageIntentV1(
        transitionId: LineageTransitionId(reader.string('transitionId')),
        operation: _lineageOperationFromWire(reader.string('operation')),
        authority: _lineageAuthorityFromWire(reader.string('authority')),
        priorLineageIds: [
          for (final value in reader.list('priorLineageIds'))
            PointLineageId(requireCanonicalString(value, 'priorLineageIds[]')),
        ],
        next: [
          for (final value in reader.list('next'))
            MeasurementPublicationCurrentEndpointIntentV1.fromJson(
              requireCanonicalObject(value, 'next[]'),
            ),
        ],
      ),
    );
  }

  /// Stable transition identity.
  final LineageTransitionId transitionId;

  /// Closed legal operation shape.
  final LineageOperation operation;

  /// Authority under which the operation was admitted.
  final LineageTransitionAuthority authority;

  /// Exact stable prior lineage set, without prior occurrence IDs.
  final List<PointLineageId> priorLineageIds;

  /// Exact current endpoint claims.
  final List<MeasurementPublicationCurrentEndpointIntentV1> next;

  @override
  Map<String, Object?> toJson() => {
        'authority': authority.wireName,
        'kind': 'measurementPublicationLineageIntent',
        'next': [for (final endpoint in next) endpoint.toJson()],
        'operation': operation.wireName,
        'priorLineageIds': [
          for (final lineageId in priorLineageIds) lineageId.value,
        ],
        'transitionId': transitionId.value,
      };

  void _validateIntentShape() {
    switch (operation) {
      case LineageOperation.continueLineage:
        if (priorLineageIds.length != 1 ||
            next.length != 1 ||
            priorLineageIds.single != next.single.lineageId) {
          throw ArgumentError(
            'Continue must be exactly 1→1 and preserve lineage',
          );
        }
      case LineageOperation.create:
        if (priorLineageIds.isNotEmpty || next.length != 1) {
          throw ArgumentError('Create must be exactly 0→1');
        }
      case LineageOperation.retire:
        if (priorLineageIds.length != 1 || next.isNotEmpty) {
          throw ArgumentError('Retire must be exactly 1→0');
        }
      case LineageOperation.split:
        if (priorLineageIds.length != 1 || next.length < 2) {
          throw ArgumentError(
            'Split must be exactly 1→N where N is at least 2',
          );
        }
        if (next.map((endpoint) => endpoint.lineageId.value).toSet().length !=
            next.length) {
          throw ArgumentError(
            'Every split successor must have a unique lineage',
          );
        }
      case LineageOperation.merge:
        if (priorLineageIds.length < 2 || next.length != 1) {
          throw ArgumentError(
            'Merge must be exactly N→1 where N is at least 2',
          );
        }
        if (authority != LineageTransitionAuthority.explicit) {
          throw ArgumentError('Merge requires explicit authority');
        }
    }
  }
}

/// Strict carrier-independent projection used to derive publication routes.
///
/// The wire shape is an explicit positive list of pre-carrier identity,
/// topology, event, lineage, and route-seed fields. Final artifact bytes,
/// content hashes, carriers, and every other post-injection value are absent by
/// construction. Adding a field to the final publication draft therefore
/// cannot silently add it to this route preimage.
final class MeasurementPublicationRoutePlanV1 extends CanonicalDocument {
  /// Creates and closes one pre-carrier route plan.
  MeasurementPublicationRoutePlanV1({
    required this.surfaceId,
    required this.analyticsSurfaceKey,
    required this.deliverySurfaceType,
    required this.minimumMeasurementClient,
    required this.completeManifestId,
    required this.privacyPolicyRevisionId,
    required this.collectionBudgetRevisionId,
    required List<MeasurementPublicationRouteArtifactV1> artifacts,
    required List<CodeIdentityBindingV1> codeIdentityBindings,
    required List<MeasurementPublicationDraftNodeV1> nodes,
    required List<MeasurementPublicationDraftEventV1> events,
    required List<MeasurementPublicationDraftRouteSeedV1> routeSeeds,
    required List<MeasurementPublicationLineageIntentV1> lineageIntents,
  })  : artifacts = _sortedUniqueRouteArtifacts(artifacts),
        codeIdentityBindings = _sortedUniqueCodeIdentityBindings(
          codeIdentityBindings,
        ),
        nodes = _sortedUniqueNodes(nodes),
        events = _sortedUniqueEvents(events),
        routeSeeds = _sortedUniqueRouteSeeds(routeSeeds),
        lineageIntents = _sortedUniqueLineageIntents(lineageIntents) {
    if (minimumMeasurementClient <= 0 ||
        minimumMeasurementClient > kMaximumPortableJsonInteger) {
      throw ArgumentError.value(
        minimumMeasurementClient,
        'minimumMeasurementClient',
        'Expected a positive portable client capability revision',
      );
    }
    _validateStructuralClosure();
    routes = _deriveRoutes(routeSeeds, routeDraftClosureDigest);
    _validateRouteClosure();
  }

  /// Decodes byte-exact canonical route-plan bytes.
  factory MeasurementPublicationRoutePlanV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementPublicationRoutePlanV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'measurementPublicationRouteDraftClosure',
      );

  /// Decodes one closed carrier-independent route plan.
  factory MeasurementPublicationRoutePlanV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'analyticsSurfaceKey',
        'artifacts',
        'codeIdentityBindings',
        'collectionBudgetRevisionId',
        'completeManifestId',
        'deliverySurfaceType',
        'events',
        'kind',
        'lineageIntents',
        'minimumMeasurementClient',
        'nodes',
        'privacyPolicyRevisionId',
        'routeSeeds',
        'schemaVersion',
        'surfaceId',
      },
      requiredKeys: const {
        'analyticsSurfaceKey',
        'artifacts',
        'codeIdentityBindings',
        'collectionBudgetRevisionId',
        'completeManifestId',
        'deliverySurfaceType',
        'events',
        'kind',
        'lineageIntents',
        'minimumMeasurementClient',
        'nodes',
        'privacyPolicyRevisionId',
        'routeSeeds',
        'schemaVersion',
        'surfaceId',
      },
      path: 'measurementPublicationRouteDraftClosure',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'measurementPublicationRouteDraftClosure',
    );
    final artifacts = reader.list('artifacts');
    final codeIdentityBindings = reader.list('codeIdentityBindings');
    final nodes = reader.list('nodes');
    final events = reader.list('events');
    final routeSeeds = reader.list('routeSeeds');
    final lineageIntents = reader.list('lineageIntents');
    _validateRawRoutePlanListBounds(
      artifacts: artifacts,
      codeIdentityBindings: codeIdentityBindings,
      nodes: nodes,
      events: events,
      routeSeeds: routeSeeds,
      lineageIntents: lineageIntents,
    );
    return _constructDraft(
      'measurementPublicationRouteDraftClosure',
      () => MeasurementPublicationRoutePlanV1(
        surfaceId: SurfaceId(reader.string('surfaceId')),
        analyticsSurfaceKey: AnalyticsSurfaceKey(
          reader.string('analyticsSurfaceKey'),
        ),
        deliverySurfaceType: DeliverySurfaceTypeId(
          reader.string('deliverySurfaceType'),
        ),
        minimumMeasurementClient: reader.integer('minimumMeasurementClient'),
        completeManifestId: MeasurementManifestId(
          reader.string('completeManifestId'),
        ),
        privacyPolicyRevisionId: AuthorityRevisionId(
          reader.string('privacyPolicyRevisionId'),
        ),
        collectionBudgetRevisionId: AuthorityRevisionId(
          reader.string('collectionBudgetRevisionId'),
        ),
        artifacts: [
          for (final value in artifacts)
            MeasurementPublicationRouteArtifactV1.fromJson(
              requireCanonicalObject(value, 'artifacts[]'),
            ),
        ],
        codeIdentityBindings: [
          for (final value in codeIdentityBindings)
            CodeIdentityBindingV1.fromJson(
              requireCanonicalObject(value, 'codeIdentityBindings[]'),
            ),
        ],
        nodes: [
          for (final value in nodes)
            MeasurementPublicationDraftNodeV1.fromJson(
              requireCanonicalObject(value, 'nodes[]'),
            ),
        ],
        events: [
          for (final value in events)
            MeasurementPublicationDraftEventV1.fromJson(
              requireCanonicalObject(value, 'events[]'),
            ),
        ],
        routeSeeds: [
          for (final value in routeSeeds)
            MeasurementPublicationDraftRouteSeedV1.fromJson(
              requireCanonicalObject(value, 'routeSeeds[]'),
            ),
        ],
        lineageIntents: [
          for (final value in lineageIntents)
            MeasurementPublicationLineageIntentV1.fromJson(
              requireCanonicalObject(value, 'lineageIntents[]'),
            ),
        ],
      ),
    );
  }

  /// Stable compiler-ledger surface identity; not a final target identity.
  final SurfaceId surfaceId;

  /// Analytics key sealed into a future published revision.
  final AnalyticsSurfaceKey analyticsSurfaceKey;

  /// Registered delivery-surface type identity.
  final DeliverySurfaceTypeId deliverySurfaceType;

  /// Minimum Measurement client capability revision.
  final int minimumMeasurementClient;

  /// Target-neutral complete manifest identity.
  final MeasurementManifestId completeManifestId;

  /// Immutable privacy policy revision.
  final AuthorityRevisionId privacyPolicyRevisionId;

  /// Immutable collection budget revision.
  final AuthorityRevisionId collectionBudgetRevisionId;

  /// Complete carrier-independent artifact occurrence topology.
  final List<MeasurementPublicationRouteArtifactV1> artifacts;

  /// Target-neutral projection of the code identity ledger.
  final List<CodeIdentityBindingV1> codeIdentityBindings;

  /// Complete canonical node ancestry closure.
  final List<MeasurementPublicationDraftNodeV1> nodes;

  /// Complete compiler-resolved source-event closure.
  final List<MeasurementPublicationDraftEventV1> events;

  /// Strict carrier derivation seeds.
  final List<MeasurementPublicationDraftRouteSeedV1> routeSeeds;

  /// Complete target-neutral lineage operation set.
  final List<MeasurementPublicationLineageIntentV1> lineageIntents;

  /// Fully derived carrier spellings and fingerprints.
  late final List<MeasurementPublicationDraftRouteV1> routes;

  /// Digest of this complete carrier-independent route preimage.
  CanonicalDigest get routeDraftClosureDigest => canonicalDigest;

  @override
  CanonicalHashDomain get hashDomain =>
      CanonicalHashDomain.measurementPublicationRouteDraftClosure;

  @override
  Map<String, Object?> toJson() => {
        'analyticsSurfaceKey': analyticsSurfaceKey.value,
        'artifacts': [for (final artifact in artifacts) artifact.toJson()],
        'codeIdentityBindings': [
          for (final binding in codeIdentityBindings) binding.toJson(),
        ],
        'collectionBudgetRevisionId': collectionBudgetRevisionId.value,
        'completeManifestId': completeManifestId.value,
        'deliverySurfaceType': deliverySurfaceType.value,
        'events': [for (final event in events) event.toJson()],
        'kind': 'measurementPublicationRouteDraftClosure',
        'lineageIntents': [
          for (final intent in lineageIntents) intent.toJson(),
        ],
        'minimumMeasurementClient': minimumMeasurementClient,
        'nodes': [for (final node in nodes) node.toJson()],
        'privacyPolicyRevisionId': privacyPolicyRevisionId.value,
        'routeSeeds': [for (final routeSeed in routeSeeds) routeSeed.toJson()],
        'schemaVersion': kMeasurementSchemaVersion,
        'surfaceId': surfaceId.value,
      };

  void _validateStructuralClosure() {
    if (artifacts.isEmpty ||
        artifacts.length > kMaximumMeasurementPublicationDraftArtifactCount ||
        codeIdentityBindings.isEmpty ||
        codeIdentityBindings.length >
            kMaximumMeasurementPublicationDraftNodeCount ||
        nodes.isEmpty ||
        nodes.length > kMaximumMeasurementPublicationDraftNodeCount ||
        events.length > kMaximumMeasurementPublicationDraftEventCount ||
        lineageIntents.length >
            kMaximumMeasurementPublicationDraftLineageIntentCount) {
      throw ArgumentError('The publication route plan exceeds one bound');
    }

    final artifactsByEdge = {
      for (final artifact in artifacts)
        artifact.occurrenceEdgeToken.value: artifact,
    };
    final roots = artifacts
        .where((artifact) => artifact.parentOccurrenceEdgeToken == null)
        .toList(growable: false);
    if (roots.length != 1) {
      throw ArgumentError(
        'The publication route plan requires exactly one root artifact',
      );
    }
    final definitionsByArtifactId =
        <String, MeasurementPublicationRouteArtifactV1>{};
    for (final artifact in artifacts) {
      final existing = definitionsByArtifactId[artifact.artifactId.value];
      if (existing != null &&
          (existing.artifactKind != artifact.artifactKind ||
              existing.localManifestId != artifact.localManifestId)) {
        throw ArgumentError(
          'Repeated route artifact occurrences must preserve one exact '
          'definition and local manifest provenance',
        );
      }
      definitionsByArtifactId[artifact.artifactId.value] = artifact;
      final parent = artifact.parentOccurrenceEdgeToken;
      if (parent != null &&
          (!artifactsByEdge.containsKey(parent.value) ||
              parent == artifact.occurrenceEdgeToken)) {
        throw ArgumentError(
          'Every route artifact parent must name another edge',
        );
      }
    }

    final bindingsByCode = {
      for (final binding in codeIdentityBindings)
        binding.codeIdentityId.value: binding,
    };
    final nodesByCode = {
      for (final node in nodes) node.codeIdentityId.value: node,
    };
    _requireExactStringKeys(
      expected: bindingsByCode.keys,
      actual: nodesByCode.keys,
      label: 'route-plan nodes and code identity bindings',
    );
    final nodeRoots = nodes
        .where((node) => node.parentCodeIdentityId == null)
        .toList(growable: false);
    if (nodeRoots.length != 1) {
      throw ArgumentError(
        'The publication route plan requires exactly one node root',
      );
    }
    for (final node in nodes) {
      if (!artifactsByEdge.containsKey(
            node.artifactOccurrenceEdgeToken.value,
          ) ||
          (node.parentCodeIdentityId != null &&
              !nodesByCode.containsKey(node.parentCodeIdentityId!.value))) {
        throw ArgumentError(
          'Every route-plan node must close its artifact and parent',
        );
      }
    }

    final eventSlots = <String>{};
    final eventReferences = <String>{};
    final eventLineages = <String>{};
    for (final event in events) {
      if (!nodesByCode.containsKey(event.nodeCodeIdentityId.value)) {
        throw ArgumentError(
          'Every route-plan event must join one canonical node',
        );
      }
      if (!eventSlots.add(
        '${event.nodeCodeIdentityId.value}\u0000'
        '${event.sourceEventIdentity.value}',
      )) {
        throw ArgumentError('Each route-plan node may claim one event once');
      }
      if (!eventReferences.add(event.generatedReferenceId.value) ||
          !eventLineages.add(event.lineageId.value)) {
        throw ArgumentError(
          'Route-plan event references and current lineages must be unique',
        );
      }
    }

    _validateAcyclicParentClosure(
      roots.single.occurrenceEdgeToken.value,
      artifacts.map(
        (artifact) => MapEntry(
          artifact.occurrenceEdgeToken.value,
          artifact.parentOccurrenceEdgeToken?.value,
        ),
      ),
      'artifact occurrence edges',
    );
    _validateAcyclicParentClosure(
      nodeRoots.single.codeIdentityId.value,
      nodes.map(
        (node) => MapEntry(
          node.codeIdentityId.value,
          node.parentCodeIdentityId?.value,
        ),
      ),
      'canonical nodes',
    );
  }

  void _validateRouteClosure() {
    if (routes.length > kMaximumMeasurementPublicationDraftRouteCount) {
      throw ArgumentError('A route plan exceeds its bounded route closure');
    }
    final eventsByReference = {
      for (final event in events) event.generatedReferenceId.value: event,
    };
    final nodesByCode = {
      for (final node in nodes) node.codeIdentityId.value: node,
    };
    final requiredRouteReferences = <String>{
      for (final event in events)
        if (event.collectionClass != MeasurementCollectionClass.prohibited)
          event.generatedReferenceId.value,
    };
    final actualRouteReferences = <String>{};
    final fullFingerprints = <String>{};
    final localTokensByEdge = <String, Set<String>>{};
    for (final route in routes) {
      final event = eventsByReference[route.generatedReferenceId.value];
      if (event == null ||
          event.collectionClass == MeasurementCollectionClass.prohibited ||
          nodesByCode[event.nodeCodeIdentityId.value]!
                  .artifactOccurrenceEdgeToken !=
              route.artifactOccurrenceEdgeToken) {
        throw ArgumentError(
          'Every route-plan route must close one admitted event edge',
        );
      }
      if (!actualRouteReferences.add(route.generatedReferenceId.value) ||
          !fullFingerprints.add(route.opaqueRouteToken.fingerprint.hex)) {
        throw ArgumentError('Full route-plan carriers must be unique');
      }
      final parsed = MeasurementPublicationRouteCarrierV1.parse(route.carrier);
      final locals = localTokensByEdge.putIfAbsent(
        parsed.artifactOccurrenceEdgeToken.value,
        () => <String>{},
      );
      final local = base64Url.encode(parsed.localToken).replaceAll('=', '');
      if (!locals.add(local)) {
        throw ArgumentError('Local route tokens must be unique per edge');
      }
    }
    _requireExactStringKeys(
      expected: requiredRouteReferences,
      actual: actualRouteReferences,
      label: 'admitted route-plan events and full route carriers',
    );

    final nextReferences = <String>{};
    final priorLineages = <String>{};
    for (final intent in lineageIntents) {
      for (final priorLineageId in intent.priorLineageIds) {
        if (!priorLineages.add(priorLineageId.value)) {
          throw ArgumentError(
            'A prior route-plan lineage may appear in one intent only',
          );
        }
      }
      for (final next in intent.next) {
        final event = eventsByReference[next.generatedReferenceId.value];
        if (event == null || event.lineageId != next.lineageId) {
          throw ArgumentError(
            'Every current route-plan endpoint must exactly join one event',
          );
        }
        if (!nextReferences.add(next.generatedReferenceId.value)) {
          throw ArgumentError(
            'A current route-plan event may appear in one intent only',
          );
        }
      }
    }
    _requireExactStringKeys(
      expected: eventsByReference.keys,
      actual: nextReferences,
      label: 'route-plan events and lineage intent next endpoints',
    );
  }
}

/// Strict target-neutral Measurement publication candidate input.
///
/// This final document carries exact post-carrier artifact hashes. Its routes
/// must come from one already-closed [MeasurementPublicationRoutePlanV1]. It
/// deliberately carries no target, final revision, final row, ordinal,
/// external authority reference, binding, or prior occurrence ID.
final class MeasurementPublicationDraftV1 extends CanonicalDocument {
  /// Creates a complete final target-neutral generated publication draft.
  MeasurementPublicationDraftV1({
    required this.routePlan,
    required List<MeasurementPublicationDraftArtifactV1> artifacts,
  }) : artifacts = _sortedUniqueArtifacts(artifacts) {
    _validateFinalArtifactClosure();
    routes = routePlan.routes;
  }

  /// Decodes byte-exact canonical target-neutral draft bytes.
  factory MeasurementPublicationDraftV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        MeasurementPublicationDraftV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementPublicationDraft',
      );

  /// Decodes a closed draft and rejects any non-derived route spelling.
  factory MeasurementPublicationDraftV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'analyticsSurfaceKey',
        'artifacts',
        'codeIdentityBindings',
        'collectionBudgetRevisionId',
        'completeManifestId',
        'deliverySurfaceType',
        'events',
        'kind',
        'lineageIntents',
        'minimumMeasurementClient',
        'nodes',
        'privacyPolicyRevisionId',
        'routes',
        'schemaVersion',
        'surfaceId',
      },
      requiredKeys: const {
        'analyticsSurfaceKey',
        'artifacts',
        'codeIdentityBindings',
        'collectionBudgetRevisionId',
        'completeManifestId',
        'deliverySurfaceType',
        'events',
        'kind',
        'lineageIntents',
        'minimumMeasurementClient',
        'nodes',
        'privacyPolicyRevisionId',
        'routes',
        'schemaVersion',
        'surfaceId',
      },
      path: 'measurementPublicationDraft',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'measurementPublicationDraft',
    );
    final artifacts = reader.list('artifacts');
    final codeIdentityBindings = reader.list('codeIdentityBindings');
    final nodes = reader.list('nodes');
    final events = reader.list('events');
    final routes = reader.list('routes');
    final lineageIntents = reader.list('lineageIntents');
    _validateRawDraftListBounds(
      artifacts: artifacts,
      codeIdentityBindings: codeIdentityBindings,
      nodes: nodes,
      events: events,
      routes: routes,
      lineageIntents: lineageIntents,
    );
    final encodedRoutes = [
      for (final value in routes)
        MeasurementPublicationDraftRouteV1.fromJson(
          requireCanonicalObject(value, 'routes[]'),
        ),
    ];
    return _constructDraft(
      'measurementPublicationDraft',
      () {
        final finalArtifacts = [
          for (final value in artifacts)
            MeasurementPublicationDraftArtifactV1.fromJson(
              requireCanonicalObject(value, 'artifacts[]'),
            ),
        ];
        final routePlan = MeasurementPublicationRoutePlanV1(
          surfaceId: SurfaceId(reader.string('surfaceId')),
          analyticsSurfaceKey: AnalyticsSurfaceKey(
            reader.string('analyticsSurfaceKey'),
          ),
          deliverySurfaceType: DeliverySurfaceTypeId(
            reader.string('deliverySurfaceType'),
          ),
          minimumMeasurementClient: reader.integer('minimumMeasurementClient'),
          completeManifestId: MeasurementManifestId(
            reader.string('completeManifestId'),
          ),
          privacyPolicyRevisionId: AuthorityRevisionId(
            reader.string('privacyPolicyRevisionId'),
          ),
          collectionBudgetRevisionId: AuthorityRevisionId(
            reader.string('collectionBudgetRevisionId'),
          ),
          artifacts: [
            for (final artifact in finalArtifacts)
              MeasurementPublicationRouteArtifactV1(
                artifactId: artifact.artifactId,
                artifactKind: artifact.artifactKind,
                occurrenceEdgeToken: artifact.occurrenceEdgeToken,
                localManifestId: artifact.localManifestId,
                parentOccurrenceEdgeToken: artifact.parentOccurrenceEdgeToken,
              ),
          ],
          codeIdentityBindings: [
            for (final value in codeIdentityBindings)
              CodeIdentityBindingV1.fromJson(
                requireCanonicalObject(value, 'codeIdentityBindings[]'),
              ),
          ],
          nodes: [
            for (final value in nodes)
              MeasurementPublicationDraftNodeV1.fromJson(
                requireCanonicalObject(value, 'nodes[]'),
              ),
          ],
          events: [
            for (final value in events)
              MeasurementPublicationDraftEventV1.fromJson(
                requireCanonicalObject(value, 'events[]'),
              ),
          ],
          routeSeeds: [
            for (final route in encodedRoutes)
              MeasurementPublicationDraftRouteSeedV1(
                generatedReferenceId: route.generatedReferenceId,
                artifactOccurrenceEdgeToken: route.artifactOccurrenceEdgeToken,
              ),
          ],
          lineageIntents: [
            for (final value in lineageIntents)
              MeasurementPublicationLineageIntentV1.fromJson(
                requireCanonicalObject(value, 'lineageIntents[]'),
              ),
          ],
        );
        final draft = MeasurementPublicationDraftV1(
          routePlan: routePlan,
          artifacts: finalArtifacts,
        );
        if (!_sameRoutes(draft.routes, encodedRoutes)) {
          throw ArgumentError(
            'A decoded draft route must equal its derived full carrier and '
            'fingerprint',
          );
        }
        return draft;
      },
    );
  }

  /// Carrier-independent plan that owns every derived route.
  final MeasurementPublicationRoutePlanV1 routePlan;

  /// Stable compiler-ledger surface identity; not a final target identity.
  SurfaceId get surfaceId => routePlan.surfaceId;

  /// Analytics key sealed into a future published revision.
  AnalyticsSurfaceKey get analyticsSurfaceKey => routePlan.analyticsSurfaceKey;

  /// Registered delivery-surface type identity.
  DeliverySurfaceTypeId get deliverySurfaceType =>
      routePlan.deliverySurfaceType;

  /// Minimum Measurement client capability revision.
  int get minimumMeasurementClient => routePlan.minimumMeasurementClient;

  /// Target-neutral complete manifest identity.
  MeasurementManifestId get completeManifestId => routePlan.completeManifestId;

  /// Immutable privacy policy revision.
  AuthorityRevisionId get privacyPolicyRevisionId =>
      routePlan.privacyPolicyRevisionId;

  /// Immutable collection budget revision.
  AuthorityRevisionId get collectionBudgetRevisionId =>
      routePlan.collectionBudgetRevisionId;

  /// Complete generated artifact occurrence closure.
  final List<MeasurementPublicationDraftArtifactV1> artifacts;

  /// Target-neutral projection of the code identity ledger.
  List<CodeIdentityBindingV1> get codeIdentityBindings =>
      routePlan.codeIdentityBindings;

  /// Complete canonical node ancestry closure.
  List<MeasurementPublicationDraftNodeV1> get nodes => routePlan.nodes;

  /// Complete compiler-resolved source-event closure.
  List<MeasurementPublicationDraftEventV1> get events => routePlan.events;

  /// Strict carrier derivation seeds, retained only through [routes] on wire.
  List<MeasurementPublicationDraftRouteSeedV1> get routeSeeds =>
      routePlan.routeSeeds;

  /// Complete target-neutral lineage operation set.
  List<MeasurementPublicationLineageIntentV1> get lineageIntents =>
      routePlan.lineageIntents;

  /// Fully derived carrier spellings and fingerprints.
  late final List<MeasurementPublicationDraftRouteV1> routes;

  /// Digest of the explicit carrier-independent route projection.
  CanonicalDigest get routeDraftClosureDigest =>
      routePlan.routeDraftClosureDigest;

  @override
  CanonicalHashDomain get hashDomain =>
      CanonicalHashDomain.measurementPublicationDraft;

  @override
  Map<String, Object?> toJson() => {
        'analyticsSurfaceKey': analyticsSurfaceKey.value,
        'artifacts': [for (final artifact in artifacts) artifact.toJson()],
        'codeIdentityBindings': [
          for (final binding in codeIdentityBindings) binding.toJson(),
        ],
        'collectionBudgetRevisionId': collectionBudgetRevisionId.value,
        'completeManifestId': completeManifestId.value,
        'deliverySurfaceType': deliverySurfaceType.value,
        'events': [for (final event in events) event.toJson()],
        'kind': 'measurementPublicationDraft',
        'lineageIntents': [
          for (final intent in lineageIntents) intent.toJson(),
        ],
        'minimumMeasurementClient': minimumMeasurementClient,
        'nodes': [for (final node in nodes) node.toJson()],
        'privacyPolicyRevisionId': privacyPolicyRevisionId.value,
        'routes': [for (final route in routes) route.toJson()],
        'schemaVersion': kMeasurementSchemaVersion,
        'surfaceId': surfaceId.value,
      };

  void _validateFinalArtifactClosure() {
    if (artifacts.length != routePlan.artifacts.length) {
      throw ArgumentError(
        'Final artifacts must exactly match the route-plan topology',
      );
    }
    final definitionsByArtifactId =
        <String, MeasurementPublicationDraftArtifactV1>{};
    for (var index = 0; index < artifacts.length; index++) {
      final artifact = artifacts[index];
      final planned = routePlan.artifacts[index];
      if (artifact.artifactId != planned.artifactId ||
          artifact.artifactKind != planned.artifactKind ||
          artifact.occurrenceEdgeToken != planned.occurrenceEdgeToken ||
          artifact.localManifestId != planned.localManifestId ||
          artifact.parentOccurrenceEdgeToken !=
              planned.parentOccurrenceEdgeToken) {
        throw ArgumentError(
          'Final artifacts must exactly match the route-plan topology',
        );
      }
      final existing = definitionsByArtifactId[artifact.artifactId.value];
      if (existing != null &&
          (existing.artifactKind != artifact.artifactKind ||
              existing.contentHash != artifact.contentHash ||
              existing.localManifestId != artifact.localManifestId)) {
        throw ArgumentError(
          'Repeated draft artifact occurrences must preserve one exact '
          'definition and local manifest provenance',
        );
      }
      definitionsByArtifactId[artifact.artifactId.value] = artifact;
    }
  }
}

List<MeasurementPublicationDraftArtifactV1> _sortedUniqueArtifacts(
  List<MeasurementPublicationDraftArtifactV1> values,
) {
  if (values.isEmpty ||
      values.length > kMaximumMeasurementPublicationDraftArtifactCount) {
    throw ArgumentError('A draft requires bounded artifact occurrences');
  }
  final copy = values.toList()
    ..sort(
      (left, right) => left.occurrenceEdgeToken.value.compareTo(
        right.occurrenceEdgeToken.value,
      ),
    );
  _rejectDuplicates(
    copy.map((artifact) => artifact.occurrenceEdgeToken.value),
    'Draft artifact occurrence edges',
  );
  return List.unmodifiable(copy);
}

List<MeasurementPublicationRouteArtifactV1> _sortedUniqueRouteArtifacts(
  List<MeasurementPublicationRouteArtifactV1> values,
) {
  if (values.isEmpty ||
      values.length > kMaximumMeasurementPublicationDraftArtifactCount) {
    throw ArgumentError('A route plan requires bounded artifact occurrences');
  }
  final copy = values.toList()
    ..sort(
      (left, right) => left.occurrenceEdgeToken.value.compareTo(
        right.occurrenceEdgeToken.value,
      ),
    );
  _rejectDuplicates(
    copy.map((artifact) => artifact.occurrenceEdgeToken.value),
    'Route-plan artifact occurrence edges',
  );
  return List.unmodifiable(copy);
}

List<CodeIdentityBindingV1> _sortedUniqueCodeIdentityBindings(
  List<CodeIdentityBindingV1> values,
) {
  if (values.isEmpty ||
      values.length > kMaximumMeasurementPublicationDraftNodeCount) {
    throw ArgumentError('A draft requires bounded code identity bindings');
  }
  final copy = values.toList()
    ..sort(
      (left, right) =>
          left.codeIdentityId.value.compareTo(right.codeIdentityId.value),
    );
  _rejectDuplicates(
    copy.map((binding) => binding.codeIdentityId.value),
    'Draft code identities',
  );
  final nodeTokens = copy
      .map((binding) => binding.canonicalNodeTokenId.value)
      .toList()
    ..sort();
  _rejectDuplicates(nodeTokens, 'Draft canonical node tokens');
  return List.unmodifiable(copy);
}

List<MeasurementPublicationDraftNodeV1> _sortedUniqueNodes(
  List<MeasurementPublicationDraftNodeV1> values,
) {
  if (values.isEmpty ||
      values.length > kMaximumMeasurementPublicationDraftNodeCount) {
    throw ArgumentError('A draft requires bounded canonical nodes');
  }
  final copy = values.toList()
    ..sort(
      (left, right) =>
          left.codeIdentityId.value.compareTo(right.codeIdentityId.value),
    );
  _rejectDuplicates(
    copy.map((node) => node.codeIdentityId.value),
    'Draft nodes',
  );
  return List.unmodifiable(copy);
}

List<MeasurementPublicationDraftEventV1> _sortedUniqueEvents(
  List<MeasurementPublicationDraftEventV1> values,
) {
  if (values.length > kMaximumMeasurementPublicationDraftEventCount) {
    throw ArgumentError('A draft exceeds its bounded event closure');
  }
  final copy = values.toList()
    ..sort(
      (left, right) => left.generatedReferenceId.value.compareTo(
        right.generatedReferenceId.value,
      ),
    );
  _rejectDuplicates(
    copy.map((event) => event.generatedReferenceId.value),
    'Draft generated references',
  );
  return List.unmodifiable(copy);
}

List<MeasurementPublicationDraftRouteSeedV1> _sortedUniqueRouteSeeds(
  List<MeasurementPublicationDraftRouteSeedV1> values,
) {
  if (values.length > kMaximumMeasurementPublicationDraftRouteCount) {
    throw ArgumentError('A draft exceeds its bounded route closure');
  }
  final copy = values.toList()
    ..sort(
      (left, right) => left.generatedReferenceId.value.compareTo(
        right.generatedReferenceId.value,
      ),
    );
  _rejectDuplicates(
    copy.map((route) => route.generatedReferenceId.value),
    'Draft route generated references',
  );
  return List.unmodifiable(copy);
}

List<MeasurementPublicationDraftRouteV1> _deriveRoutes(
  List<MeasurementPublicationDraftRouteSeedV1> routeSeeds,
  CanonicalDigest routeDraftClosureDigest,
) =>
    List.unmodifiable([
      for (final routeSeed in routeSeeds)
        _deriveRoute(routeSeed, routeDraftClosureDigest),
    ]);

MeasurementPublicationDraftRouteV1 _deriveRoute(
  MeasurementPublicationDraftRouteSeedV1 routeSeed,
  CanonicalDigest routeDraftClosureDigest,
) {
  final carrier = MeasurementPublicationRouteCarrierV1.derive(
    routeDraftClosureDigest: routeDraftClosureDigest,
    artifactOccurrenceEdgeToken: routeSeed.artifactOccurrenceEdgeToken,
    generatedReferenceId: routeSeed.generatedReferenceId,
  );
  return MeasurementPublicationDraftRouteV1(
    generatedReferenceId: routeSeed.generatedReferenceId,
    artifactOccurrenceEdgeToken: routeSeed.artifactOccurrenceEdgeToken,
    carrier: carrier.value,
    opaqueRouteToken: OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(
      carrier.value,
    ),
  );
}

void _validateRawDraftListBounds({
  required List<Object?> artifacts,
  required List<Object?> codeIdentityBindings,
  required List<Object?> nodes,
  required List<Object?> events,
  required List<Object?> routes,
  required List<Object?> lineageIntents,
}) {
  if (artifacts.isEmpty ||
      artifacts.length > kMaximumMeasurementPublicationDraftArtifactCount ||
      codeIdentityBindings.isEmpty ||
      codeIdentityBindings.length >
          kMaximumMeasurementPublicationDraftNodeCount ||
      nodes.isEmpty ||
      nodes.length > kMaximumMeasurementPublicationDraftNodeCount ||
      events.length > kMaximumMeasurementPublicationDraftEventCount ||
      routes.length > kMaximumMeasurementPublicationDraftRouteCount ||
      lineageIntents.length >
          kMaximumMeasurementPublicationDraftLineageIntentCount) {
    throw const CanonicalFormatException(
      'measurementPublicationDraft exceeds one raw closure bound',
    );
  }
}

void _validateRawRoutePlanListBounds({
  required List<Object?> artifacts,
  required List<Object?> codeIdentityBindings,
  required List<Object?> nodes,
  required List<Object?> events,
  required List<Object?> routeSeeds,
  required List<Object?> lineageIntents,
}) {
  if (artifacts.isEmpty ||
      artifacts.length > kMaximumMeasurementPublicationDraftArtifactCount ||
      codeIdentityBindings.isEmpty ||
      codeIdentityBindings.length >
          kMaximumMeasurementPublicationDraftNodeCount ||
      nodes.isEmpty ||
      nodes.length > kMaximumMeasurementPublicationDraftNodeCount ||
      events.length > kMaximumMeasurementPublicationDraftEventCount ||
      routeSeeds.length > kMaximumMeasurementPublicationDraftRouteCount ||
      lineageIntents.length >
          kMaximumMeasurementPublicationDraftLineageIntentCount) {
    throw const CanonicalFormatException(
      'measurementPublicationRouteDraftClosure exceeds one raw closure bound',
    );
  }
}

List<MeasurementPublicationLineageIntentV1> _sortedUniqueLineageIntents(
  List<MeasurementPublicationLineageIntentV1> values,
) {
  if (values.length > kMaximumMeasurementPublicationDraftLineageIntentCount) {
    throw ArgumentError('A draft exceeds its bounded lineage intent closure');
  }
  final copy = values.toList()
    ..sort(
      (left, right) =>
          left.transitionId.value.compareTo(right.transitionId.value),
    );
  _rejectDuplicates(
    copy.map((intent) => intent.transitionId.value),
    'Draft lineage transitions',
  );
  return List.unmodifiable(copy);
}

List<PointLineageId> _sortedUniqueLineageIds(List<PointLineageId> values) {
  final copy = values.toList()
    ..sort((left, right) => left.value.compareTo(right.value));
  _rejectDuplicates(
    copy.map((value) => value.value),
    'Intent prior lineages',
  );
  return List.unmodifiable(copy);
}

List<MeasurementPublicationCurrentEndpointIntentV1>
    _sortedUniqueCurrentEndpointIntents(
  List<MeasurementPublicationCurrentEndpointIntentV1> values,
) {
  final copy = values.toList()
    ..sort(
      (left, right) => left.generatedReferenceId.value.compareTo(
        right.generatedReferenceId.value,
      ),
    );
  _rejectDuplicates(
    copy.map((value) => value.generatedReferenceId.value),
    'Intent current generated references',
  );
  return List.unmodifiable(copy);
}

void _validateAcyclicParentClosure(
  String root,
  Iterable<MapEntry<String, String?>> values,
  String label,
) {
  final parents = {for (final entry in values) entry.key: entry.value};
  final children = <String, List<String>>{};
  for (final entry in parents.entries) {
    final parent = entry.value;
    if (parent != null) {
      children.putIfAbsent(parent, () => <String>[]).add(entry.key);
    }
  }
  final reachable = <String>{};
  final visiting = <String>{};
  void visit(String value) {
    if (!visiting.add(value)) throw ArgumentError('$label must be acyclic');
    if (reachable.add(value)) {
      (children[value] ?? const <String>[]).forEach(visit);
    }
    visiting.remove(value);
  }

  visit(root);
  if (reachable.length != parents.length) {
    throw ArgumentError('Every $label entry must be root-reachable');
  }
}

void _requireExactStringKeys({
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

void _rejectDuplicates(Iterable<String> values, String label) {
  String? previous;
  for (final value in values) {
    if (value == previous) throw ArgumentError('$label must be unique');
    previous = value;
  }
}

bool _sameRoutes(
  List<MeasurementPublicationDraftRouteV1> left,
  List<MeasurementPublicationDraftRouteV1> right,
) =>
    left.length == right.length &&
    left.indexed.every((entry) => entry.$2 == right[entry.$1]);

NormalizedInteractionKind _normalizedInteractionKindFromWire(String value) =>
    _wireEnum(
      NormalizedInteractionKind.values,
      value,
      (entry) => entry.wireName,
      'normalized interaction kind',
    );

MeasurementPrivacyClass _privacyClassFromWire(String value) => _wireEnum(
      MeasurementPrivacyClass.values,
      value,
      (entry) => entry.wireName,
      'measurement privacy class',
    );

SemanticValueClass _semanticValueClassFromWire(String value) => _wireEnum(
      SemanticValueClass.values,
      value,
      (entry) => entry.wireName,
      'semantic value class',
    );

MeasurementCollectionClass _collectionClassFromWire(String value) => _wireEnum(
      MeasurementCollectionClass.values,
      value,
      (entry) => entry.wireName,
      'measurement collection class',
    );

LineageOperation _lineageOperationFromWire(String value) => _wireEnum(
      LineageOperation.values,
      value,
      (entry) => entry.wireName,
      'lineage operation',
    );

LineageTransitionAuthority _lineageAuthorityFromWire(String value) => _wireEnum(
      LineageTransitionAuthority.values,
      value,
      (entry) => entry.wireName,
      'lineage transition authority',
    );

T _wireEnum<T>(
  List<T> values,
  String value,
  String Function(T value) wireName,
  String label,
) {
  for (final candidate in values) {
    if (wireName(candidate) == value) return candidate;
  }
  throw CanonicalFormatException('Unknown $label "$value"');
}

T _constructDraft<T>(String path, T Function() create) {
  try {
    return create();
    // Constructor admission failures must become canonical decoder failures.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}
