import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'measurement_publication_binding_runtime.dart';
import 'measurement_runtime_capture.dart';

/// Exact replacement-plane capability description schema understood by this
/// dormant SDK seam.
const int kMeasurementCaptureCapabilityDescriptionSchemaVersion = 1;

/// Exact capability revision implemented by the replacement Measurement plane.
const int kMeasurementCaptureCapabilityRevision = 1;

/// Installed Measurement client revision represented by this SDK build.
///
/// The published context's `minimumMeasurementClient` reuses this live positive
/// capability revision; it is not supplied by the delivered description.
const int kMeasurementCaptureClientRevision =
    kMeasurementCaptureCapabilityRevision;

/// Closed identifier for the replacement Measurement capture capability.
const String kMeasurementCaptureCapabilityId = 'measurement.capture';

/// Trusted capabilities installed in this SDK build.
///
/// This value is local build authority. It is never read from, or populated
/// by, a delivered [MeasurementCaptureCapabilityDescription]. The default is
/// the production capability revision; tests may provide a typed local value
/// to model another installed SDK without creating a wire field.
final class MeasurementCaptureInstalledCapabilities {
  const MeasurementCaptureInstalledCapabilities._({
    required this.measurementClientRevision,
  });

  /// The capability set compiled into this SDK build.
  static const current = MeasurementCaptureInstalledCapabilities._(
    measurementClientRevision: kMeasurementCaptureClientRevision,
  );

  /// Creates a validated local capability set for deterministic tests.
  factory MeasurementCaptureInstalledCapabilities({
    int measurementClientRevision = kMeasurementCaptureClientRevision,
  }) {
    _requirePortablePositive(
      measurementClientRevision,
      'measurementClientRevision',
    );
    return MeasurementCaptureInstalledCapabilities._(
      measurementClientRevision: measurementClientRevision,
    );
  }

  /// Positive live capability revision trusted from the installed SDK build.
  final int measurementClientRevision;
}

/// The result of comparing a capability description with its published context.
enum MeasurementCaptureCapabilityStatus {
  /// The exact capability and exact published context are mutually supported.
  supported,

  /// The description is known, but this client cannot satisfy its minimum.
  unsupported,

  /// The capability or published context was not supplied.
  missing,

  /// A supplied description had an invalid shape or value.
  malformed,

  /// A valid description belongs to an older context or descriptor line.
  stale,

  /// A description uses a future version, unknown field, or unknown capability.
  futureOrUnknown,
}

/// The only write authority the dormant gate can return.
enum MeasurementCaptureWriteAuthority {
  /// No Measurement write is admitted.
  none,

  /// The new replacement-plane fact frame is admitted.
  replacementPlane,
}

/// The exact published context that a capability description must seal.
///
/// This is an SDK-side projection of the already-published context. It does
/// not alter or decode the wire record, and it is intentionally separate
/// from the generic delivery carrier used for published surface content.
final class MeasurementCapturePublishedContext {
  MeasurementCapturePublishedContext._({
    required this.mountedArtifactContext,
    required this.minimumMeasurementClient,
    required this.measurementSchemaVersion,
  }) {
    _requirePortablePositive(
      minimumMeasurementClient,
      'minimumMeasurementClient',
    );
    _requirePortablePositive(
      measurementSchemaVersion,
      'measurementSchemaVersion',
    );
  }

  /// Derives capture context from one resolver-owned exact mounted result.
  ///
  /// [MeasurementPublicationBindingRuntimeResolvedMount] has no public
  /// constructor. The runtime resolver creates it only after an accepted exact
  /// binding read, registered-attestation agreement, mounted-context closure,
  /// and exact opaque-route closure.
  factory MeasurementCapturePublishedContext.fromResolvedMount(
    MeasurementPublicationBindingRuntimeResolvedMount resolvedMount,
  ) =>
      MeasurementCapturePublishedContext._(
        mountedArtifactContext: resolvedMount.mountedArtifactContext,
        minimumMeasurementClient: resolvedMount.minimumMeasurementClient,
        measurementSchemaVersion: resolvedMount.measurementSchemaVersion,
      );

  /// Exact artifact coordinates already resolved before Measurement capture.
  final MeasurementMountedArtifactContext mountedArtifactContext;

  /// Positive capability-revision floor for this published context.
  final int minimumMeasurementClient;

  /// Exact measurement schema version for this published context.
  final int measurementSchemaVersion;

