import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/identifiers.dart';
import 'package:restage_measurement_schema/src/manifest.dart';
import 'package:restage_measurement_schema/src/publication_candidate.dart';
import 'package:restage_measurement_schema/src/publication_draft.dart';
import 'package:restage_measurement_schema/src/publication_route.dart';
import 'package:restage_measurement_schema/src/published_identity.dart';

/// Maximum exact artifact definitions carried by one binding.
///
/// This is a binding-protocol admission bound. It does not alter the published
/// graph's accepted set; a larger published bundle simply cannot be consumed
/// through this bounded route-binding protocol.
const int kMaximumMeasurementPublicationBindingArtifactCount = 1024;

/// Maximum mounted artifact occurrences carried by one binding.
const int kMaximumMeasurementPublicationBindingMountedArtifactCount = 1024;

/// Maximum opaque event routes carried by one mounted artifact occurrence.
const int kMaximumMeasurementPublicationBindingRoutesPerMountedArtifact =
    kMaximumMeasurementPublicationRuntimeRouteCount;

/// Maximum opaque event routes carried by one binding across all mounts.
///
/// This is the frozen runtime-route accepted set. The independent artifact
/// graph and canonical-node limits may be larger; they do not widen the
/// number of delivered carrier routes.
const int kMaximumMeasurementPublicationBindingRouteCount =
    kMaximumMeasurementPublicationRuntimeRouteCount;

/// Opaque exact reference to one immutable publication authority record.
///
/// [immutablePublicationDigest] and [declaredArtifactBytesDigest] are opaque
/// to Measurement. A registered adapter may issue this reference
/// only after proving the first digest identifies one immutable external
/// publication/revision and the second digest identifies that publication's
/// exact declared artifact-byte closure. This package intentionally does not
/// decode, name, or import that authority's surface, source, payload, or
/// delivery vocabulary.
final class RegisteredPublicationAuthorityReferenceV1 extends CanonicalValue {
  /// Creates one registered opaque publication reference.
  RegisteredPublicationAuthorityReferenceV1({
    required this.authorityId,
    required this.externalPublicationAuthorityRef,
    required this.candidateReference,
    required this.immutablePublicationDigest,
    required this.declaredArtifactBytesDigest,
  }) {
    if (!_externalPublicationAuthorityRefPattern.hasMatch(
      externalPublicationAuthorityRef,
    )) {
      throw ArgumentError.value(
        externalPublicationAuthorityRef,
        'externalPublicationAuthorityRef',
        'Expected a versioned 192-bit opaque external authority reference',
      );
    }
    if (candidateReference.declaredArtifactBytesDigest !=
        declaredArtifactBytesDigest) {
      throw ArgumentError(
        'The registered authority must retain its candidate declared '
        'artifact-byte digest exactly',
      );
    }
  }

  /// Decodes byte-exact canonical reference bytes.
  factory RegisteredPublicationAuthorityReferenceV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        RegisteredPublicationAuthorityReferenceV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'registeredPublicationAuthorityReference',
      );

  /// Decodes a closed opaque authority reference.
  factory RegisteredPublicationAuthorityReferenceV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'authorityId',
        'candidateReference',
        'declaredArtifactBytesDigest',
        'externalPublicationAuthorityRef',
        'immutablePublicationDigest',
        'kind',
      },
      requiredKeys: const {
        'authorityId',
        'candidateReference',
        'declaredArtifactBytesDigest',
        'externalPublicationAuthorityRef',
        'immutablePublicationDigest',
        'kind',
      },
      path: 'registeredPublicationAuthorityReference',
    );
    if (reader.string('kind') != 'registeredPublicationAuthorityReference') {
      throw const CanonicalFormatException(
        'registeredPublicationAuthorityReference.kind must be '
        '"registeredPublicationAuthorityReference"',
      );
    }
    return _constructBinding(
      'registeredPublicationAuthorityReference',
      () => RegisteredPublicationAuthorityReferenceV1(
        authorityId: MeasurementPublicationAuthorityId(
          reader.string('authorityId'),
        ),
        externalPublicationAuthorityRef: reader.string(
          'externalPublicationAuthorityRef',
        ),
        candidateReference: MeasurementPublicationCandidateReferenceV1.fromJson(
          reader.object('candidateReference'),
        ),
        immutablePublicationDigest: CanonicalDigest(
          reader.string('immutablePublicationDigest'),
        ),
        declaredArtifactBytesDigest: CanonicalDigest(
          reader.string('declaredArtifactBytesDigest'),
        ),
      ),
    );
  }

  /// Registered authority permitted to attest this opaque reference.
  final MeasurementPublicationAuthorityId authorityId;

  /// Globally unique immutable external publication locator.
  final String externalPublicationAuthorityRef;

  /// Target-neutral candidate proven before authority finalization.
  final MeasurementPublicationCandidateReferenceV1 candidateReference;

  /// Digest of one exact immutable external publication/revision.
  final CanonicalDigest immutablePublicationDigest;

  /// Digest of the exact external declaration of artifact bytes.
  final CanonicalDigest declaredArtifactBytesDigest;

  @override
  Map<String, Object?> toJson() => {
        'authorityId': authorityId.value,
        'candidateReference': candidateReference.toJson(),
        'declaredArtifactBytesDigest': declaredArtifactBytesDigest.hex,
        'externalPublicationAuthorityRef': externalPublicationAuthorityRef,
        'immutablePublicationDigest': immutablePublicationDigest.hex,
        'kind': 'registeredPublicationAuthorityReference',
      };
}

