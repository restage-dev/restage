import 'dart:collection';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;

/// Shared resolved descriptor used by the code-identity ledger.
typedef MeasurementRfwPresentationDescriptor
    = rfw.RfwCatalogOccurrenceDescriptor;

/// Shared anchor for an ordinary reachable local RFW declaration body.
typedef MeasurementRfwPresentationLocalDeclarationAnchor
    = rfw.RfwCatalogOccurrenceLocalDeclarationAnchor;

/// Shared exact parsed call selected before artifact encoding.
typedef MeasurementRfwPresentationOccurrence = rfw.RfwCatalogOccurrence;

/// Shared value-stable handle retained across compiler passes.
typedef MeasurementPresentationOccurrenceHandle
    = rfw.RfwCatalogOccurrenceHandle;

/// Reconciled presentation witness reserved for one RFW structural descriptor.
final class MeasurementRfwPresentationPlannedOccurrence {
  /// Creates one ledger-reconciled occurrence reservation.
  const MeasurementRfwPresentationPlannedOccurrence({
    required this.handle,
    required this.structuralOccurrenceKey,
    required this.measurementSurfaceId,
    required this.routeDraftClosureDigest,
    required this.nodeCodeIdentityId,
    required this.canonicalNodeTokenId,
    required this.artifactOccurrenceEdgeToken,
    required this.presentationLineageId,
    required this.presentationReferenceId,
    required this.presentationDisplayMetadataRef,
    required this.presentationRoute,
  });

  /// Opaque frozen occurrence handle selected before artifact encoding.
  final MeasurementPresentationOccurrenceHandle handle;

  /// Descriptor key selected by ledger reconciliation.
  final String structuralOccurrenceKey;

  /// Stable surface selected by the route plan.
  final SurfaceId measurementSurfaceId;

  /// Canonical digest of the completed target-neutral route closure.
  final CanonicalDigest routeDraftClosureDigest;

  /// Ledger-owned code identity for the descriptor.
  final CodeIdentityId nodeCodeIdentityId;

  /// Canonical node witness selected by the ledger.
  final NodeTokenId canonicalNodeTokenId;

  /// Mounted artifact occurrence that owns the descriptor.
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;

  /// Stable presentation continuity witness.
  final PointLineageId presentationLineageId;

  /// Target-neutral reference reserved before final artifact encoding.
  final GeneratedPresentationReferenceId presentationReferenceId;

  /// Non-identity display witness.
  final DisplayMetadataRef presentationDisplayMetadataRef;

  /// Derived route consumed by the final RFW composition pass.
  final MeasurementPublicationDraftPresentationRouteV1 presentationRoute;
}