  /// Returns a local, noncanonical description shape used by deterministic
  /// capability tests. It is not a compatibility decoder or wire contract.
  Map<String, Object?> toJson() => {
        'artifactGraphHash': mountedArtifactContext.artifactGraphHash.hex,
        'artifactId': mountedArtifactContext.artifactId.value,
        'artifactOccurrenceEdgeToken':
            mountedArtifactContext.artifactOccurrenceEdgeToken.value,
        'measurementManifestHash':
            mountedArtifactContext.measurementManifestHash.hex,
        'minimumMeasurementClient': minimumMeasurementClient,
        'measurementSchemaVersion': measurementSchemaVersion,
        'surfaceRevisionId': mountedArtifactContext.surfaceRevisionId.value,
      };

  @override
  bool operator ==(Object other) =>
      other is MeasurementCapturePublishedContext &&
      mountedArtifactContext == other.mountedArtifactContext &&
      minimumMeasurementClient == other.minimumMeasurementClient &&
      measurementSchemaVersion == other.measurementSchemaVersion;

  @override
  int get hashCode => Object.hash(
        mountedArtifactContext,
        minimumMeasurementClient,
        measurementSchemaVersion,
      );
}

/// One strict replacement-plane capability description.
///
/// The constructor is deliberately data-only. Admission performs the
/// fail-closed validation so malformed, stale, and future values can be
/// represented by matrix fixtures without being coerced into a supported
/// capability.
final class MeasurementCaptureCapabilityDescription {
  /// Creates a capability description for one exact published context.
  const MeasurementCaptureCapabilityDescription({
    required this.descriptionSchemaVersion,
    required this.capabilityId,
    required this.capabilityRevision,
    required this.measurementSchemaVersion,
    required this.publishedContext,
  });

  /// Schema version of this local capability-description shape.
  final int descriptionSchemaVersion;

  /// Closed replacement-plane capability identifier.
  final String capabilityId;

  /// Exact replacement-plane capability revision required by the description.
  final int capabilityRevision;

  /// Measurement schema version carried by the described published context.
  final int measurementSchemaVersion;

  /// Exact published context selected when this description was produced.
  final MeasurementCapturePublishedContext publishedContext;

  /// Returns the exact local description shape accepted by the strict gate.
  ///
  /// This map is only a test/adapter boundary for the new replacement plane;
  /// no legacy alias or compatibility format is accepted.
  Map<String, Object?> toJson() => {
        'capabilityId': capabilityId,
        'capabilityRevision': capabilityRevision,
        'kind': 'measurementCaptureCapability',
        'measurementSchemaVersion': measurementSchemaVersion,
        'publishedContext': publishedContext.toJson(),
        'schemaVersion': descriptionSchemaVersion,
      };
}

/// Immutable result of the capability gate.
final class MeasurementCaptureAdmission {
  const MeasurementCaptureAdmission._({
    required this.status,
    required this.writeAuthority,
  });

  /// Why the capability was or was not admitted.
  final MeasurementCaptureCapabilityStatus status;

  /// The only authority allowed to write facts after this decision.
  final MeasurementCaptureWriteAuthority writeAuthority;

  /// Whether the replacement-plane capture entry may receive facts.
  bool get admitted =>
      status == MeasurementCaptureCapabilityStatus.supported &&
      writeAuthority == MeasurementCaptureWriteAuthority.replacementPlane;

  /// Whether this decision permits a replacement-plane fact write.
  bool get writesReplacementFacts =>
      writeAuthority == MeasurementCaptureWriteAuthority.replacementPlane;

  /// Legacy analytics is never a fallback authority for this seam.
  bool get writesLegacyAnalytics => false;

  /// The capability seam never dual-writes facts.
  bool get dualWrites => false;

  /// Admission has no effect on ordinary host or business callbacks.
  bool get preservesHostBusinessCallbacks => true;
}