/// One artifact-local opaque route to an exact published occurrence and
/// lineage.
///
/// This value deliberately contains no event name, callback arguments, widget
/// key, path, host data/context, or subject identifier.
final class MeasurementPublicationRouteV1 extends CanonicalValue {
  /// Creates one exact opaque carrier route.
  const MeasurementPublicationRouteV1({
    required this.opaqueRouteToken,
    required this.occurrenceId,
    required this.lineageId,
  });

  /// Decodes one strict opaque route.
  factory MeasurementPublicationRouteV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'kind',
        'lineageId',
        'occurrenceId',
        'opaqueRouteToken',
      },
      requiredKeys: const {
        'kind',
        'lineageId',
        'occurrenceId',
        'opaqueRouteToken',
      },
      path: 'measurementPublicationRoute',
    );
    if (reader.string('kind') != 'measurementPublicationRoute') {
      throw const CanonicalFormatException(
        'measurementPublicationRoute.kind must be '
        '"measurementPublicationRoute"',
      );
    }
    return _constructBinding(
      'measurementPublicationRoute',
      () => MeasurementPublicationRouteV1(
        opaqueRouteToken: OpaqueMeasurementRouteTokenV1.fromJson(
          reader.object('opaqueRouteToken'),
        ),
        occurrenceId: CanonicalDigest(reader.string('occurrenceId')),
        lineageId: PointLineageId(reader.string('lineageId')),
      ),
    );
  }

  /// Fingerprint of the host-delivered opaque carrier.
  final OpaqueMeasurementRouteTokenV1 opaqueRouteToken;

  /// Exact published point occurrence selected by the carrier.
  final CanonicalDigest occurrenceId;

  /// Exact published continuity identity selected by the carrier.
  final PointLineageId lineageId;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'measurementPublicationRoute',
        'lineageId': lineageId.value,
        'occurrenceId': occurrenceId.hex,
        'opaqueRouteToken': opaqueRouteToken.toJson(),
      };
}

