import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'presentation_commit.dart';

/// Maximum opaque routes retained for one root mounted session.
///
/// This is an SDK-side state bound. It is not a canonical artifact field.
const int kMaximumMeasurementRuntimeRouteCount = 1024;

/// Maximum distinct successful presentations retained by one capture session.
const int kMaximumMeasurementPresentedPointCount = 1024;

/// Maximum presented facts that may retain interaction counters.
const int kMaximumMeasurementInteractionCounterCount = 256;

/// Saturation cap for every retained counter in one capture session.
const int kMaximumMeasurementCounterValue = 65535;

/// Maximum distinct aggregate missingness states declared by the frame wire.
const int kMaximumMeasurementMissingnessEntryCount = 256;

/// Stable names for the dependency-independent SDK consumer entrypoints.
abstract final class MeasurementRuntimeEntrypoints {
  /// Resolves one artifact-local opaque token before Measurement capture.
  static const resolveOpaqueRouteV1 = 'sdk.measurement.resolveOpaqueRouteV1';

  /// Produces one byte-stable measurement fact frame.
  static const emitFactFrameV1 = 'sdk.measurement.emitFactFrameV1';
}

/// Exact mounted artifact context used to resolve a noncanonical route token.
///
/// This contains only published artifact coordinates. It deliberately omits
/// target and any subject or customer identity.
final class MeasurementMountedArtifactContext {
  /// Creates the mounted context already resolved by the delivery owner.
  const MeasurementMountedArtifactContext({
    required this.artifactGraphHash,
    required this.artifactId,
    required this.artifactOccurrenceEdgeToken,
    required this.measurementManifestHash,
    required this.surfaceRevisionId,
  });

  /// Exact graph selected for this mounted artifact occurrence.
  final CanonicalDigest artifactGraphHash;

  /// Exact artifact selected for this mounted occurrence.
  final ArtifactId artifactId;

  /// Exact graph-local occurrence edge selected by the delivery owner.
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;

  /// Exact complete measurement manifest selected for this mount.
  final CanonicalDigest measurementManifestHash;

  /// Exact published surface revision selected for this mount.
  final SurfaceRevisionId surfaceRevisionId;

  /// Returns a changed mounted context for fixture and boundary testing.
  MeasurementMountedArtifactContext copyWith({
    CanonicalDigest? artifactGraphHash,
    ArtifactId? artifactId,
    ArtifactOccurrenceEdgeToken? artifactOccurrenceEdgeToken,
    CanonicalDigest? measurementManifestHash,
    SurfaceRevisionId? surfaceRevisionId,
  }) =>
      MeasurementMountedArtifactContext(
        artifactGraphHash: artifactGraphHash ?? this.artifactGraphHash,
        artifactId: artifactId ?? this.artifactId,
        artifactOccurrenceEdgeToken:
            artifactOccurrenceEdgeToken ?? this.artifactOccurrenceEdgeToken,
        measurementManifestHash:
            measurementManifestHash ?? this.measurementManifestHash,
        surfaceRevisionId: surfaceRevisionId ?? this.surfaceRevisionId,
      );

  @override
  bool operator ==(Object other) =>
      other is MeasurementMountedArtifactContext &&
      artifactGraphHash == other.artifactGraphHash &&
      artifactId == other.artifactId &&
      artifactOccurrenceEdgeToken == other.artifactOccurrenceEdgeToken &&
      measurementManifestHash == other.measurementManifestHash &&
      surfaceRevisionId == other.surfaceRevisionId;

  @override
  int get hashCode => Object.hash(
        artifactGraphHash,
        artifactId,
        artifactOccurrenceEdgeToken,
        measurementManifestHash,
        surfaceRevisionId,
      );
}

/// Opaque, artifact-local carrier delivered to the SDK before capture.
///
/// Its spelling is not durable identity, is never serialized by this library,
/// and is intentionally unrelated to author event names.
final class OpaqueMeasurementEventSlotToken {
  /// Creates one bounded opaque carrier without normalizing its spelling.
  OpaqueMeasurementEventSlotToken(String value) : _value = _requireValue(value);

  final String _value;

  static String _requireValue(String value) {
    if (value.isEmpty || value.length > 256) {
      throw ArgumentError.value(
        value,
        'value',
        'Expected a non-empty opaque token of at most 256 code units',
      );
    }
    return value;
  }