/// Reconciled presentation reservations for one publication route plan.
final class MeasurementRfwPresentationPublicationPlan {
  /// Creates and validates the target-neutral occurrence-to-route mapping.
  MeasurementRfwPresentationPublicationPlan({
    required this.routePlan,
    required Map<String, CodeIdentityId> codeIdentityByStructuralOccurrenceKey,
    required Iterable<MeasurementRfwPresentationPlannedOccurrence> occurrences,
  })  : codeIdentityByStructuralOccurrenceKey = Map.unmodifiable(
          Map.of(codeIdentityByStructuralOccurrenceKey),
        ),
        occurrences = List.unmodifiable(occurrences) {
    final byKey = <String, MeasurementRfwPresentationPlannedOccurrence>{};
    final descriptorKeys = <String>{};
    final handles = <MeasurementPresentationOccurrenceHandle>{};
    final references = <String>{};
    final routeByReference = {
      for (final route in routePlan.presentationRoutes)
        route.generatedPresentationReferenceId.value: route,
    };
    final presentationByReference = {
      for (final presentation in routePlan.presentations)
        presentation.generatedPresentationReferenceId.value: presentation,
    };
    final bindingByCode = {
      for (final binding in routePlan.codeIdentityBindings)
        binding.codeIdentityId.value: binding,
    };
    final nodeByCode = {
      for (final node in routePlan.nodes) node.codeIdentityId.value: node,
    };
    final artifactEdges = {
      for (final artifact in routePlan.artifacts)
        artifact.occurrenceEdgeToken.value,
    };
    if (this.codeIdentityByStructuralOccurrenceKey.length >
        kMaximumMeasurementPublicationPresentationRouteCount) {
      throw ArgumentError(
        'Presentation reconciliation exceeds the shared route capacity',
      );
    }
    final expectedDescriptorKeys = <String>{
      for (final occurrence in this.occurrences)
        occurrence.structuralOccurrenceKey,
    };
    final reconciledCodeIdentities = <String>{};
    for (final entry in this.codeIdentityByStructuralOccurrenceKey.entries) {
      if (!reconciledCodeIdentities.add(entry.value.value)) {
        throw ArgumentError(
          'Presentation reconciliation code identities must be unique',
        );
      }
    }
    if (this.codeIdentityByStructuralOccurrenceKey.length !=
            expectedDescriptorKeys.length ||
        !this
            .codeIdentityByStructuralOccurrenceKey
            .keys
            .toSet()
            .containsAll(expectedDescriptorKeys) ||
        !expectedDescriptorKeys.containsAll(
          this.codeIdentityByStructuralOccurrenceKey.keys,
        )) {
      throw ArgumentError(
        'Presentation reconciliation must contain exactly one identity per '
        'planned occurrence',
      );
    }
    for (final occurrence in this.occurrences) {
      final key = _plannedOccurrenceKey(
        occurrence.artifactOccurrenceEdgeToken,
        occurrence.structuralOccurrenceKey,
      );
      if (byKey.putIfAbsent(key, () => occurrence) != occurrence) {
        throw ArgumentError(
            'A presentation descriptor has two route witnesses');
      }
      if (!descriptorKeys.add(occurrence.structuralOccurrenceKey)) {
        throw ArgumentError('A presentation descriptor was repeated');
      }
      if (!handles.add(occurrence.handle)) {
        throw ArgumentError('A presentation occurrence handle was repeated');
      }
      if (!references.add(occurrence.presentationReferenceId.value)) {
        throw ArgumentError('A presentation route witness was repeated');
      }
      if (codeIdentityByStructuralOccurrenceKey[
              occurrence.structuralOccurrenceKey] !=
          occurrence.nodeCodeIdentityId) {
        throw ArgumentError(
          'A presentation occurrence must retain its reconciled code identity',
        );
      }
      if (occurrence.measurementSurfaceId != routePlan.surfaceId ||
          occurrence.routeDraftClosureDigest !=
              routePlan.routeDraftClosureDigest ||
          !artifactEdges
              .contains(occurrence.artifactOccurrenceEdgeToken.value)) {
        throw ArgumentError(
          'A presentation occurrence must retain its route-plan surface and '
          'artifact closure',
        );
      }
      final route = routeByReference[occurrence.presentationReferenceId.value];
      final presentation =
          presentationByReference[occurrence.presentationReferenceId.value];
      final binding = bindingByCode[occurrence.nodeCodeIdentityId.value];
      final node = nodeByCode[occurrence.nodeCodeIdentityId.value];
      if (route == null ||
          presentation == null ||
          binding == null ||
          node == null ||
          !_samePresentationRoute(occurrence.presentationRoute, route) ||
          presentation.nodeCodeIdentityId != occurrence.nodeCodeIdentityId ||
          presentation.lineageId != occurrence.presentationLineageId ||
          presentation.displayMetadataRef !=
              occurrence.presentationDisplayMetadataRef ||
          binding.canonicalNodeTokenId != occurrence.canonicalNodeTokenId ||
          node.artifactOccurrenceEdgeToken !=
              occurrence.artifactOccurrenceEdgeToken) {
        throw ArgumentError(
          'A presentation occurrence must retain its exact route witness',
        );
      }
    }
    final expectedReferences = <String>{
      for (final route in routePlan.presentationRoutes)
        route.generatedPresentationReferenceId.value,
    };
    if (references.length != expectedReferences.length ||
        !references.containsAll(expectedReferences)) {
      throw ArgumentError(
        'Presentation route reservations must close over the route plan',
      );
    }
    _occurrencesByKey = Map.unmodifiable(byKey);
  }

  /// Target-neutral route plan whose references were reserved before final
  /// composition.
  final MeasurementPublicationRoutePlanV1 routePlan;

  /// Ledger reconciliation map that binds each frozen descriptor to one code
  /// identity before route witnesses are constructed.
  final Map<String, CodeIdentityId> codeIdentityByStructuralOccurrenceKey;

  /// Every reconciled RFW presentation occurrence.
  final List<MeasurementRfwPresentationPlannedOccurrence> occurrences;

  late final Map<String, MeasurementRfwPresentationPlannedOccurrence>
      _occurrencesByKey;