/// Complete opaque route set for one exact mounted artifact occurrence.
final class MeasurementPublicationMountedArtifactRoutesV1
    extends CanonicalValue {
  /// Creates a bounded, sorted route set for one graph occurrence edge.
  MeasurementPublicationMountedArtifactRoutesV1({
    required this.artifactOccurrenceEdgeToken,
    required List<MeasurementPublicationRouteV1> routes,
  }) : routes = _sortedUniqueMountedRoutes(routes);

  /// Decodes a strict bounded mounted route set.
  factory MeasurementPublicationMountedArtifactRoutesV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'artifactOccurrenceEdgeToken', 'kind', 'routes'},
      requiredKeys: const {'artifactOccurrenceEdgeToken', 'kind', 'routes'},
      path: 'measurementPublicationMountedArtifactRoutes',
    );
    if (reader.string('kind') !=
        'measurementPublicationMountedArtifactRoutes') {
      throw const CanonicalFormatException(
        'measurementPublicationMountedArtifactRoutes.kind must be '
        '"measurementPublicationMountedArtifactRoutes"',
      );
    }
    final routes = reader.list('routes');
    if (routes.isEmpty ||
        routes.length >
            kMaximumMeasurementPublicationBindingRoutesPerMountedArtifact) {
      throw const CanonicalFormatException(
        'measurementPublicationMountedArtifactRoutes.routes exceeds its raw '
        'input bound',
      );
    }
    return _constructBinding(
      'measurementPublicationMountedArtifactRoutes',
      () => MeasurementPublicationMountedArtifactRoutesV1(
        artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
          reader.string('artifactOccurrenceEdgeToken'),
        ),
        routes: [
          for (final route in routes)
            MeasurementPublicationRouteV1.fromJson(
              requireCanonicalObject(route, 'routes[]'),
            ),
        ],
      ),
    );
  }

  /// Exact graph occurrence that owns these artifact-local carrier routes.
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;

  /// Sorted, unique opaque routes for this mounted occurrence.
  final List<MeasurementPublicationRouteV1> routes;

  @override
  Map<String, Object?> toJson() => {
        'artifactOccurrenceEdgeToken': artifactOccurrenceEdgeToken.value,
        'kind': 'measurementPublicationMountedArtifactRoutes',
        'routes': [for (final route in routes) route.toJson()],
      };
}

/// Exact immutable handle by which a consumer requests one binding.
///
/// A handle has no active-revision fallback: both the external immutable
/// publication authority and the expected binding digest are fixed.
final class MeasurementPublicationBindingReferenceV1 extends CanonicalValue {
  /// Creates one exact binding handle.
  const MeasurementPublicationBindingReferenceV1({
    required this.publicationAuthorityReference,
    required this.bindingDigest,
  });

  /// Decodes byte-exact canonical binding-reference bytes.
  factory MeasurementPublicationBindingReferenceV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementPublicationBindingReferenceV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'measurementPublicationBindingReference',
      );

  /// Decodes one closed binding handle.
  factory MeasurementPublicationBindingReferenceV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'bindingDigest',
        'kind',
        'publicationAuthorityReference',
      },
      requiredKeys: const {
        'bindingDigest',
        'kind',
        'publicationAuthorityReference',
      },
      path: 'measurementPublicationBindingReference',
    );
    if (reader.string('kind') != 'measurementPublicationBindingReference') {
      throw const CanonicalFormatException(
        'measurementPublicationBindingReference.kind must be '
        '"measurementPublicationBindingReference"',
      );
    }
    return _constructBinding(
      'measurementPublicationBindingReference',
      () => MeasurementPublicationBindingReferenceV1(
        publicationAuthorityReference:
            RegisteredPublicationAuthorityReferenceV1.fromJson(
          reader.object('publicationAuthorityReference'),
        ),
        bindingDigest: CanonicalDigest(reader.string('bindingDigest')),
      ),
    );
  }

  /// Exact opaque authority reference selected by the external publication.
  final RegisteredPublicationAuthorityReferenceV1 publicationAuthorityReference;

  /// Domain-separated digest of the one expected binding document.
  final CanonicalDigest bindingDigest;

  @override
  Map<String, Object?> toJson() => {
        'bindingDigest': bindingDigest.hex,
        'kind': 'measurementPublicationBindingReference',
        'publicationAuthorityReference': publicationAuthorityReference.toJson(),
      };
}

/// Exact binding plus the publication witnesses it must resolve.
///
/// The binding reference is the immutable publication identity. The repeated
/// published-surface coordinate is a fail-closed witness checked by an owning
/// exact-read authority; it does not introduce a second publication identity.
final class ExactMeasurementPublicationContextRefV1 extends CanonicalValue {
  /// Creates one exact immutable publication-context reference.
  const ExactMeasurementPublicationContextRefV1({
    required this.bindingReference,
    required this.surfaceIdentity,
    required this.surfaceRevisionId,
    required this.artifactGraphHash,
    required this.measurementManifestHash,
  });