  /// Returns the canonical binding fingerprint outside the capture hot path.
  ///
  /// The raw carrier remains private and is never serialized by this SDK. Host
  /// setup may derive this fingerprint while constructing a route table; the
  /// synchronous capture sub-entry receives only a pre-resolved handle.
  OpaqueMeasurementRouteTokenV1 get publicationBindingToken =>
      OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(_value);

  @override
  bool operator ==(Object other) =>
      other is OpaqueMeasurementEventSlotToken && _value == other._value;

  @override
  int get hashCode => _value.hashCode;
}

/// Minimal Measurement-owned identity required after route resolution.
final class MeasurementRuntimeRouteDeclaration {
  /// Creates one pre-resolvable route declaration.
  const MeasurementRuntimeRouteDeclaration({
    required this.token,
    required this.occurrenceId,
    required this.lineageId,
  });

  /// Artifact-local carrier selected by the delivery owner.
  final OpaqueMeasurementEventSlotToken token;

  /// Exact point occurrence identity.
  final CanonicalDigest occurrenceId;

  /// Exact durable continuity identity.
  final PointLineageId lineageId;
}

/// Immutable bounded resolver for one root surface session.
///
/// Resolution occurs before the capture sub-entry. Its returned handle cannot
/// be recreated by a caller and carries no customer argument or event name.
final class MeasurementRuntimeRouteTable {
  /// Builds the fixed-size resolver table outside the capture sub-entry.
  MeasurementRuntimeRouteTable({
    required this.mountedArtifactContext,
    required List<MeasurementRuntimeRouteDeclaration> routes,
    this.maximumRouteCount = kMaximumMeasurementRuntimeRouteCount,
  }) : _owner = Object() {
    _initializeDeclaredRoutes(routes);
  }

  /// Builds one route table from an accepted publication binding's complete
  /// route closure.
  ///
  /// The binding closes the complete published route set before this table is
  /// created. The raw carrier arrives only with a later host event, at which
  /// point [resolveOpaqueRoute] parses its encoded edge and performs the exact
  /// fingerprint lookup. This prevents a host from having to enumerate
  /// future event carriers before it receives them.
  factory MeasurementRuntimeRouteTable.fromPublicationBinding({
    required MeasurementMountedArtifactContext mountedArtifactContext,
    required MeasurementPublicationBindingV1 binding,
    int maximumRouteCount = kMaximumMeasurementRuntimeRouteCount,
  }) {
    final table = MeasurementRuntimeRouteTable._(
      mountedArtifactContext: mountedArtifactContext,
      maximumRouteCount: maximumRouteCount,
    );
    table._initializePublicationRoutes(binding);
    return table;
  }

  MeasurementRuntimeRouteTable._({
    required this.mountedArtifactContext,
    required this.maximumRouteCount,
  }) : _owner = Object();

  /// Root context whose complete binding closure this table accepts.
  final MeasurementMountedArtifactContext mountedArtifactContext;

  /// Explicit state bound for this immutable resolver table.
  final int maximumRouteCount;

  final Object _owner;
  late final Map<OpaqueMeasurementEventSlotToken,
      MeasurementCaptureRouteHandle>? _routesByToken;
  late final Map<String, Map<String, MeasurementCaptureRouteHandle>>?
      _routesByPublicationEdge;
  late final List<MeasurementCaptureRouteHandle> _routes;

  void _initializeDeclaredRoutes(
    List<MeasurementRuntimeRouteDeclaration> routes,
  ) {
    if (maximumRouteCount <= 0 ||
        maximumRouteCount > kMaximumMeasurementRuntimeRouteCount ||
        routes.length > maximumRouteCount) {
      throw ArgumentError.value(
        routes.length,
        'routes',
        'Expected at most $maximumRouteCount opaque routes',
      );
    }

    final byToken =
        <OpaqueMeasurementEventSlotToken, MeasurementCaptureRouteHandle>{};
    final handles = <MeasurementCaptureRouteHandle>[];
    final occurrenceIds = <CanonicalDigest>{};
    final lineageIds = <PointLineageId>{};
    for (var index = 0; index < routes.length; index++) {
      final route = routes[index];
      if (!occurrenceIds.add(route.occurrenceId)) {
        throw ArgumentError.value(
          route.occurrenceId,
          'routes',
          'Each route must resolve one distinct occurrence',
        );
      }
      if (!lineageIds.add(route.lineageId)) {
        throw ArgumentError.value(
          route.lineageId,
          'routes',
          'Each current route must claim one distinct lineage',
        );
      }
      final handle = MeasurementCaptureRouteHandle._(
        _owner,
        index,
        occurrenceId: route.occurrenceId,
        lineageId: route.lineageId,
      );
      if (byToken.containsKey(route.token)) {
        throw ArgumentError.value(
          route.token,
          'routes',
          'Opaque route tokens must be unique in one mounted artifact',
        );
      }
      byToken[route.token] = handle;
      handles.add(handle);
    }
    _routesByToken = Map.unmodifiable(byToken);
    _routesByPublicationEdge = null;
    _routes = List.unmodifiable(handles);
  }