  /// Materializes exact final parsed-call joins from [occurrenceSet].
  ///
  /// The set resolves eligibility before any artifact encoding. Its rebinding
  /// method proves final topology before this measurement adapter attaches
  /// routes to exact final call objects.
  MeasurementRfwPresentationArtifactMaterialization materializeArtifact({
    required rfw.ResolvedRfwCatalogOccurrenceSet occurrenceSet,
    required rfw.RemoteWidgetLibrary finalLibrary,
    required ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken,
  }) {
    final rebinding = occurrenceSet.rebindFinalLibrary(finalLibrary);
    final expected = <String, MeasurementRfwPresentationPlannedOccurrence>{
      for (final occurrence in occurrences)
        if (occurrence.artifactOccurrenceEdgeToken ==
            artifactOccurrenceEdgeToken)
          occurrence.structuralOccurrenceKey: occurrence,
    };
    for (final planned in expected.values) {
      final frozen = occurrenceSet.occurrenceForHandle(planned.handle);
      if (frozen == null ||
          frozen.descriptor.structuralOccurrenceKey !=
              planned.structuralOccurrenceKey) {
        throw const FormatException(
          'A presentation witness does not match its frozen occurrence',
        );
      }
    }
    final joins = <MeasurementPresentationOccurrenceJoin>[];
    final joinsByCall = Map<rfw.ConstructorCall,
        MeasurementPresentationOccurrenceJoin>.identity();
    final joinsByHandle = <MeasurementPresentationOccurrenceHandle,
        MeasurementPresentationOccurrenceJoin>{};
    for (final binding in rebinding.bindings) {
      final planned = _occurrencesByKey[_plannedOccurrenceKey(
        artifactOccurrenceEdgeToken,
        binding.descriptor.structuralOccurrenceKey,
      )];
      if (planned == null) {
        throw const FormatException(
          'A final RFW catalog occurrence has no presentation witness',
        );
      }
      if (expected.remove(binding.descriptor.structuralOccurrenceKey) == null) {
        throw const FormatException(
          'A final RFW catalog occurrence repeats one presentation witness',
        );
      }
      if (binding.handle != planned.handle) {
        throw const FormatException(
          'A final RFW catalog occurrence changed its presentation handle',
        );
      }
      final join = MeasurementPresentationOccurrenceJoin._(
        handle: binding.handle,
        constructorCall: binding.constructorCall,
        measurementSurfaceId: planned.measurementSurfaceId,
        routeDraftClosureDigest: planned.routeDraftClosureDigest,
        nodeCodeIdentityId: planned.nodeCodeIdentityId,
        canonicalNodeTokenId: planned.canonicalNodeTokenId,
        artifactOccurrenceEdgeToken: planned.artifactOccurrenceEdgeToken,
        presentationLineageId: planned.presentationLineageId,
        presentationReferenceId: planned.presentationReferenceId,
        presentationDisplayMetadataRef: planned.presentationDisplayMetadataRef,
        presentationRoute: planned.presentationRoute,
      );
      if (joinsByCall.putIfAbsent(join.constructorCall, () => join) != join ||
          joinsByHandle.putIfAbsent(join.handle, () => join) != join) {
        throw const FormatException(
          'Presentation occurrence handles must be unique',
        );
      }
      joins.add(join);
    }
    if (expected.isNotEmpty) {
      final missing = expected.keys.toList()..sort();
      throw FormatException(
        'A planned presentation witness has no final RFW catalog occurrence: '
        '$missing',
      );
    }
    return MeasurementRfwPresentationArtifactMaterialization._(
      occurrenceSet: occurrenceSet,
      rebinding: rebinding,
      artifactOccurrenceEdgeToken: artifactOccurrenceEdgeToken,
      joins: joins,
      joinsByCall: joinsByCall,
      joinsByHandle: joinsByHandle,
    );
  }
}

/// Exact join between a final parsed call and its route witness.
final class MeasurementPresentationOccurrenceJoin {
  const MeasurementPresentationOccurrenceJoin._({
    required this.handle,
    required this.constructorCall,
    required this.measurementSurfaceId,
    required this.routeDraftClosureDigest,
    required this.nodeCodeIdentityId,
    required this.canonicalNodeTokenId,
    required this.artifactOccurrenceEdgeToken,
    required this.presentationLineageId,
    required this.presentationReferenceId,
    required this.presentationDisplayMetadataRef,
    required this.presentationRoute,
  });

  /// Exact same-pass occurrence handle.
  final MeasurementPresentationOccurrenceHandle handle;

  /// Exact parsed RFW constructor object.
  final rfw.ConstructorCall constructorCall;

  /// Stable measurement surface selected by the route plan.
  final SurfaceId measurementSurfaceId;

  /// Canonical digest of the target-neutral route closure.
  final CanonicalDigest routeDraftClosureDigest;

  /// Ledger-owned identity for this occurrence.
  final CodeIdentityId nodeCodeIdentityId;

  /// Canonical node witness selected by the ledger.
  final NodeTokenId canonicalNodeTokenId;

  /// Mounted artifact occurrence that owns the call.
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;

  /// Stable presentation continuity witness.
  final PointLineageId presentationLineageId;

  /// Draft continuity witness retained for the target-neutral projection.
  PointLineageId get draftPresentationLineageId => presentationLineageId;

  /// Reserved target-neutral presentation reference.
  final GeneratedPresentationReferenceId presentationReferenceId;

  /// Non-identity display witness.
  final DisplayMetadataRef presentationDisplayMetadataRef;