  /// Decodes byte-exact canonical publication-context bytes.
  factory ExactMeasurementPublicationContextRefV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        ExactMeasurementPublicationContextRefV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'exactMeasurementPublicationContextRef',
      );

  /// Decodes one closed exact publication-context reference.
  factory ExactMeasurementPublicationContextRefV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactGraphHash',
        'bindingReference',
        'kind',
        'measurementManifestHash',
        'surfaceIdentity',
        'surfaceRevisionId',
      },
      requiredKeys: const {
        'artifactGraphHash',
        'bindingReference',
        'kind',
        'measurementManifestHash',
        'surfaceIdentity',
        'surfaceRevisionId',
      },
      path: 'exactMeasurementPublicationContextRef',
    );
    if (reader.string('kind') != 'exactMeasurementPublicationContextRef') {
      throw const CanonicalFormatException(
        'exactMeasurementPublicationContextRef.kind must be '
        '"exactMeasurementPublicationContextRef"',
      );
    }
    return _constructBinding(
      'exactMeasurementPublicationContextRef',
      () => ExactMeasurementPublicationContextRefV1(
        bindingReference: MeasurementPublicationBindingReferenceV1.fromJson(
          reader.object('bindingReference'),
        ),
        surfaceIdentity: PublishedSurfaceIdentityV1.fromJson(
          reader.object('surfaceIdentity'),
        ),
        surfaceRevisionId:
            SurfaceRevisionId(reader.string('surfaceRevisionId')),
        artifactGraphHash: CanonicalDigest(reader.string('artifactGraphHash')),
        measurementManifestHash: CanonicalDigest(
          reader.string('measurementManifestHash'),
        ),
      ),
    );
  }

  /// Exact immutable binding authority.
  final MeasurementPublicationBindingReferenceV1 bindingReference;

  /// Exact stable published surface identity witness.
  final PublishedSurfaceIdentityV1 surfaceIdentity;

  /// Exact immutable published surface-revision witness.
  final SurfaceRevisionId surfaceRevisionId;

  /// Exact published artifact-graph witness.
  final CanonicalDigest artifactGraphHash;

  /// Exact published complete-manifest witness.
  final CanonicalDigest measurementManifestHash;

  @override
  Map<String, Object?> toJson() => {
        'artifactGraphHash': artifactGraphHash.hex,
        'bindingReference': bindingReference.toJson(),
        'kind': 'exactMeasurementPublicationContextRef',
        'measurementManifestHash': measurementManifestHash.hex,
        'surfaceIdentity': surfaceIdentity.toJson(),
        'surfaceRevisionId': surfaceRevisionId.value,
      };
}

/// One versioned Measurement-owned companion binding for an immutable publish.
///
/// The binding reuses the published revision, artifact graph, complete
/// manifest, artifact records, schema/minimum-client fields, and occurrence /
/// lineage identities rather than copying their fields. The only external
/// publication representation is [publicationAuthorityReference].
final class MeasurementPublicationBindingV1 extends CanonicalDocument {
  /// Creates and validates one exact publication-to-Measurement binding.
  MeasurementPublicationBindingV1({
    required this.publicationAuthorityReference,
    required this.publishedSurfaceRevision,
    required this.exactArtifactGraph,
    required List<PublishedArtifactV1> publishedArtifacts,
    required this.completeMeasurementManifest,
    required List<MeasurementPublicationMountedArtifactRoutesV1>
        mountedArtifactRoutes,
  })  : publishedArtifacts = _sortedUniqueBindingPublishedArtifacts(
          publishedArtifacts,
        ),
        mountedArtifactRoutes = _sortedUniqueMountedArtifactRoutes(
          mountedArtifactRoutes,
        ) {
    _validateBundleBounds();
    validatePublishedMeasurementBundleV1(
      surfaceRevision: publishedSurfaceRevision,
      artifactGraph: exactArtifactGraph,
      publishedArtifacts: this.publishedArtifacts,
      completeManifest: completeMeasurementManifest,
    );
    _validateExactRouteClosure();
  }