  void _initializePublicationRoutes(MeasurementPublicationBindingV1 binding) {
    if (maximumRouteCount <= 0 ||
        maximumRouteCount > kMaximumMeasurementRuntimeRouteCount) {
      throw ArgumentError.value(
        maximumRouteCount,
        'maximumRouteCount',
        'Expected a positive bounded route count',
      );
    }

    final routesByEdge = <String, Map<String, MeasurementCaptureRouteHandle>>{
      for (final edge in binding.exactArtifactGraph.occurrenceEdges)
        edge.edgeToken.value: <String, MeasurementCaptureRouteHandle>{},
    };
    final handles = <MeasurementCaptureRouteHandle>[];
    final occurrenceIds = <CanonicalDigest>{};
    final lineageIds = <PointLineageId>{};
    final fullFingerprints = <String>{};
    final mountedEdges = <String>{};
    var routeCount = 0;
    for (final mountedRoutes in binding.mountedArtifactRoutes) {
      final edge = mountedRoutes.artifactOccurrenceEdgeToken.value;
      final routesForEdge = routesByEdge[edge];
      if (routesForEdge == null || !mountedEdges.add(edge)) {
        throw ArgumentError.value(
          mountedRoutes.artifactOccurrenceEdgeToken,
          'binding.mountedArtifactRoutes',
          'Each route set must name one distinct admitted graph edge',
        );
      }
      routeCount += mountedRoutes.routes.length;
      if (routeCount > maximumRouteCount) {
        throw ArgumentError.value(
          routeCount,
          'binding.mountedArtifactRoutes',
          'Expected at most $maximumRouteCount opaque routes',
        );
      }
      for (final route in mountedRoutes.routes) {
        if (!occurrenceIds.add(route.occurrenceId)) {
          throw ArgumentError.value(
            route.occurrenceId,
            'binding.mountedArtifactRoutes',
            'Each route must resolve one distinct occurrence',
          );
        }
        if (!lineageIds.add(route.lineageId)) {
          throw ArgumentError.value(
            route.lineageId,
            'binding.mountedArtifactRoutes',
            'Each current route must claim one distinct lineage',
          );
        }
        final fingerprint = route.opaqueRouteToken.fingerprint.hex;
        if (!fullFingerprints.add(fingerprint) ||
            routesForEdge.containsKey(fingerprint)) {
          throw ArgumentError.value(
            route.opaqueRouteToken,
            'binding.mountedArtifactRoutes',
            'Opaque route fingerprints must be unique in one binding',
          );
        }
        final handle = MeasurementCaptureRouteHandle._(
          _owner,
          handles.length,
          occurrenceId: route.occurrenceId,
          lineageId: route.lineageId,
        );
        routesForEdge[fingerprint] = handle;
        handles.add(handle);
      }
    }
    _routesByToken = null;
    _routesByPublicationEdge =
        Map<String, Map<String, MeasurementCaptureRouteHandle>>.unmodifiable({
      for (final entry in routesByEdge.entries)
        entry.key: Map<String, MeasurementCaptureRouteHandle>.unmodifiable(
          entry.value,
        ),
    });
    _routes = List.unmodifiable(handles);
  }

  int get _routeCount => _routes.length;

  /// Exact pre-resolved routes in their fixed worker registration order.
  ///
  /// The list is immutable and construction-plane only. Callback code receives
  /// one opaque [MeasurementCaptureRouteHandle], never this table.
  @internal
  List<MeasurementCaptureRouteHandle> get routes => _routes;

  /// Resolves a route only when [context] matches this mounted artifact exactly.
  ///
  /// The returned handle is passed unchanged to the synchronous capture
  /// sub-entry; this method must not be called from that sub-entry.
  MeasurementCaptureRouteHandle? resolveOpaqueRoute({
    required MeasurementMountedArtifactContext context,
    required OpaqueMeasurementEventSlotToken token,
  }) {
    if (context != mountedArtifactContext) return null;
    final routesByToken = _routesByToken;
    if (routesByToken != null) return routesByToken[token];

    try {
      final carrier = MeasurementPublicationRouteCarrierV1.parse(token._value);
      final routesForEdge =
          _routesByPublicationEdge![carrier.artifactOccurrenceEdgeToken.value];
      if (routesForEdge == null) return null;
      return routesForEdge[OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(
        token._value,
      ).fingerprint.hex];
    } on ArgumentError {
      return null;
    }
  }
}

