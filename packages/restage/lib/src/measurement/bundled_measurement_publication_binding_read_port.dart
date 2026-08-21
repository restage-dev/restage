import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

const int _maximumGeneratedArtifactClosureCarrierArtifacts = 1024;

/// Target-neutral compiler output attached only to generated source objects.
///
/// The final draft digest is available only after the compiler has finalized
/// the exact artifact closure. It deliberately does not name a target,
/// delivery selection, or hosted publication reference; the verified bundled
/// target profile performs the bounded exact join to the final publication locator.
@internal
@immutable
final class MeasurementBundledGeneratedSourceCarrier {
  /// Creates one exact final-draft carrier for generated source code.
  const MeasurementBundledGeneratedSourceCarrier({
    required this.measurementPublicationDraftDigest,
  });

  /// Digest of the compiler's exact final Measurement publication draft.
  final CanonicalDigest measurementPublicationDraftDigest;
}

/// One exact delivered payload artifact observed by a bundled resolver.
///
/// This is an internal runtime carrier, never a publication manifest role or a
/// developer-authored descriptor field. It retains the exact tuple shape the
/// verified registry proof uses, including the resolved asset path rather than
/// an inferred sibling path.
@internal
@immutable
final class MeasurementBundledGeneratedArtifact {
  /// Creates one exact resolved payload artifact carrier.
  MeasurementBundledGeneratedArtifact({
    required this.logicalPath,
    required this.role,
    required this.id,
    required this.byteLength,
    required this.sha256,
  }) {
    if (byteLength < 0 || byteLength > kRestageBundleMaxClassicZipValue) {
      throw ArgumentError.value(
        byteLength,
        'byteLength',
        'must fit a bundled artifact',
      );
    }
    // Reuse the frozen manifest tuple admission rules without adding any
    // Measurement field to a manifest or artifact role.
    SurfacePublicationArtifact(
      contentHash: sha256,
      path: logicalPath,
      role: role,
      id: id,
    );
  }

  /// Builds a carrier from the exact bytes returned by one bundled resolver.
  factory MeasurementBundledGeneratedArtifact.fromBytes({
    required String logicalPath,
    required SurfacePublicationArtifactRole role,
    required String? id,
    required List<int> bytes,
  }) =>
      MeasurementBundledGeneratedArtifact(
        logicalPath: logicalPath,
        role: role,
        id: id,
        byteLength: bytes.length,
        sha256: 'sha256:${crypto.sha256.convert(bytes)}',
      );

  /// Exact package-relative path used by the artifact resolver.
  final String logicalPath;

  /// The strict publication role for this payload artifact.
  final SurfacePublicationArtifactRole role;

  /// Screen identity for screen/blob roles, absent only for a flow document.
  final String? id;

  /// Exact byte length of the resolved artifact.
  final int byteLength;

  /// `sha256:<hex>` over the exact resolved bytes.
  final String sha256;

  String get _identity => '${role.wireName}\u0000$logicalPath\u0000${id ?? ''}';

  bool _matches(_DeclaredBundleArtifact artifact) =>
      logicalPath == artifact.path &&
      role == artifact.manifestRole &&
      id == artifact.id &&
      byteLength == artifact.byteLength &&
      sha256 == artifact.sha256;
}

/// Bounded exact payload closure attached to a bundled resolved result.
///
/// Capability sidecars are not payload artifacts and therefore do not occur in
/// this carrier. The read port still replays every sidecar and every other
/// declared tuple against the verified source-owned bundle before exposing a
/// final locator.
@internal
@immutable
final class MeasurementBundledGeneratedArtifactClosureCarrier {
  /// Creates a canonicalized, duplicate-free exact payload closure carrier.
  MeasurementBundledGeneratedArtifactClosureCarrier({
    required Iterable<MeasurementBundledGeneratedArtifact> artifacts,
  }) : artifacts = List.unmodifiable(_canonicalizeArtifacts(artifacts));

  /// Exact resolved payload artifacts in deterministic tuple order.
  final List<MeasurementBundledGeneratedArtifact> artifacts;