  /// Decodes byte-exact canonical binding bytes.
  factory MeasurementPublicationBindingV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementPublicationBindingV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementPublicationBinding',
      );

  /// Decodes a closed, bounded binding document.
  factory MeasurementPublicationBindingV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'completeMeasurementManifest',
        'exactArtifactGraph',
        'kind',
        'mountedArtifactRoutes',
        'publicationAuthorityReference',
        'publishedArtifacts',
        'publishedSurfaceRevision',
        'schemaVersion',
      },
      requiredKeys: const {
        'completeMeasurementManifest',
        'exactArtifactGraph',
        'kind',
        'mountedArtifactRoutes',
        'publicationAuthorityReference',
        'publishedArtifacts',
        'publishedSurfaceRevision',
        'schemaVersion',
      },
      path: 'measurementPublicationBinding',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'measurementPublicationBinding',
    );
    final publishedArtifacts = reader.list('publishedArtifacts');
    if (publishedArtifacts.isEmpty ||
        publishedArtifacts.length >
            kMaximumMeasurementPublicationBindingArtifactCount) {
      throw const CanonicalFormatException(
        'measurementPublicationBinding.publishedArtifacts exceeds its raw '
        'input bound',
      );
    }
    final mountedArtifactRoutes = reader.list('mountedArtifactRoutes');
    if (mountedArtifactRoutes.length >
        kMaximumMeasurementPublicationBindingMountedArtifactCount) {
      throw const CanonicalFormatException(
        'measurementPublicationBinding.mountedArtifactRoutes exceeds its raw '
        'input bound',
      );
    }
    var rawRouteCount = 0;
    for (final mounted in mountedArtifactRoutes) {
      final mountedObject = requireCanonicalObject(
        mounted,
        'mountedArtifactRoutes[]',
      );
      final rawRoutes = mountedObject['routes'];
      if (rawRoutes is List) {
        rawRouteCount += rawRoutes.length;
        if (rawRouteCount > kMaximumMeasurementPublicationBindingRouteCount) {
          throw const CanonicalFormatException(
            'measurementPublicationBinding.mountedArtifactRoutes exceeds its '
            'raw publication-wide route bound',
          );
        }
      }
    }
    return _constructBinding(
      'measurementPublicationBinding',
      () => MeasurementPublicationBindingV1(
        publicationAuthorityReference:
            RegisteredPublicationAuthorityReferenceV1.fromJson(
          reader.object('publicationAuthorityReference'),
        ),
        publishedSurfaceRevision: PublishedSurfaceRevisionV1.fromJson(
          reader.object('publishedSurfaceRevision'),
        ),
        exactArtifactGraph: ExactArtifactGraphV1.fromJson(
          reader.object('exactArtifactGraph'),
        ),
        publishedArtifacts: [
          for (final artifact in publishedArtifacts)
            PublishedArtifactV1.fromJson(
              requireCanonicalObject(artifact, 'publishedArtifacts[]'),
            ),
        ],
        completeMeasurementManifest: CompleteMeasurementManifestV1.fromJson(
          reader.object('completeMeasurementManifest'),
        ),
        mountedArtifactRoutes: [
          for (final mounted in mountedArtifactRoutes)
            MeasurementPublicationMountedArtifactRoutesV1.fromJson(
              requireCanonicalObject(mounted, 'mountedArtifactRoutes[]'),
            ),
        ],
      ),
    );
  }

  /// Opaque exact external publication/revision and artifact-byte authority.
  final RegisteredPublicationAuthorityReferenceV1 publicationAuthorityReference;

  /// Reused immutable published revision, including schema/client gates.
  final PublishedSurfaceRevisionV1 publishedSurfaceRevision;

  /// Reused exact published artifact occurrence graph.
  final ExactArtifactGraphV1 exactArtifactGraph;

  /// Reused published graph-bound artifact records.
  final List<PublishedArtifactV1> publishedArtifacts;

  /// Reused complete published measurement-manifest closure.
  final CompleteMeasurementManifestV1 completeMeasurementManifest;

  /// Opaque token fingerprints grouped by exact mounted artifact occurrence.
  final List<MeasurementPublicationMountedArtifactRoutesV1>
      mountedArtifactRoutes;

  /// Exact immutable handle for this one binding.
  MeasurementPublicationBindingReferenceV1 get reference =>
      MeasurementPublicationBindingReferenceV1(
        publicationAuthorityReference: publicationAuthorityReference,
        bindingDigest: canonicalDigest,
      );

  /// Finds the route declaration set for one exact graph occurrence edge.
  MeasurementPublicationMountedArtifactRoutesV1? routesForMountedArtifact(
    ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken,
  ) {
    for (final routes in mountedArtifactRoutes) {
      if (routes.artifactOccurrenceEdgeToken == artifactOccurrenceEdgeToken) {
        return routes;
      }
    }
    return null;
  }

  /// Whether this binding reconstructs exactly [expectedReference].
  bool matchesReference(
    MeasurementPublicationBindingReferenceV1 expectedReference,
  ) =>
      reference == expectedReference;

  @override
  CanonicalHashDomain get hashDomain =>
      CanonicalHashDomain.measurementPublicationBinding;

  @override
  Map<String, Object?> toJson() => {
        'completeMeasurementManifest': completeMeasurementManifest.toJson(),
        'exactArtifactGraph': exactArtifactGraph.toJson(),
        'kind': 'measurementPublicationBinding',
        'mountedArtifactRoutes': [
          for (final routes in mountedArtifactRoutes) routes.toJson(),
        ],
        'publicationAuthorityReference': publicationAuthorityReference.toJson(),
        'publishedArtifacts': [
          for (final artifact in publishedArtifacts) artifact.toJson(),
        ],
        'publishedSurfaceRevision': publishedSurfaceRevision.toJson(),
        'schemaVersion': kMeasurementSchemaVersion,
      };

  void _validateBundleBounds() {
    if (publishedArtifacts.isEmpty ||
        publishedArtifacts.length >
            kMaximumMeasurementPublicationBindingArtifactCount ||
        exactArtifactGraph.artifactIdentities.length >
            kMaximumMeasurementPublicationBindingArtifactCount ||
        completeMeasurementManifest.localManifests.length >
            kMaximumMeasurementPublicationBindingArtifactCount ||
        exactArtifactGraph.occurrenceEdges.length >
            kMaximumMeasurementPublicationBindingMountedArtifactCount) {
      throw ArgumentError(
        'The binding exceeds its bounded artifact or mounted-occurrence '
        'closure',
      );
    }
  }

  void _validateExactRouteClosure() {
    final totalRouteCount = mountedArtifactRoutes.fold<int>(
      0,
      (sum, mounted) => sum + mounted.routes.length,
    );
    if (totalRouteCount > kMaximumMeasurementPublicationBindingRouteCount) {
      throw ArgumentError('The binding exceeds its total opaque-route bound');
    }

    final graphEdges = <String, ArtifactOccurrenceEdgeV1>{
      for (final edge in exactArtifactGraph.occurrenceEdges)
        edge.edgeToken.value: edge,
    };
    final pointsByOccurrence = <String, MeasurementPointOccurrenceV1>{};
    final requiredOccurrenceIds = <String>{};
    for (final point in completeMeasurementManifest.points) {
      final prior = pointsByOccurrence[point.occurrenceId.hex];
      if (prior != null) {
        throw ArgumentError(
          'The complete manifest cannot repeat one route occurrence',
        );
      }
      pointsByOccurrence[point.occurrenceId.hex] = point;
      if (point.capabilityKind == MeasurementCapabilityKind.sourceInteraction &&
          point.collectionClass != MeasurementCollectionClass.prohibited) {
        requiredOccurrenceIds.add(point.occurrenceId.hex);
      }
    }

    final routedOccurrenceIds = <String>{};
    final routedLineageIds = <String>{};
    final routedFullCarrierFingerprints = <String>{};
    for (final mounted in mountedArtifactRoutes) {
      if (!graphEdges.containsKey(mounted.artifactOccurrenceEdgeToken.value)) {
        throw ArgumentError(
          'Every mounted route set must name an exact artifact graph edge',
        );
      }
      for (final route in mounted.routes) {
        final point = pointsByOccurrence[route.occurrenceId.hex];
        if (point == null ||
            point.capabilityKind !=
                MeasurementCapabilityKind.sourceInteraction ||
            point.collectionClass == MeasurementCollectionClass.prohibited ||
            point.lineageId != route.lineageId ||
            point.artifactOccurrenceEdgeToken !=
                mounted.artifactOccurrenceEdgeToken) {
          throw ArgumentError(
            'Every opaque route must close one admitted exact source '
            'occurrence in its mounted artifact context',
          );
        }
        if (!routedOccurrenceIds.add(route.occurrenceId.hex)) {
          throw ArgumentError(
            'One exact occurrence cannot be routed more than once',
          );
        }
        if (!routedLineageIds.add(route.lineageId.value)) {
          throw ArgumentError(
            'One current lineage cannot be routed more than once',
          );
        }
        if (!routedFullCarrierFingerprints.add(
          route.opaqueRouteToken.fingerprint.hex,
        )) {
          throw ArgumentError(
            'One full opaque route carrier fingerprint cannot occur twice',
          );
        }
      }
    }
    if (!_sameStringSet(requiredOccurrenceIds, routedOccurrenceIds)) {
      throw ArgumentError(
        'Opaque routes must exactly close all admitted source occurrences',
      );
    }
  }
}