/// Pure, dormant admission gate for the automatic Measurement replacement
/// plane.
///
/// The gate validates one exact capability description and one exact published
/// context. A non-supported result has no write authority: it does not create
/// a capture session, invoke legacy analytics, or alter host/business work.
abstract final class MeasurementCaptureCapabilityGate {
  /// Evaluates the replacement-plane capability without activating capture.
  static MeasurementCaptureAdmission evaluate({
    required Object? capabilityDescription,
    required Object? publishedContext,
    MeasurementCaptureInstalledCapabilities installedCapabilities =
        MeasurementCaptureInstalledCapabilities.current,
  }) {
    if (capabilityDescription == null || publishedContext == null) {
      return _decision(MeasurementCaptureCapabilityStatus.missing);
    }
    if (publishedContext is! MeasurementCapturePublishedContext) {
      return _decision(MeasurementCaptureCapabilityStatus.malformed);
    }

    final parsed = _parseCapability(capabilityDescription);
    final parseStatus = parsed.status;
    if (parseStatus != null) return _decision(parseStatus);

    final capability = parsed.description!;
    final descriptorStatus = _validateDescriptorShape(capability);
    if (descriptorStatus != null) return _decision(descriptorStatus);

    final contextStatus = _validatePublishedContext(publishedContext);
    if (contextStatus != null) return _decision(contextStatus);

    final futureStatus = _futureProtocolStatus(
      capability: capability,
      publishedContext: publishedContext,
    );
    if (futureStatus != null) return _decision(futureStatus);

    if (!capability.publishedContext.matches(publishedContext)) {
      return _decision(MeasurementCaptureCapabilityStatus.stale);
    }
    if (capability.measurementSchemaVersion !=
        publishedContext.measurementSchemaVersion) {
      return _decision(MeasurementCaptureCapabilityStatus.stale);
    }
    if (capability.measurementSchemaVersion != kMeasurementSchemaVersion) {
      return _decision(
        capability.measurementSchemaVersion > kMeasurementSchemaVersion
            ? MeasurementCaptureCapabilityStatus.futureOrUnknown
            : MeasurementCaptureCapabilityStatus.stale,
      );
    }
    if (publishedContext.measurementSchemaVersion !=
        kMeasurementSchemaVersion) {
      return _decision(
        publishedContext.measurementSchemaVersion > kMeasurementSchemaVersion
            ? MeasurementCaptureCapabilityStatus.futureOrUnknown
            : MeasurementCaptureCapabilityStatus.stale,
      );
    }
    if (capability.capabilityId != kMeasurementCaptureCapabilityId) {
      return _decision(MeasurementCaptureCapabilityStatus.futureOrUnknown);
    }
    if (capability.descriptionSchemaVersion !=
        kMeasurementCaptureCapabilityDescriptionSchemaVersion) {
      return _decision(MeasurementCaptureCapabilityStatus.stale);
    }
    if (capability.capabilityRevision < kMeasurementCaptureCapabilityRevision) {
      return _decision(MeasurementCaptureCapabilityStatus.unsupported);
    }
    if (publishedContext.minimumMeasurementClient >
        installedCapabilities.measurementClientRevision) {
      return _decision(MeasurementCaptureCapabilityStatus.unsupported);
    }

    return _decision(MeasurementCaptureCapabilityStatus.supported);
  }

  static MeasurementCaptureAdmission _decision(
    MeasurementCaptureCapabilityStatus status,
  ) =>
      MeasurementCaptureAdmission._(
        status: status,
        writeAuthority: status == MeasurementCaptureCapabilityStatus.supported
            ? MeasurementCaptureWriteAuthority.replacementPlane
            : MeasurementCaptureWriteAuthority.none,
      );
}

MeasurementCaptureCapabilityStatus? _futureProtocolStatus({
  required _ParsedCapabilityDescription capability,
  required MeasurementCapturePublishedContext publishedContext,
}) {
  if (capability.descriptionSchemaVersion >
          kMeasurementCaptureCapabilityDescriptionSchemaVersion ||
      capability.capabilityRevision > kMeasurementCaptureCapabilityRevision ||
      capability.measurementSchemaVersion > kMeasurementSchemaVersion ||
      capability.publishedContext.measurementSchemaVersion >
          kMeasurementSchemaVersion ||
      publishedContext.measurementSchemaVersion > kMeasurementSchemaVersion ||
      capability.capabilityId != kMeasurementCaptureCapabilityId) {
    return MeasurementCaptureCapabilityStatus.futureOrUnknown;
  }
  return null;
}

final class _ParsedCapability {
  const _ParsedCapability(this.description) : status = null;

  const _ParsedCapability.status(MeasurementCaptureCapabilityStatus value)
      : description = null,
        status = value;

  final _ParsedCapabilityDescription? description;
  final MeasurementCaptureCapabilityStatus? status;
}

final class _ParsedCapabilityDescription {
  const _ParsedCapabilityDescription({
    required this.descriptionSchemaVersion,
    required this.capabilityId,
    required this.capabilityRevision,
    required this.measurementSchemaVersion,
    required this.publishedContext,
  });