/// Opaque pre-resolved route accepted by one capture session.
final class MeasurementCaptureRouteHandle {
  const MeasurementCaptureRouteHandle._(
    this._owner,
    this._index, {
    required this.occurrenceId,
    required this.lineageId,
  });

  final Object _owner;
  final int _index;

  /// Bounded worker-route slot selected during exact pre-mount resolution.
  ///
  /// This is internal construction-plane data. Hosts pass it only through a
  /// prebound capture edge; they never derive it from an event carrier.
  @internal
  int get routeIndex => _index;

  /// Exact occurrence selected before the capture sub-entry.
  final CanonicalDigest occurrenceId;

  /// Exact lineage selected before the capture sub-entry.
  final PointLineageId lineageId;
}

/// Bounded frame limits for one capture session.
final class MeasurementFactFrameBounds {
  /// Creates bounds for every variable-size runtime frame member.
  MeasurementFactFrameBounds({
    required this.maximumCounterValue,
    required this.maximumPresentedPoints,
    required this.maximumInteractionCounters,
    required this.maximumMissingnessEntries,
  }) {
    if (maximumCounterValue <= 0 ||
        maximumCounterValue > kMaximumMeasurementCounterValue ||
        maximumPresentedPoints <= 0 ||
        maximumPresentedPoints > kMaximumMeasurementPresentedPointCount ||
        maximumInteractionCounters < 0 ||
        maximumInteractionCounters >
            kMaximumMeasurementInteractionCounterCount ||
        maximumMissingnessEntries < 0 ||
        maximumMissingnessEntries > kMaximumMeasurementMissingnessEntryCount) {
      throw ArgumentError(
        'Frame bounds must remain within the closed capture policy limits',
      );
    }
  }

  /// Saturation cap for each count retained in this frame.
  final int maximumCounterValue;

  /// Maximum distinct successful presentations retained in this frame.
  final int maximumPresentedPoints;

  /// Maximum retained interaction counters across presented facts.
  final int maximumInteractionCounters;

  /// Maximum distinct missingness states retained in this frame.
  final int maximumMissingnessEntries;
}

/// Opaque session nonce retained only for frame idempotency.
final class MeasurementCaptureSessionNonce {
  /// Creates one bounded nonce without interpreting it as customer identity.
  MeasurementCaptureSessionNonce(String value) : _value = _requireValue(value);

  final String _value;

  static String _requireValue(String value) {
    if (value.isEmpty ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'Expected a non-empty canonical capture nonce of at most 128 code units',
      );
    }
    return value;
  }
}

/// Result of one synchronous capture-sub-entry update.
enum MeasurementCaptureWriteDisposition {
  /// The bounded route fact was updated.
  recorded,

  /// The route fact bound was full and the dropped count was retained.
  truncated,

  /// The session is terminal and accepts no later updates.
  finalized,
}

/// Missingness that is retained explicitly rather than fabricated as zero.
enum MeasurementCaptureMissingness {
  /// A source fact could not be produced by the owning source.
  sourceUnavailable(ObservationState.sourceUnavailable),

  /// Transport or handoff could not retain the complete frame relation.
  transportTruncated(ObservationState.transportTruncated);

  const MeasurementCaptureMissingness(this.observationState);

  /// Exact observation state represented by this fact-frame missingness.
  final ObservationState observationState;

  /// Stable fact-frame spelling.
  String get wireName => observationState.wireName;
}

/// Result of recording one bounded missingness state.
enum MeasurementMissingnessWriteDisposition {
  /// The state was retained or its bounded count incremented.
  recorded,

  /// The distinct-state budget was exhausted, so no false zero was written.
  rejectedAtBound,

  /// The frame is already final.
  finalized,
}

/// Immutable frame returned by a pending checkpoint or final teardown.
final class MeasurementFactFrame {
  /// Takes ownership of fresh canonical bytes built inside this library.
  ///
  /// The private construction path receives only the new [Uint8List] returned
  /// by [CanonicalJsonCodec.encode]. The public getter remains a defensive
  /// copy, so callers cannot mutate retry or ingest state.
  MeasurementFactFrame._(Uint8List ownedCanonicalBytes)
      : _canonicalBytes = ownedCanonicalBytes;