/// Exact registered-adapter attestation returned only with an accepted read.
final class RegisteredPublicationAttestationV1 extends CanonicalValue {
  /// Creates one opaque attestation bound to one complete binding reference.
  const RegisteredPublicationAttestationV1({
    required this.bindingReference,
    required this.attestationDigest,
  });

  /// Decodes byte-exact canonical attestation bytes.
  factory RegisteredPublicationAttestationV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        RegisteredPublicationAttestationV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'registeredPublicationAttestation',
      );

  /// Decodes one strict registered attestation.
  factory RegisteredPublicationAttestationV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'attestationDigest', 'bindingReference', 'kind'},
      requiredKeys: const {'attestationDigest', 'bindingReference', 'kind'},
      path: 'registeredPublicationAttestation',
    );
    if (reader.string('kind') != 'registeredPublicationAttestation') {
      throw const CanonicalFormatException(
        'registeredPublicationAttestation.kind must be '
        '"registeredPublicationAttestation"',
      );
    }
    return _constructBinding(
      'registeredPublicationAttestation',
      () => RegisteredPublicationAttestationV1(
        bindingReference: MeasurementPublicationBindingReferenceV1.fromJson(
          reader.object('bindingReference'),
        ),
        attestationDigest: CanonicalDigest(reader.string('attestationDigest')),
      ),
    );
  }

  /// Exact complete binding reference attested by the registered adapter.
  final MeasurementPublicationBindingReferenceV1 bindingReference;

  /// Opaque registered-adapter attestation digest.
  final CanonicalDigest attestationDigest;

  @override
  Map<String, Object?> toJson() => {
        'attestationDigest': attestationDigest.hex,
        'bindingReference': bindingReference.toJson(),
        'kind': 'registeredPublicationAttestation',
      };
}