  static List<MeasurementBundledGeneratedArtifact> _canonicalizeArtifacts(
    Iterable<MeasurementBundledGeneratedArtifact> artifacts,
  ) {
    final result = artifacts.toList()
      ..sort((left, right) => left._identity.compareTo(right._identity));
    if (result.isEmpty ||
        result.length > _maximumGeneratedArtifactClosureCarrierArtifacts) {
      throw ArgumentError.value(
        result.length,
        'artifacts',
        'must contain 1..$_maximumGeneratedArtifactClosureCarrierArtifacts '
            'exact payload artifacts',
      );
    }
    final identities = <String>{};
    for (final artifact in result) {
      if (!identities.add(artifact._identity)) {
        throw ArgumentError.value(
          artifact.logicalPath,
          'artifacts',
          'must not repeat an exact payload artifact identity',
        );
      }
    }
    return result;
  }
}

final Expando<MeasurementBundledGeneratedSourceCarrier>
    _generatedSourceCarriers =
    Expando<MeasurementBundledGeneratedSourceCarrier>(
  'restage.measurement.bundledGeneratedSourceCarrier',
);

final Expando<MeasurementBundledGeneratedArtifactClosureCarrier>
    _generatedArtifactClosureCarriers =
    Expando<MeasurementBundledGeneratedArtifactClosureCarrier>(
  'restage.measurement.bundledGeneratedArtifactClosureCarrier',
);

/// Attaches compiler-owned exact source provenance to a generated descriptor
/// or its bundled resolved result.
@internal
T attachMeasurementBundledGeneratedSourceCarrier<T extends Object>(
  T value,
  MeasurementBundledGeneratedSourceCarrier? carrier,
) {
  if (carrier == null) return value;
  final existing = _generatedSourceCarriers[value];
  if (existing != null &&
      existing.measurementPublicationDraftDigest !=
          carrier.measurementPublicationDraftDigest) {
    throw StateError(
      'A generated source cannot be rebound to different Measurement '
      'provenance.',
    );
  }
  _generatedSourceCarriers[value] = carrier;
  return value;
}

/// Returns compiler-owned exact provenance for one generated source object.
@internal
MeasurementBundledGeneratedSourceCarrier?
    measurementBundledGeneratedSourceCarrierFor(Object value) =>
        _generatedSourceCarriers[value];

/// Decodes one compiler-emitted final-draft digest without disrupting render.
///
/// Generated Dart is expected to pass the exact compiler-owned digest. A
/// malformed literal is treated as no Measurement provenance so the source can
/// still render while Measurement remains disabled.
@internal
MeasurementBundledGeneratedSourceCarrier?
    measurementBundledGeneratedSourceCarrierForFinalDraftDigest(
  String measurementPublicationDraftDigest,
) {
  try {
    return MeasurementBundledGeneratedSourceCarrier(
      measurementPublicationDraftDigest: CanonicalDigest(
        measurementPublicationDraftDigest,
      ),
    );
  } on Object {
    return null;
  }
}

/// Attaches a resolver-observed exact payload closure to one bundled result.
@internal
T attachMeasurementBundledGeneratedArtifactClosureCarrier<T extends Object>(
  T value,
  MeasurementBundledGeneratedArtifactClosureCarrier? carrier,
) {
  if (carrier == null) return value;
  final existing = _generatedArtifactClosureCarriers[value];
  if (existing != null && !_sameArtifactClosures(existing, carrier)) {
    throw StateError(
      'A bundled resolved payload cannot be rebound to different Measurement '
      'artifact provenance.',
    );
  }
  _generatedArtifactClosureCarriers[value] = carrier;
  return value;
}

/// Returns the exact resolved payload closure, or null for no Measurement.
@internal
MeasurementBundledGeneratedArtifactClosureCarrier?
    measurementBundledGeneratedArtifactClosureCarrierFor(Object value) =>
        _generatedArtifactClosureCarriers[value];

bool _sameArtifactClosures(
  MeasurementBundledGeneratedArtifactClosureCarrier left,
  MeasurementBundledGeneratedArtifactClosureCarrier right,
) {
  if (left.artifacts.length != right.artifacts.length) return false;
  for (var index = 0; index < left.artifacts.length; index += 1) {
    final leftArtifact = left.artifacts[index];
    final rightArtifact = right.artifacts[index];
    if (leftArtifact.logicalPath != rightArtifact.logicalPath ||
        leftArtifact.role != rightArtifact.role ||
        leftArtifact.id != rightArtifact.id ||
        leftArtifact.byteLength != rightArtifact.byteLength ||
        leftArtifact.sha256 != rightArtifact.sha256) {
      return false;
    }
  }
  return true;
}

