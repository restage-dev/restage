import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'bundled_measurement_publication_binding_read_port.dart';
import 'measurement_runtime_capture.dart';

/// Fail-closed result of resolving one exact publication binding for a mount.
final class MeasurementPublicationBindingRuntimeResolution {
  const MeasurementPublicationBindingRuntimeResolution._({
    required this.readResult,
    required this.routeTable,
    required this.resolvedMount,
  });

  /// Exact asynchronous binding-read outcome.
  ///
  /// This is the complete closed result returned by the only external
  /// authority seam. A route table or resolved mount is available only for an
  /// accepted result whose remaining mounted joins also close below.
  final MeasurementPublicationBindingReadResult readResult;

  /// Route table only when [readResult] accepted every exact join.
  final MeasurementRuntimeRouteTable? routeTable;

  /// Exact mount authority emitted only after every resolution closure holds.
  ///
  /// This is the sole input from which a host may derive its capture context.
  /// Its private constructor prevents a caller from presenting raw binding
  /// fields as an already-attested mount.
  final MeasurementPublicationBindingRuntimeResolvedMount? resolvedMount;

  /// Whether one exact binding produced a usable route table.
  bool get isAccepted =>
      readResult is MeasurementPublicationBindingReadAccepted &&
      routeTable != null &&
      resolvedMount != null;
}

/// Resolution-owned authority for one exact attested root surface mount.
///
/// A value is created only by [MeasurementPublicationBindingRuntimeResolver]
/// after an accepted exact read, binding-reference and registered-attestation
/// agreement, mounted-context closure, and exact opaque-route closure all
/// succeed.
final class MeasurementPublicationBindingRuntimeResolvedMount {
  const MeasurementPublicationBindingRuntimeResolvedMount._({
    required this.publicationContextRef,
    required this.mountedArtifactContext,
    required this.publishedSurfaceRevision,
    required this.minimumMeasurementClient,
    required this.measurementSchemaVersion,
  });

  /// Exact root artifact coordinates accepted for this surface session.
  final MeasurementMountedArtifactContext mountedArtifactContext;

  /// Exact immutable publication context retained through capture and ingest.
  ///
  /// This is not reconstructible from the revision/graph/manifest triple:
  /// two immutable publications may attest that same triple. Keeping the
  /// resolver-owned context prevents a capture session from inferring a
  /// current or alternate publication binding.
  final ExactMeasurementPublicationContextRefV1 publicationContextRef;

  /// Exact revision accepted for this mount.
  ///
  /// Hosts that need the revision for a presentation hook take it from this
  /// resolver-owned value rather than reconstructing a parallel raw context.
  final PublishedSurfaceRevisionV1 publishedSurfaceRevision;

  /// Exact capability floor sealed by the accepted binding.
  final int minimumMeasurementClient;

  /// Exact Measurement schema version sealed by the accepted binding.
  final int measurementSchemaVersion;
}

/// Builds one root-session route table only from an exact asynchronous binding
/// read.
///
/// This resolver has no publication-selection operation: its only request is
/// the supplied immutable [MeasurementPublicationBindingReferenceV1]. The
/// accepted binding closes the route fingerprints; a later host event supplies
/// its raw carrier to the resolver-owned route table outside the capture hot
/// path.
abstract final class MeasurementPublicationBindingRuntimeResolver {
  /// Resolves one bundled generated surface publication closure without a host binding handle.
  ///
  /// The bundled target-profile loader fixes the target, registry, and verified
  /// bundle bytes before it exposes [bindingReadPort]. The host supplies only
  /// the exact generated publication locator emitted for its mounted closure; accepted
  /// reference bytes come exclusively from the immutable bundled entry.
  static Future<MeasurementPublicationBindingRuntimeResolution>
      resolveBundledExactGeneratedPublicationLocator({
    required MeasurementBundledGeneratedPublicationLocatorV1
        generatedPublicationLocator,
    required BundledMeasurementPublicationBindingReadPort bindingReadPort,
  }) async {
    late final MeasurementPublicationBindingReadResult readResult;
    try {
      readResult =
          await bindingReadPort.resolveExactGeneratedPublicationLocator(
        generatedPublicationLocator,
      );
    } on Object {
      return _rejected(
        const MeasurementPublicationBindingTransportUnavailable(),
      );
    }

    return switch (readResult) {
      MeasurementPublicationBindingReadAccepted() => _resolveReadResult(
          bindingReference: readResult.reference,
          readResult: readResult,
        ),
      _ => _rejected(readResult),
    };
  }

  /// Requests and resolves a separately published binding by its exact handle.
  ///
  /// The read port owns I/O and returns a closed result for every expected
  /// unavailable or invalid outcome. An unexpected port error is also treated
  /// as transport unavailability; this resolver never selects another binding
  /// or falls back to an active revision.
  static Future<MeasurementPublicationBindingRuntimeResolution>
      requestAndResolveExact({
    required MeasurementPublicationBindingReferenceV1 bindingReference,
    required MeasurementPublicationBindingReadPort bindingReadPort,
  }) async {
    late final MeasurementPublicationBindingReadResult readResult;
    try {
      readResult = await bindingReadPort.readExact(bindingReference);
    } on Object {
      return _rejected(
        const MeasurementPublicationBindingTransportUnavailable(),
      );
    }

    return _resolveReadResult(
      bindingReference: bindingReference,
      readResult: readResult,
    );
  }