  final Uint8List _canonicalBytes;
  late final MeasurementFactFrameV1 _validatedIngestFrameV1 =
      MeasurementFactFrameV1.fromCanonicalBytes(_canonicalBytes);

  /// Defensive copy of the canonical frame bytes for ingest or retry.
  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);

  /// Returns the shared, validated ingest frame retained for this frame.
  ///
  /// This internal seam keeps the raw frame digest and strict validation in the
  /// shared contract. Repeated transport attempts reuse the same validated
  /// frame instead of reimplementing frame JSON or hashing in the SDK.
  @internal
  MeasurementFactFrameV1 get validatedIngestFrameV1 => _validatedIngestFrameV1;
}

/// Test-visible accounting for state owned by one runtime capture session.
///
/// This is deliberately structural rather than a heap-size estimate: Dart and
/// the host allocator own actual collection and RSS accounting. It reports the
/// variable-size capture buffers and route-table reference that finality can
/// release.
final class MeasurementRuntimeCaptureRetainedOwnership {
  const MeasurementRuntimeCaptureRetainedOwnership._({
    required this.retainedSnapshotByteCount,
    required this.retainedFactSlotCount,
    required this.retainedMissingnessCounterCount,
    required this.retainsRouteTable,
  });

  /// Exact canonical bytes retained for the current idempotent emission.
  final int retainedSnapshotByteCount;

  /// Mutable fact slots this session still owns.
  final int retainedFactSlotCount;

  /// Mutable missingness counters this session still owns.
  final int retainedMissingnessCounterCount;

  /// Whether this session still owns the shared immutable route table.
  final bool retainsRouteTable;
}