/// Exact-only bundled source over one verified target-profile closure.
///
/// This port has no transport, delivery-selection, or reference lookup path.
/// Its target, registry, and bundle artifacts are fixed by the profile loader.
final class BundledMeasurementPublicationBindingReadPort {
  /// Creates a port only after the profile loader verified its bundle closure.
  @internal
  BundledMeasurementPublicationBindingReadPort({
    required this.target,
    required MeasurementPublicationBundledRegistryV1 registry,
    required Iterable<RestageBundle> verifiedBundles,
  })  : _registry = registry,
        _verifiedArtifacts = _verifiedArtifactIndex(verifiedBundles) {
    if (registry.target != target) {
      throw ArgumentError(
        'A bundled Measurement read port requires the verified profile target.',
      );
    }
  }

  /// The exact target decoded from the selected packaged profile.
  final TargetCoordinate target;

  final MeasurementPublicationBundledRegistryV1 _registry;
  final Map<String, _VerifiedBundleArtifact> _verifiedArtifacts;

  /// Resolves one generated surface publication closure under exact zero/one/many rules.
  ///
  /// The accepted result is exposed only after the entry's candidate proof has
  /// replayed every declared artifact tuple against the verified bundle bytes.
  Future<MeasurementPublicationBindingReadResult>
      resolveExactGeneratedPublicationLocator(
    MeasurementBundledGeneratedPublicationLocatorV1 generatedPublicationLocator,
  ) async {
    final resolution = _registry.resolveExactGeneratedPublicationLocator(
      generatedPublicationLocator,
    );
    return switch (resolution) {
      MeasurementPublicationBundledRegistryLocatorAbsent() =>
        const MeasurementPublicationBindingAbsent(),
      MeasurementPublicationBundledRegistryLocatorAmbiguous() =>
        const MeasurementPublicationBindingReplayed(),
      MeasurementPublicationBundledRegistryLocatorAccepted() =>
        _matchesVerifiedCandidateClosure(resolution.entry)
            ? resolution.entry.acceptedRead
            : const MeasurementPublicationBindingMismatched(),
    };
  }

  /// Resolves one compiler-generated source carrier to exactly one final publication
  /// locator, or returns null for absent, ambiguous, stale, or malformed
  /// provenance.
  ///
  /// The carrier's final draft digest is target-neutral compiler output. This
  /// method is the only profile-owned join from that digest to the final
  /// manifest/upload/artifact locator, and it never selects a candidate by
  /// slug, mutable delivery state, a widget key, or an alternate path.
  @internal
  Future<MeasurementBundledGeneratedPublicationLocatorV1?>
      resolveExactGeneratedSourceCarrier(
    MeasurementBundledGeneratedSourceCarrier carrier,
  ) async {
    try {
      MeasurementPublicationBundledRegistryEntryV1? matched;
      for (final entry in _registry.entries) {
        final digest = carrier.measurementPublicationDraftDigest;
        if (entry.candidateReference.measurementPublicationDraftDigest !=
                digest ||
            entry.candidateProof.measurementPublicationDraft.canonicalDigest !=
                digest) {
          continue;
        }
        if (matched != null) return null;
        matched = entry;
      }
      if (matched == null || !_matchesVerifiedCandidateClosure(matched)) {
        return null;
      }
      return matched.generatedPublicationLocator;
    } on Object {
      return null;
    }
  }

  /// Resolves an exact bundled payload closure to one final publication locator.
  ///
  /// This accepts only an exact set of resolved flow/blob payload tuples. The
  /// full registry candidate proof, including sidecars, is replayed against
  /// verified bundle bytes before the locator can leave the port.
  @internal
  Future<MeasurementBundledGeneratedPublicationLocatorV1?>
      resolveExactGeneratedArtifactClosureCarrier(
    MeasurementBundledGeneratedArtifactClosureCarrier carrier,
  ) async {
    try {
      MeasurementPublicationBundledRegistryEntryV1? matched;
      for (final entry in _registry.entries) {
        if (!_matchesResolvedPayloadArtifactClosure(entry, carrier)) {
          continue;
        }
        if (matched != null) return null;
        matched = entry;
      }
      if (matched == null || !_matchesVerifiedCandidateClosure(matched)) {
        return null;
      }
      return matched.generatedPublicationLocator;
    } on Object {
      return null;
    }
  }