  /// Exact final route used by the composer.
  final MeasurementPublicationDraftPresentationRouteV1 presentationRoute;

  /// Exact route carrier selected for this presentation occurrence.
  String get presentationRouteCarrier => presentationRoute.carrier;

  /// Domain-separated fingerprint of [presentationRouteCarrier].
  OpaqueMeasurementRouteTokenV1 get presentationRouteFingerprint =>
      presentationRoute.opaqueRouteToken;
}

/// Same-pass exact-object joins for one final RFW artifact.
final class MeasurementRfwPresentationArtifactMaterialization {
  MeasurementRfwPresentationArtifactMaterialization._({
    required this.occurrenceSet,
    required this.rebinding,
    required this.artifactOccurrenceEdgeToken,
    required Iterable<MeasurementPresentationOccurrenceJoin> joins,
    required Map<rfw.ConstructorCall, MeasurementPresentationOccurrenceJoin>
        joinsByCall,
    required Map<MeasurementPresentationOccurrenceHandle,
            MeasurementPresentationOccurrenceJoin>
        joinsByHandle,
  })  : joins = List.unmodifiable(joins),
        _joinsByCall = UnmodifiableMapView(joinsByCall),
        _joinsByHandle = UnmodifiableMapView(joinsByHandle);

  /// Frozen source occurrence set that established [joins].
  final rfw.ResolvedRfwCatalogOccurrenceSet occurrenceSet;

  /// Exact final-library rebinding that proves [joins] topology.
  final rfw.ResolvedRfwCatalogOccurrenceRebinding rebinding;

  /// Exact parsed final RFW library used by composition.
  rfw.RemoteWidgetLibrary get finalLibrary => rebinding.finalLibrary;

  /// Mounted artifact occurrence containing [joins].
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;

  /// All exact parsed-call joins in this artifact.
  final List<MeasurementPresentationOccurrenceJoin> joins;

  final Map<rfw.ConstructorCall, MeasurementPresentationOccurrenceJoin>
      _joinsByCall;
  final Map<MeasurementPresentationOccurrenceHandle,
      MeasurementPresentationOccurrenceJoin> _joinsByHandle;

  /// Finds a join by exact parsed final call identity.
  MeasurementPresentationOccurrenceJoin? presentationJoinForCall(
    rfw.ConstructorCall constructorCall,
  ) =>
      _joinsByCall[constructorCall];

  /// Finds a join by its value-stable compiler-owned handle.
  MeasurementPresentationOccurrenceJoin? presentationJoinForHandle(
    MeasurementPresentationOccurrenceHandle handle,
  ) =>
      _joinsByHandle[handle];

  /// Requires one known value-stable handle.
  MeasurementPresentationOccurrenceJoin requirePresentationJoinForHandle(
    MeasurementPresentationOccurrenceHandle handle,
  ) {
    final join = presentationJoinForHandle(handle);
    if (join == null) {
      throw const FormatException('Unknown presentation occurrence handle');
    }
    return join;
  }

  /// Validates a typed handle against a caller-supplied final manifest.
  ///
  /// Local build output does not depend on this helper. It checks a manifest
  /// that the caller already holds and returns the matching final reference.
  GeneratedPresentationReferenceV1
      requireFinalizedPresentationReferenceForHandle({
    required MeasurementPresentationOccurrenceHandle handle,
    required CompleteMeasurementManifestV1 completeManifest,
  }) {
    final join = requirePresentationJoinForHandle(handle);
    if (completeManifest.surfaceId != join.measurementSurfaceId) {
      throw ArgumentError(
        'A final manifest must match the presentation measurement surface',
      );
    }
    final matches = completeManifest.generatedPresentationReferences
        .where((reference) =>
            reference.referenceId == join.presentationReferenceId)
        .toList(growable: false);
    if (matches.length != 1) {
      throw const FormatException(
        'A presentation handle requires one final manifest reference',
      );
    }
    final reference = matches.single;
    if (reference.lineageId != join.presentationLineageId ||
        reference.displayMetadataRef != join.presentationDisplayMetadataRef) {
      throw const FormatException(
        'A final manifest reference does not match its presentation witness',
      );
    }
    return reference;
  }
}

String _plannedOccurrenceKey(
  ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken,
  String structuralOccurrenceKey,
) =>
    '${artifactOccurrenceEdgeToken.value}\u0000$structuralOccurrenceKey';

bool _samePresentationRoute(
  MeasurementPublicationDraftPresentationRouteV1 left,
  MeasurementPublicationDraftPresentationRouteV1 right,
) =>
    left.generatedPresentationReferenceId ==
        right.generatedPresentationReferenceId &&
    left.artifactOccurrenceEdgeToken == right.artifactOccurrenceEdgeToken &&
    left.carrier == right.carrier &&
    left.opaqueRouteToken.fingerprint == right.opaqueRouteToken.fingerprint;