/// Bounded, subjectless runtime accumulator for one mounted artifact session.
///
/// This is dormant SDK-internal replacement-plane state. It has no transport,
/// timer, scheduling, tree, host lifecycle, or legacy analytics integration.
final class MeasurementRuntimeCaptureSession
    implements MeasurementPresentationCaptureSink {
  /// Creates one fixed-capacity capture session.
  MeasurementRuntimeCaptureSession({
    required MeasurementFactFrameBounds bounds,
    required MeasurementCaptureSessionNonce captureSessionNonce,
    required ExactMeasurementPublicationContextRefV1 publicationContextRef,
    required MeasurementRuntimeRouteTable routeTable,
    required int sequence,
  }) : this._(
          bounds: bounds,
          captureSessionNonce: captureSessionNonce,
          publicationContextRef: publicationContextRef,
          routeTable: routeTable,
          sequence: sequence,
          successfulRootPresentation: false,
        );

  /// Creates a test-only session already admitted through first paint.
  ///
  /// Production code must create the ordinary constructor and receive the
  /// successful-paint fact through [recordSuccessfulPresentation]. The narrow
  /// test seam keeps capture-buffer tests independent of Flutter rendering;
  /// it is not exported as a host integration API.
  MeasurementRuntimeCaptureSession.testOnlySuccessfulPresentation({
    required MeasurementFactFrameBounds bounds,
    required MeasurementCaptureSessionNonce captureSessionNonce,
    required ExactMeasurementPublicationContextRefV1 publicationContextRef,
    required MeasurementRuntimeRouteTable routeTable,
    required int sequence,
  }) : this._(
          bounds: bounds,
          captureSessionNonce: captureSessionNonce,
          publicationContextRef: publicationContextRef,
          routeTable: routeTable,
          sequence: sequence,
          successfulRootPresentation: true,
        );

  MeasurementRuntimeCaptureSession._({
    required this.bounds,
    required this.captureSessionNonce,
    required this.publicationContextRef,
    required MeasurementRuntimeRouteTable routeTable,
    required int sequence,
    required bool successfulRootPresentation,
  })  : _routeTable = routeTable,
        _nextSequence = sequence,
        _slotStates = Uint32List(routeTable._routeCount),
        _missingnessCounts = List<int>.filled(
          MeasurementCaptureMissingness.values.length,
          0,
          growable: false,
        ) {
    _successfulRootPresentation = successfulRootPresentation;
    if (sequence <= 0 || sequence > kMaximumPortableJsonInteger) {
      throw ArgumentError.value(
        sequence,
        'sequence',
        'Expected a positive portable sequence',
      );
    }
    final mounted = routeTable.mountedArtifactContext;
    if (publicationContextRef.surfaceRevisionId != mounted.surfaceRevisionId ||
        publicationContextRef.artifactGraphHash != mounted.artifactGraphHash ||
        publicationContextRef.measurementManifestHash !=
            mounted.measurementManifestHash) {
      throw ArgumentError(
        'The capture context must join the exact mounted publication context',
      );
    }
  }

  /// Explicit frame budget retained by this session.
  final MeasurementFactFrameBounds bounds;

  /// Opaque retry coordinate. It is not subject identity.
  final MeasurementCaptureSessionNonce captureSessionNonce;

  /// Exact publication context selected for this mounted capture session.
  ///
  /// The revision/graph/manifest triple is retained in the route table, but
  /// cannot identify which immutable publication supplied it. The
  /// resolver-owned context therefore travels through the final frame
  /// unchanged.
  final ExactMeasurementPublicationContextRefV1 publicationContextRef;

  /// Sequence that the next emitted snapshot will carry.
  int get sequence => _nextSequence;

  MeasurementRuntimeRouteTable? _routeTable;
  Uint32List? _slotStates;
  List<int>? _missingnessCounts;
  int _presentedPointCount = 0;
  int _interactionCounterCount = 0;
  int _droppedPresentedPointCount = 0;
  int _droppedInteractionCounterCount = 0;
  int _distinctMissingnessCount = 0;
  int _nextSequence;
  MeasurementFactFrame? _checkpointFrame;
  MeasurementFactFrame? _finalFrame;
  bool _successfulRootPresentation = false;

  /// Direct, deterministic retained-state accounting for lifecycle tests.
  @visibleForTesting
  MeasurementRuntimeCaptureRetainedOwnership get debugRetainedOwnership =>
      MeasurementRuntimeCaptureRetainedOwnership._(
        retainedSnapshotByteCount:
            (_finalFrame ?? _checkpointFrame)?._canonicalBytes.length ?? 0,
        retainedFactSlotCount: _slotStates?.length ?? 0,
        retainedMissingnessCounterCount: _missingnessCounts?.length ?? 0,
        retainsRouteTable: _routeTable != null,
      );

  /// O(1) handle lookup and one bounded interaction update.
  MeasurementCaptureWriteDisposition recordInteraction(
    MeasurementCaptureRouteHandle route,
  ) =>
      _record(route, true);

  /// O(1) handle lookup and one bounded presentation update.
  MeasurementCaptureWriteDisposition recordPresentation(
    MeasurementCaptureRouteHandle route,
  ) =>
      _record(route, false);

  MeasurementCaptureWriteDisposition _record(
    MeasurementCaptureRouteHandle route,
    bool recordsInteraction,
  ) {
    if (_finalFrame != null) {
      return MeasurementCaptureWriteDisposition.finalized;
    }
    final routeTable = _routeTable;
    final slotStates = _slotStates;
    if (routeTable == null || slotStates == null) {
      throw StateError('Active capture state is unavailable');
    }
    if (!identical(route._owner, routeTable._owner)) {
      throw ArgumentError.value(
        route,
        'route',
        'Route belongs to another table',
      );
    }
    final index = route._index;
    final originalSlotState = slotStates[index];
    var slotState = originalSlotState;
    _beginNewSnapshotAfterCheckpoint();
    if ((slotState & _measurementSlotPresentedFlag) == 0) {
      if (_presentedPointCount == bounds.maximumPresentedPoints) {
        if ((slotState & _measurementSlotDroppedAtPresentationFlag) == 0) {
          slotStates[index] =
              slotState | _measurementSlotDroppedAtPresentationFlag;
          _droppedPresentedPointCount = _incrementBounded(
            _droppedPresentedPointCount,
          );
        }
        return MeasurementCaptureWriteDisposition.truncated;
      }
      slotState |= _measurementSlotPresentedFlag;
      _presentedPointCount += 1;
      if (_interactionCounterCount == bounds.maximumInteractionCounters) {
        slotState |= _measurementSlotInteractionCounterTruncatedFlag;
        _droppedInteractionCounterCount = _incrementBounded(
          _droppedInteractionCounterCount,
        );
      } else {
        slotState |= _measurementSlotHasInteractionCounterFlag;
        _interactionCounterCount += 1;
      }
    }
    if (recordsInteraction &&
        (slotState & _measurementSlotHasInteractionCounterFlag) != 0) {
      final interactionCount = slotState & _measurementSlotInteractionCountMask;
      if (interactionCount < bounds.maximumCounterValue) {
        final nextInteractionCount = interactionCount + 1;
        slotState = (slotState & ~_measurementSlotInteractionCountMask) |
            nextInteractionCount;
        if (nextInteractionCount == bounds.maximumCounterValue) {
          slotState |= _measurementSlotInteractionSaturatedFlag;
        }
      }
    }
    if (slotState != originalSlotState) slotStates[index] = slotState;
    return (slotState & _measurementSlotHasInteractionCounterFlag) != 0
        ? MeasurementCaptureWriteDisposition.recorded
        : MeasurementCaptureWriteDisposition.truncated;
  }

  /// Records bounded missingness outside the callback capture sub-entry.
  MeasurementMissingnessWriteDisposition recordMissingness(
    MeasurementCaptureMissingness missingness,
  ) {
    if (_finalFrame != null) {
      return MeasurementMissingnessWriteDisposition.finalized;
    }
    final missingnessCounts = _missingnessCounts;
    if (missingnessCounts == null) {
      throw StateError('Active capture state is unavailable');
    }
    _beginNewSnapshotAfterCheckpoint();
    final index = missingness.index;
    if (missingnessCounts[index] == 0 &&
        _distinctMissingnessCount == bounds.maximumMissingnessEntries) {
      return MeasurementMissingnessWriteDisposition.rejectedAtBound;
    }
    if (missingnessCounts[index] == 0) _distinctMissingnessCount += 1;
    missingnessCounts[index] = _incrementBounded(missingnessCounts[index]);
    return MeasurementMissingnessWriteDisposition.recorded;
  }

  /// Records the one exact successful first-paint fact for this session.
  ///
  /// The route hook is the only production caller. It gives the capture frame a
  /// bounded, subjectless proof marker without accepting a timestamp, widget
  /// identity, route token, customer argument, or population scope from the
  /// host. A fact for any other mounted context fails closed.
  @override
  void recordSuccessfulPresentation(
    MeasurementSuccessfulPresentationFact fact,
  ) {
    if (_finalFrame != null) {
      throw StateError('A finalized capture session cannot admit first paint');
    }
    final routeTable = _routeTable;
    if (routeTable == null ||
        !_sameMountedPresentation(
          routeTable.mountedArtifactContext,
          fact.context.publishedSurfaceRevision,
        )) {
      throw ArgumentError.value(
        fact,
        'fact',
        'Successful paint must match the exact mounted publication context',
      );
    }
    _beginNewSnapshotAfterCheckpoint();
    _successfulRootPresentation = true;
  }

  /// Emits one nonterminal cumulative frame for retry by the owning host.
  ///
  /// Repeated checkpoints without a later record return this exact immutable
  /// frame. Once recording resumes, the host retains this returned result for
  /// any retry while this session advances to a higher sequence.
  MeasurementFactFrame checkpoint() {
    if (_finalFrame != null) {
      throw StateError('A finalized capture session cannot checkpoint');
    }
    final existing = _checkpointFrame;
    if (existing != null) return existing;
    final checkpoint = _buildFrame(isFinal: false);
    _checkpointFrame = checkpoint;
    return checkpoint;
  }

  /// Finalizes current state at the owning lifecycle's teardown boundary.
  MeasurementFactFrame teardown() {
    final existing = _finalFrame;
    if (existing != null) return existing;
    _beginNewSnapshotAfterCheckpoint();
    final frame = _buildFrame(isFinal: true);
    _finalFrame = frame;
    _releaseMutableState();
    return frame;
  }

  MeasurementFactFrame _buildFrame({required bool isFinal}) {
    final routeTable = _routeTable;
    final slotStates = _slotStates;
    final missingnessCounts = _missingnessCounts;
    if (routeTable == null || slotStates == null || missingnessCounts == null) {
      throw StateError('Active capture state is unavailable');
    }
    if (!_successfulRootPresentation) {
      throw StateError(
        'A fact frame requires an exact successful first-paint commitment',
      );
    }

    final facts = <_MeasurementSerializedFact>[];
    for (var index = 0; index < slotStates.length; index++) {
      final slotState = slotStates[index];
      if ((slotState & _measurementSlotPresentedFlag) == 0) continue;
      final route = routeTable._routes[index];
      facts.add(
        _MeasurementSerializedFact(
          occurrenceId: route.occurrenceId.hex,
          lineageId: route.lineageId.value,
          interactionState: _interactionStateForSlotState(slotState),
          interactionCount: _interactionCountJsonForSlotState(slotState),
        ),
      );
    }
    facts.sort((left, right) => left.identity.compareTo(right.identity));
    final missingness = <Map<String, Object?>>[];
    for (final value in MeasurementCaptureMissingness.values) {
      final count = missingnessCounts[value.index];
      if (count == 0) continue;
      missingness.add({'count': count, 'state': value.wireName});
    }
    return MeasurementFactFrame._(
      CanonicalJsonCodec.encode({
        'bounds': {
          'maximumCounterValue': bounds.maximumCounterValue,
          'maximumInteractionCounters': bounds.maximumInteractionCounters,
          'maximumMissingnessEntries': bounds.maximumMissingnessEntries,
          'maximumPresentedPoints': bounds.maximumPresentedPoints,
        },
        'captureSessionNonce': captureSessionNonce._value,
        'facts': [for (final fact in facts) fact.toJson()],
        'finality': {'kind': isFinal ? 'final' : 'pending'},
        'kind': 'measurementFactFrame',
        'missingness': missingness,
        'publishedContext': publicationContextRef.toJson(),
        'retryPolicy': const {'kind': 'byteIdenticalSameSequence'},
        'rootPresentation': const {'kind': 'successfulFirstPaint'},
        'schemaVersion': kMeasurementSchemaVersion,
        'sequence': _nextSequence,
        'truncation': {
          'interactionCounters': {
            'droppedCount': _droppedInteractionCounterCount,
            'truncated': _droppedInteractionCounterCount > 0,
          },
          'presentedPoints': {
            'droppedCount': _droppedPresentedPointCount,
            'truncated': _droppedPresentedPointCount > 0,
          },
        },
      }),
    );
  }

  void _beginNewSnapshotAfterCheckpoint() {
    if (_checkpointFrame == null) return;
    if (_nextSequence == kMaximumPortableJsonInteger) {
      throw StateError('Cannot advance a maximum portable capture sequence');
    }
    _checkpointFrame = null;
    _nextSequence += 1;
  }

  void _releaseMutableState() {
    _routeTable = null;
    _slotStates = null;
    _missingnessCounts = null;
  }

  int _incrementBounded(int value) =>
      value < bounds.maximumCounterValue ? value + 1 : value;
}