  bool _matchesResolvedPayloadArtifactClosure(
    MeasurementPublicationBundledRegistryEntryV1 entry,
    MeasurementBundledGeneratedArtifactClosureCarrier carrier,
  ) {
    try {
      final declared = <_DeclaredBundleArtifact>[
        for (final tuple in entry.candidateProof.declaredArtifactTuples)
          _declaredArtifactFromTuple(tuple),
      ]
        ..removeWhere(
          (artifact) =>
              artifact.manifestRole ==
              SurfacePublicationArtifactRole.capabilitySidecar,
        )
        ..sort((left, right) => left.identity.compareTo(right.identity));
      if (declared.length != carrier.artifacts.length) return false;
      final identities = <String>{};
      for (var index = 0; index < declared.length; index += 1) {
        final artifact = declared[index];
        if (!identities.add(artifact.identity) ||
            !carrier.artifacts[index]._matches(artifact)) {
          return false;
        }
      }
      return true;
    } on Object {
      return false;
    }
  }

  bool _matchesVerifiedCandidateClosure(
    MeasurementPublicationBundledRegistryEntryV1 entry,
  ) {
    try {
      final proof = entry.candidateProof;
      final candidateReference = proof.recomputeReference();
      if (candidateReference != entry.candidateReference ||
          candidateReference !=
              entry
                  .reference.publicationAuthorityReference.candidateReference ||
          proof.declaredArtifactBytesDigest !=
              entry.declaredArtifactBytesDigest ||
          candidateReference.declaredArtifactBytesDigest !=
              entry.declaredArtifactBytesDigest ||
          entry.generatedPublicationLocator.selectedPublicationManifestDigest !=
              candidateReference.selectedPublicationManifestDigest ||
          entry.generatedPublicationLocator.assembledPublicationUploadDigest !=
              candidateReference.assembledPublicationUploadDigest ||
          entry.generatedPublicationLocator.declaredArtifactBytesDigest !=
              entry.declaredArtifactBytesDigest) {
        return false;
      }

      final tuples = List<MeasurementPublicationCandidateArtifactTupleV1>.of(
        proof.declaredArtifactTuples,
      )..sort(
          (left, right) => _compareBytes(
            left.canonicalTupleBytes,
            right.canonicalTupleBytes,
          ),
        );
      final tupleObjects = <Object?>[];
      for (final tuple in tuples) {
        final declaredArtifact = _declaredArtifactFromTuple(tuple);
        final verifiedArtifact = _verifiedArtifacts[declaredArtifact.path];
        if (verifiedArtifact == null ||
            !declaredArtifact.matches(verifiedArtifact)) {
          return false;
        }
        tupleObjects.add(CanonicalJsonCodec.decode(tuple.canonicalTupleBytes));
      }

      return _declaredArtifactDigest(tupleObjects) ==
          entry.declaredArtifactBytesDigest;
    } on Object {
      return false;
    }
  }
}

Map<String, _VerifiedBundleArtifact> _verifiedArtifactIndex(
  Iterable<RestageBundle> bundles,
) {
  final artifacts = <String, _VerifiedBundleArtifact>{};
  for (final bundle in bundles) {
    for (final entry in bundle.entries) {
      if (entry.role == RestageBundleEntryRole.rfwText) continue;
      final artifact = _VerifiedBundleArtifact.fromEntry(entry);
      if (artifacts.containsKey(artifact.path)) {
        throw ArgumentError(
          'Verified bundled Measurement artifacts must have unique paths.',
        );
      }
      artifacts[artifact.path] = artifact;
    }
  }
  return Map<String, _VerifiedBundleArtifact>.unmodifiable(artifacts);
}