  factory _ParsedCapabilityDescription.fromDescription(
    MeasurementCaptureCapabilityDescription description,
  ) =>
      _ParsedCapabilityDescription(
        descriptionSchemaVersion: description.descriptionSchemaVersion,
        capabilityId: description.capabilityId,
        capabilityRevision: description.capabilityRevision,
        measurementSchemaVersion: description.measurementSchemaVersion,
        publishedContext: _ParsedPublishedContextDescription.fromContext(
          description.publishedContext,
        ),
      );

  final int descriptionSchemaVersion;
  final String capabilityId;
  final int capabilityRevision;
  final int measurementSchemaVersion;
  final _ParsedPublishedContextDescription publishedContext;
}

_ParsedCapability _parseCapability(Object raw) {
  if (raw is MeasurementCaptureCapabilityDescription) {
    return _ParsedCapability(
      _ParsedCapabilityDescription.fromDescription(raw),
    );
  }
  if (raw is! Map) {
    return const _ParsedCapability.status(
      MeasurementCaptureCapabilityStatus.malformed,
    );
  }

  final map = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      return const _ParsedCapability.status(
        MeasurementCaptureCapabilityStatus.malformed,
      );
    }
    map[entry.key as String] = entry.value;
  }

  const knownKeys = <String>{
    'capabilityId',
    'capabilityRevision',
    'kind',
    'measurementSchemaVersion',
    'publishedContext',
    'schemaVersion',
  };
  if (map.keys.any((key) => !knownKeys.contains(key))) {
    return const _ParsedCapability.status(
      MeasurementCaptureCapabilityStatus.futureOrUnknown,
    );
  }
  const requiredWithoutContext = <String>{
    'capabilityId',
    'capabilityRevision',
    'kind',
    'measurementSchemaVersion',
    'schemaVersion',
  };
  if (!requiredWithoutContext.every(map.containsKey)) {
    return const _ParsedCapability.status(
      MeasurementCaptureCapabilityStatus.malformed,
    );
  }
  if (!map.containsKey('publishedContext') || map['publishedContext'] == null) {
    return const _ParsedCapability.status(
      MeasurementCaptureCapabilityStatus.missing,
    );
  }
  if (map['kind'] != 'measurementCaptureCapability') {
    return const _ParsedCapability.status(
      MeasurementCaptureCapabilityStatus.futureOrUnknown,
    );
  }

  final descriptionSchemaVersion = _readInt(map['schemaVersion']);
  final capabilityRevision = _readInt(map['capabilityRevision']);
  final measurementSchemaVersion = _readInt(map['measurementSchemaVersion']);
  final capabilityId = map['capabilityId'];
  if (descriptionSchemaVersion == null ||
      capabilityRevision == null ||
      measurementSchemaVersion == null ||
      capabilityId is! String) {
    return const _ParsedCapability.status(
      MeasurementCaptureCapabilityStatus.malformed,
    );
  }

  final context = _parsePublishedContext(map['publishedContext']);
  if (context.status != null) {
    return _ParsedCapability.status(context.status!);
  }
  return _ParsedCapability(
    _ParsedCapabilityDescription(
      descriptionSchemaVersion: descriptionSchemaVersion,
      capabilityId: capabilityId,
      capabilityRevision: capabilityRevision,
      measurementSchemaVersion: measurementSchemaVersion,
      publishedContext: context.publishedContext!,
    ),
  );
}