  static MeasurementPublicationBindingRuntimeResolution _resolveReadResult({
    required MeasurementPublicationBindingReferenceV1 bindingReference,
    required MeasurementPublicationBindingReadResult readResult,
  }) =>
      switch (readResult) {
        MeasurementPublicationBindingReadAccepted()
            when readResult.reference == bindingReference =>
          _resolveAcceptedRead(
            bindingReference: bindingReference,
            acceptedRead: readResult,
          ),
        MeasurementPublicationBindingReadAccepted() => _mismatched(),
        MeasurementPublicationBindingAbsent() => _rejected(readResult),
        MeasurementPublicationBindingUnsupportedFuture() =>
          _rejected(readResult),
        MeasurementPublicationBindingMismatched() => _rejected(readResult),
        MeasurementPublicationBindingReplayed() => _rejected(readResult),
        MeasurementPublicationBindingTransportUnavailable() => _rejected(
            readResult,
          ),
      };

  static MeasurementPublicationBindingRuntimeResolution _resolveAcceptedRead({
    required MeasurementPublicationBindingReferenceV1 bindingReference,
    required MeasurementPublicationBindingReadAccepted acceptedRead,
  }) {
    try {
      final binding = acceptedRead.binding;
      if (acceptedRead.reference != bindingReference ||
          !binding.matchesReference(bindingReference) ||
          acceptedRead.registeredPublicationAttestation.bindingReference !=
              bindingReference) {
        return _mismatched();
      }
      final mountedArtifactContext = _rootMountedContext(binding);
      if (mountedArtifactContext == null) {
        return _mismatched();
      }

      return MeasurementPublicationBindingRuntimeResolution._(
        readResult: acceptedRead,
        routeTable: MeasurementRuntimeRouteTable.fromPublicationBinding(
          mountedArtifactContext: mountedArtifactContext,
          binding: binding,
        ),
        resolvedMount: MeasurementPublicationBindingRuntimeResolvedMount._(
          publicationContextRef: ExactMeasurementPublicationContextRefV1(
            bindingReference: bindingReference,
            surfaceIdentity: binding.publishedSurfaceRevision.surfaceIdentity,
            surfaceRevisionId: binding.publishedSurfaceRevision.revisionId,
            artifactGraphHash: binding.exactArtifactGraph.canonicalDigest,
            measurementManifestHash:
                binding.completeMeasurementManifest.canonicalDigest,
          ),
          mountedArtifactContext: mountedArtifactContext,
          publishedSurfaceRevision: binding.publishedSurfaceRevision,
          minimumMeasurementClient:
              binding.publishedSurfaceRevision.minimumMeasurementClient,
          measurementSchemaVersion:
              binding.publishedSurfaceRevision.measurementSchemaVersion,
        ),
      );
    } on ArgumentError {
      return _mismatched();
    }
  }

  /// Derives the sole root-session context from the accepted binding.
  ///
  /// The root edge is re-proven here rather than trusted as an isolated
  /// revision field: it must be the graph root and map to the exact root
  /// artifact. Any mismatch leaves the exact read closed but unusable.
  static MeasurementMountedArtifactContext? _rootMountedContext(
    MeasurementPublicationBindingV1 binding,
  ) {
    final graph = binding.exactArtifactGraph;
    final revision = binding.publishedSurfaceRevision;
    if (graph.rootEdgeToken != revision.rootArtifactOccurrenceEdgeToken) {
      return null;
    }
    ArtifactOccurrenceEdgeV1? rootEdge;
    for (final edge in graph.occurrenceEdges) {
      if (edge.edgeToken == revision.rootArtifactOccurrenceEdgeToken) {
        if (rootEdge != null) return null;
        rootEdge = edge;
      }
    }
    if (rootEdge == null || rootEdge.artifactId != revision.rootArtifactId) {
      return null;
    }
    return MeasurementMountedArtifactContext(
      artifactGraphHash: graph.canonicalDigest,
      artifactId: revision.rootArtifactId,
      artifactOccurrenceEdgeToken: revision.rootArtifactOccurrenceEdgeToken,
      measurementManifestHash:
          binding.completeMeasurementManifest.canonicalDigest,
      surfaceRevisionId: revision.revisionId,
    );
  }

  static MeasurementPublicationBindingRuntimeResolution _mismatched() =>
      _rejected(const MeasurementPublicationBindingMismatched());

  static MeasurementPublicationBindingRuntimeResolution _rejected(
    MeasurementPublicationBindingReadResult readResult,
  ) =>
      MeasurementPublicationBindingRuntimeResolution._(
        readResult: readResult,
        routeTable: null,
        resolvedMount: null,
      );
}