CanonicalDigest _declaredArtifactDigest(List<Object?> tupleObjects) {
  final preimage = BytesBuilder(copy: false)
    ..add(utf8
        .encode('restage-surface-publication-declared-artifact-bytes-v1\u0000'))
    ..add(
      CanonicalJsonCodec.encode(<String, Object?>{
        'kind': 'restageSurfacePublicationDeclaredArtifactBytes',
        'schemaVersion': 1,
        'tuples': tupleObjects,
      }),
    );
  return CanonicalDigest(
    crypto.sha256.convert(preimage.takeBytes()).toString(),
  );
}

_DeclaredBundleArtifact _declaredArtifactFromTuple(
  MeasurementPublicationCandidateArtifactTupleV1 tuple,
) {
  final decoded = CanonicalJsonCodec.decode(tuple.canonicalTupleBytes);
  if (decoded is! Map) throw const FormatException('tuple is not an object');
  final json = <String, Object?>{};
  for (final entry in decoded.entries) {
    if (entry.key is! String) {
      throw const FormatException('tuple key is not a string');
    }
    json[entry.key as String] = entry.value;
  }
  if (json['kind'] != 'restageSurfacePublicationDeclaredArtifactTuple' ||
      json['schemaVersion'] != 1) {
    throw const FormatException('unsupported tuple kind');
  }
  final roleValue = json['role'];
  if (roleValue is! String) throw const FormatException('missing tuple role');
  final manifestRole = SurfacePublicationArtifactRole.fromWireName(roleValue);
  final expectedKeys = <String>{
    'byteLength',
    'kind',
    'path',
    'role',
    'schemaVersion',
    'sha256',
  };
  if (manifestRole != SurfacePublicationArtifactRole.flowDocument) {
    expectedKeys.add('id');
  }
  if (json.length != expectedKeys.length ||
      !json.keys.toSet().containsAll(expectedKeys)) {
    throw const FormatException('tuple fields do not match its role');
  }
  final path = json['path'];
  final byteLength = json['byteLength'];
  final sha256 = json['sha256'];
  final id = json['id'];
  if (path is! String ||
      byteLength is! int ||
      byteLength < 0 ||
      sha256 is! String ||
      (manifestRole != SurfacePublicationArtifactRole.flowDocument &&
          id is! String)) {
    throw const FormatException('tuple fields are invalid');
  }
  final artifact = SurfacePublicationArtifact(
    contentHash: 'sha256:$sha256',
    path: path,
    role: manifestRole,
    id: switch (manifestRole) {
      SurfacePublicationArtifactRole.flowDocument => null,
      _ => id as String,
    },
  );
  return _DeclaredBundleArtifact(
    path: artifact.path,
    manifestRole: artifact.role,
    role: RestageBundleEntryRole.fromManifestRole(artifact.role),
    id: artifact.id,
    byteLength: byteLength,
    sha256: artifact.contentHash,
  );
}

int _compareBytes(List<int> left, List<int> right) {
  final sharedLength = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < sharedLength; index += 1) {
    final comparison = left[index].compareTo(right[index]);
    if (comparison != 0) return comparison;
  }
  return left.length.compareTo(right.length);
}

final class _DeclaredBundleArtifact {
  const _DeclaredBundleArtifact({
    required this.path,
    required this.manifestRole,
    required this.role,
    required this.id,
    required this.byteLength,
    required this.sha256,
  });

  final String path;
  final SurfacePublicationArtifactRole manifestRole;
  final RestageBundleEntryRole role;
  final String? id;
  final int byteLength;
  final String sha256;

  String get identity => '${manifestRole.wireName}\u0000$path\u0000${id ?? ''}';

  bool matches(_VerifiedBundleArtifact artifact) =>
      role == artifact.role &&
      byteLength == artifact.byteLength &&
      sha256 == artifact.sha256;
}

final class _VerifiedBundleArtifact {
  const _VerifiedBundleArtifact({
    required this.path,
    required this.role,
    required this.byteLength,
    required this.sha256,
  });

  factory _VerifiedBundleArtifact.fromEntry(RestageBundleEntry entry) =>
      _VerifiedBundleArtifact(
        path: entry.logicalPath,
        role: entry.role,
        byteLength: entry.byteLength,
        sha256: entry.sha256,
      );

  final String path;
  final RestageBundleEntryRole role;
  final int byteLength;
  final String sha256;
}