_ParsedPublishedContext _parsePublishedContext(Object? raw) {
  if (raw is! Map) {
    return const _ParsedPublishedContext.status(
      MeasurementCaptureCapabilityStatus.malformed,
    );
  }

  final map = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      return const _ParsedPublishedContext.status(
        MeasurementCaptureCapabilityStatus.malformed,
      );
    }
    map[entry.key as String] = entry.value;
  }
  const knownKeys = <String>{
    'artifactGraphHash',
    'artifactId',
    'artifactOccurrenceEdgeToken',
    'measurementManifestHash',
    'minimumMeasurementClient',
    'measurementSchemaVersion',
    'surfaceRevisionId',
  };
  if (map.keys.any((key) => !knownKeys.contains(key))) {
    return const _ParsedPublishedContext.status(
      MeasurementCaptureCapabilityStatus.futureOrUnknown,
    );
  }
  if (!knownKeys.every(map.containsKey)) {
    return const _ParsedPublishedContext.status(
      MeasurementCaptureCapabilityStatus.malformed,
    );
  }
  final artifactGraphHash = map['artifactGraphHash'];
  final artifactId = map['artifactId'];
  final artifactOccurrenceEdgeToken = map['artifactOccurrenceEdgeToken'];
  final measurementManifestHash = map['measurementManifestHash'];
  final minimumMeasurementClient = _readInt(map['minimumMeasurementClient']);
  final measurementSchemaVersion = _readInt(map['measurementSchemaVersion']);
  final surfaceRevisionId = map['surfaceRevisionId'];
  if (artifactGraphHash is! String ||
      artifactId is! String ||
      artifactOccurrenceEdgeToken is! String ||
      measurementManifestHash is! String ||
      minimumMeasurementClient == null ||
      measurementSchemaVersion == null ||
      surfaceRevisionId is! String) {
    return const _ParsedPublishedContext.status(
      MeasurementCaptureCapabilityStatus.malformed,
    );
  }

  try {
    _requirePortablePositive(
      minimumMeasurementClient,
      'minimumMeasurementClient',
    );
    _requirePortablePositive(
      measurementSchemaVersion,
      'measurementSchemaVersion',
    );
    return _ParsedPublishedContext(
      _ParsedPublishedContextDescription(
        mountedArtifactContext: MeasurementMountedArtifactContext(
          artifactGraphHash: CanonicalDigest(artifactGraphHash),
          artifactId: ArtifactId(artifactId),
          artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
            artifactOccurrenceEdgeToken,
          ),
          measurementManifestHash: CanonicalDigest(measurementManifestHash),
          surfaceRevisionId: SurfaceRevisionId(surfaceRevisionId),
        ),
        minimumMeasurementClient: minimumMeasurementClient,
        measurementSchemaVersion: measurementSchemaVersion,
      ),
    );
  } on Object {
    return const _ParsedPublishedContext.status(
      MeasurementCaptureCapabilityStatus.malformed,
    );
  }
}

final class _ParsedPublishedContext {
  const _ParsedPublishedContext(this.publishedContext) : status = null;

  const _ParsedPublishedContext.status(MeasurementCaptureCapabilityStatus value)
      : publishedContext = null,
        status = value;

  final _ParsedPublishedContextDescription? publishedContext;
  final MeasurementCaptureCapabilityStatus? status;
}

final class _ParsedPublishedContextDescription {
  const _ParsedPublishedContextDescription({
    required this.mountedArtifactContext,
    required this.minimumMeasurementClient,
    required this.measurementSchemaVersion,
  });

  factory _ParsedPublishedContextDescription.fromContext(
    MeasurementCapturePublishedContext context,
  ) =>
      _ParsedPublishedContextDescription(
        mountedArtifactContext: context.mountedArtifactContext,
        minimumMeasurementClient: context.minimumMeasurementClient,
        measurementSchemaVersion: context.measurementSchemaVersion,
      );

  final MeasurementMountedArtifactContext mountedArtifactContext;
  final int minimumMeasurementClient;
  final int measurementSchemaVersion;

  bool matches(MeasurementCapturePublishedContext context) =>
      mountedArtifactContext == context.mountedArtifactContext &&
      minimumMeasurementClient == context.minimumMeasurementClient &&
      measurementSchemaVersion == context.measurementSchemaVersion;
}

MeasurementCaptureCapabilityStatus? _validateDescriptorShape(
  _ParsedCapabilityDescription capability,
) {
  if (capability.capabilityId.isEmpty ||
      capability.descriptionSchemaVersion < 0 ||
      capability.capabilityRevision < 0 ||
      capability.measurementSchemaVersion < 0 ||
      capability.descriptionSchemaVersion > kMaximumPortableJsonInteger ||
      capability.capabilityRevision > kMaximumPortableJsonInteger ||
      capability.measurementSchemaVersion > kMaximumPortableJsonInteger) {
    return MeasurementCaptureCapabilityStatus.malformed;
  }
  return null;
}

MeasurementCaptureCapabilityStatus? _validatePublishedContext(
  MeasurementCapturePublishedContext context,
) {
  if (context.minimumMeasurementClient <= 0 ||
      context.minimumMeasurementClient > kMaximumPortableJsonInteger ||
      context.measurementSchemaVersion <= 0 ||
      context.measurementSchemaVersion > kMaximumPortableJsonInteger) {
    return MeasurementCaptureCapabilityStatus.malformed;
  }
  return null;
}

int? _readInt(Object? value) => value is int ? value : null;

void _requirePortablePositive(int value, String name) {
  if (value <= 0 || value > kMaximumPortableJsonInteger) {
    throw ArgumentError.value(
      value,
      name,
      'Expected a positive portable JSON integer',
    );
  }
}