bool _sameMountedPresentation(
  MeasurementMountedArtifactContext mounted,
  PublishedSurfaceRevisionV1 successfulPresentation,
) =>
    mounted.surfaceRevisionId == successfulPresentation.revisionId &&
    mounted.artifactGraphHash == successfulPresentation.artifactGraphHash &&
    mounted.measurementManifestHash ==
        successfulPresentation.measurementManifestHash;

const int _measurementSlotInteractionCountMask = 0xffff;
const int _measurementSlotPresentedFlag = 1 << 16;
const int _measurementSlotDroppedAtPresentationFlag = 1 << 17;
const int _measurementSlotHasInteractionCounterFlag = 1 << 18;
const int _measurementSlotInteractionCounterTruncatedFlag = 1 << 19;
const int _measurementSlotInteractionSaturatedFlag = 1 << 20;

MeasurementFactInteractionState _interactionStateForSlotState(
  int slotState,
) {
  if ((slotState & _measurementSlotInteractionCounterTruncatedFlag) != 0) {
    return MeasurementFactInteractionState.transportTruncated;
  }
  if ((slotState & _measurementSlotInteractionSaturatedFlag) != 0) {
    return MeasurementFactInteractionState.observedCapped;
  }
  if ((slotState & _measurementSlotInteractionCountMask) == 0) {
    return MeasurementFactInteractionState.observedZero;
  }
  return MeasurementFactInteractionState.observedValue;
}

Map<String, Object?>? _interactionCountJsonForSlotState(int slotState) =>
    (slotState & _measurementSlotHasInteractionCounterFlag) != 0
        ? {
            'saturated':
                (slotState & _measurementSlotInteractionSaturatedFlag) != 0,
            'value': slotState & _measurementSlotInteractionCountMask,
          }
        : null;

final class _MeasurementSerializedFact {
  const _MeasurementSerializedFact({
    required this.occurrenceId,
    required this.lineageId,
    required this.interactionState,
    required this.interactionCount,
  });

  final String occurrenceId;
  final String lineageId;
  final MeasurementFactInteractionState interactionState;
  final Map<String, Object?>? interactionCount;

  String get identity => '$occurrenceId\u0000$lineageId';

  Map<String, Object?> toJson() => {
        if (interactionCount != null) 'interactionCount': interactionCount,
        'interactionState': interactionState.wireName,
        'lineageId': lineageId,
        'occurrenceId': occurrenceId,
      };
}