/// Closed result of an asynchronous exact binding read.
sealed class MeasurementPublicationBindingReadResult {
  const MeasurementPublicationBindingReadResult();

  /// Every disposition the V1 read seam can return.
  static const List<Type> variants = <Type>[
    MeasurementPublicationBindingReadAccepted,
    MeasurementPublicationBindingAbsent,
    MeasurementPublicationBindingUnsupportedFuture,
    MeasurementPublicationBindingMismatched,
    MeasurementPublicationBindingReplayed,
    MeasurementPublicationBindingTransportUnavailable,
  ];
}

/// Exact binding bytes and registered attestation accepted for one request.
final class MeasurementPublicationBindingReadAccepted
    extends MeasurementPublicationBindingReadResult {
  /// Creates an accepted result only when every exact join agrees.
  MeasurementPublicationBindingReadAccepted({
    required this.reference,
    required this.binding,
    required this.registeredPublicationAttestation,
  }) {
    if (!binding.matchesReference(reference) ||
        registeredPublicationAttestation.bindingReference != reference) {
      throw ArgumentError(
        'An accepted exact binding read requires matching reference, binding, '
        'and registered attestation',
      );
    }
  }

  /// Complete immutable handle requested by the caller.
  final MeasurementPublicationBindingReferenceV1 reference;

  /// Exact canonical binding document.
  final MeasurementPublicationBindingV1 binding;

  /// Exact registered-adapter attestation for [reference].
  final RegisteredPublicationAttestationV1 registeredPublicationAttestation;
}

/// The requested exact binding is absent.
final class MeasurementPublicationBindingAbsent
    extends MeasurementPublicationBindingReadResult {
  /// Creates an exact-absence disposition.
  const MeasurementPublicationBindingAbsent();
}

/// The exact binding exists only in a future unsupported contract shape.
final class MeasurementPublicationBindingUnsupportedFuture
    extends MeasurementPublicationBindingReadResult {
  /// Creates a future-contract disposition.
  const MeasurementPublicationBindingUnsupportedFuture();
}

/// Returned binding bytes or attestation did not close against the request.
final class MeasurementPublicationBindingMismatched
    extends MeasurementPublicationBindingReadResult {
  /// Creates a mismatched exact-read disposition.
  const MeasurementPublicationBindingMismatched();
}

/// Returned binding provenance was valid for a different immutable publish.
final class MeasurementPublicationBindingReplayed
    extends MeasurementPublicationBindingReadResult {
  /// Creates a replayed exact-read disposition.
  const MeasurementPublicationBindingReplayed();
}

/// Transport could not return an exact binding without fallback.
final class MeasurementPublicationBindingTransportUnavailable
    extends MeasurementPublicationBindingReadResult {
  /// Creates a transport-unavailable disposition.
  const MeasurementPublicationBindingTransportUnavailable();
}

/// Exact-only asynchronous source of separately published bindings.
// This named port is the dependency-inversion seam for exact-only reads.
// ignore: one_member_abstracts
abstract interface class MeasurementPublicationBindingReadPort {
  /// Reads one binding by its complete immutable handle.
  Future<MeasurementPublicationBindingReadResult> readExact(
    MeasurementPublicationBindingReferenceV1 bindingReference,
  );
}

List<MeasurementPublicationRouteV1> _sortedUniqueMountedRoutes(
  List<MeasurementPublicationRouteV1> values,
) {
  if (values.isEmpty ||
      values.length >
          kMaximumMeasurementPublicationBindingRoutesPerMountedArtifact) {
    throw ArgumentError(
      'A mounted route set requires 1..'
      '$kMaximumMeasurementPublicationBindingRoutesPerMountedArtifact routes',
    );
  }
  final copy = values.toList()
    ..sort(
      (left, right) => left.opaqueRouteToken.fingerprint.hex.compareTo(
        right.opaqueRouteToken.fingerprint.hex,
      ),
    );
  final tokens = <String>{};
  final occurrences = <String>{};
  final lineages = <String>{};
  for (final route in copy) {
    if (!tokens.add(route.opaqueRouteToken.fingerprint.hex)) {
      throw ArgumentError(
        'Opaque route fingerprints must be unique per mounted artifact',
      );
    }
    if (!occurrences.add(route.occurrenceId.hex)) {
      throw ArgumentError(
        'One mounted artifact cannot route one occurrence twice',
      );
    }
    if (!lineages.add(route.lineageId.value)) {
      throw ArgumentError(
        'One mounted artifact cannot route one lineage twice',
      );
    }
  }
  return List.unmodifiable(copy);
}

List<PublishedArtifactV1> _sortedUniqueBindingPublishedArtifacts(
  List<PublishedArtifactV1> values,
) {
  if (values.isEmpty ||
      values.length > kMaximumMeasurementPublicationBindingArtifactCount) {
    throw ArgumentError(
      'A binding requires 1..'
      '$kMaximumMeasurementPublicationBindingArtifactCount published '
      'artifacts',
    );
  }
  final copy = values.toList()
    ..sort(
      (left, right) => left.identity.artifactId.value.compareTo(
        right.identity.artifactId.value,
      ),
    );
  _rejectAdjacentDuplicateStrings(
    copy.map((artifact) => artifact.identity.artifactId.value),
    'Published artifact IDs',
  );
  return List.unmodifiable(copy);
}

List<MeasurementPublicationMountedArtifactRoutesV1>
    _sortedUniqueMountedArtifactRoutes(
  List<MeasurementPublicationMountedArtifactRoutesV1> values,
) {
  if (values.length >
      kMaximumMeasurementPublicationBindingMountedArtifactCount) {
    throw ArgumentError(
      'A binding permits at most '
      '$kMaximumMeasurementPublicationBindingMountedArtifactCount mounted '
      'artifact route sets',
    );
  }
  final copy = values.toList()
    ..sort(
      (left, right) => left.artifactOccurrenceEdgeToken.value.compareTo(
        right.artifactOccurrenceEdgeToken.value,
      ),
    );
  _rejectAdjacentDuplicateStrings(
    copy.map((routes) => routes.artifactOccurrenceEdgeToken.value),
    'Mounted artifact occurrence edges',
  );
  return List.unmodifiable(copy);
}

bool _sameStringSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

void _rejectAdjacentDuplicateStrings(Iterable<String> values, String label) {
  String? prior;
  for (final value in values) {
    if (value == prior) throw ArgumentError('$label must be unique');
    prior = value;
  }
}

final RegExp _externalPublicationAuthorityRefPattern = RegExp(
  r'^mpa1\.[A-Za-z0-9_-]{32}$',
);

T _constructBinding<T>(String path, T Function() create) {
  try {
    return create();
    // Constructor admission failures must become canonical decoder failures.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}
