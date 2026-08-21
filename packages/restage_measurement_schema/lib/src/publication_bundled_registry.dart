import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/publication_binding.dart';
import 'package:restage_measurement_schema/src/publication_candidate.dart';
import 'package:restage_measurement_schema/src/target.dart';

/// Maximum exact bindings carried by one target-specific bundled registry.
///
/// A registry is an immutable application asset rather than a publication
/// payload. This independent registry-wide ceiling bounds sorting and exact
/// lookup work; per-binding artifact and route limits do not widen it. The
/// aggregate byte bound below independently limits parse and retained-memory
/// work.
const int kMaximumMeasurementPublicationBundledRegistryEntryCount = 1024;

/// Maximum canonical bytes admitted for one bundled registry document.
///
/// Thirty-two MiB bounds one immutable app-asset parse while leaving room for
/// the bounded publication closures it carries. A target whose registry is
/// larger must fail closed at generation rather than silently widening the V1
/// accepted set.
const int kMaximumMeasurementPublicationBundledRegistryBytes = 32 * 1024 * 1024;

/// Exact generated publication-and-artifact closure locator.
///
/// This target-neutral value names the generated publication manifest, upload,
/// and declared artifact-byte closure by their independently recomputed
/// digests. It contains no delivery selection state or author-facing identity.
final class MeasurementBundledGeneratedPublicationLocatorV1
    extends CanonicalValue {
  /// Creates one exact generated publication-and-artifact locator.
  const MeasurementBundledGeneratedPublicationLocatorV1({
    required this.selectedPublicationManifestDigest,
    required this.assembledPublicationUploadDigest,
    required this.declaredArtifactBytesDigest,
  });

  /// Decodes byte-exact canonical generated publication locator bytes.
  factory MeasurementBundledGeneratedPublicationLocatorV1.fromCanonicalBytes(
    List<int> bytes,
  ) {
    if (bytes.length != canonicalByteLength) {
      throw const CanonicalFormatException(
        'measurementBundledGeneratedPublicationLocator must have the exact '
        'V1 canonical byte length',
      );
    }
    return verifyCanonicalRoundTrip(
      MeasurementBundledGeneratedPublicationLocatorV1.fromJson(
        decodeCanonicalObject(bytes),
      ),
      bytes,
      path: 'measurementBundledGeneratedPublicationLocator',
    );
  }

  /// Decodes one strict generated publication-and-artifact locator.
  factory MeasurementBundledGeneratedPublicationLocatorV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'assembledPublicationUploadDigest',
        'declaredArtifactBytesDigest',
        'kind',
        'selectedPublicationManifestDigest',
      },
      requiredKeys: const {
        'assembledPublicationUploadDigest',
        'declaredArtifactBytesDigest',
        'kind',
        'selectedPublicationManifestDigest',
      },
      path: 'measurementBundledGeneratedPublicationLocator',
    );
    if (reader.string('kind') !=
        'measurementBundledGeneratedPublicationLocator') {
      throw const CanonicalFormatException(
        'measurementBundledGeneratedPublicationLocator.kind must be '
        '"measurementBundledGeneratedPublicationLocator"',
      );
    }
    return _constructBundledRegistry(
      'measurementBundledGeneratedPublicationLocator',
      () => MeasurementBundledGeneratedPublicationLocatorV1(
        assembledPublicationUploadDigest: CanonicalDigest(
          reader.string('assembledPublicationUploadDigest'),
        ),
        declaredArtifactBytesDigest: CanonicalDigest(
          reader.string('declaredArtifactBytesDigest'),
        ),
        selectedPublicationManifestDigest: CanonicalDigest(
          reader.string('selectedPublicationManifestDigest'),
        ),
      ),
    );
  }

  /// Digest of the selected generated surface publication manifest bytes.
  final CanonicalDigest selectedPublicationManifestDigest;

  /// Digest of the assembled generated publication upload bytes.
  final CanonicalDigest assembledPublicationUploadDigest;

  /// Digest of the complete declared generated artifact-byte closure.
  final CanonicalDigest declaredArtifactBytesDigest;

  /// Exact canonical byte length of this fixed-width V1 locator.
  static const int canonicalByteLength = 358;

  @override
  Map<String, Object?> toJson() => {
        'assembledPublicationUploadDigest':
            assembledPublicationUploadDigest.hex,
        'declaredArtifactBytesDigest': declaredArtifactBytesDigest.hex,
        'kind': 'measurementBundledGeneratedPublicationLocator',
        'selectedPublicationManifestDigest':
            selectedPublicationManifestDigest.hex,
      };
}

/// Closed result of one generated publication locator lookup in a bundled
/// registry.
sealed class MeasurementPublicationBundledRegistryLocatorResolution {
  const MeasurementPublicationBundledRegistryLocatorResolution();
}

/// The generated publication locator had no bundled registry entry.
final class MeasurementPublicationBundledRegistryLocatorAbsent
    extends MeasurementPublicationBundledRegistryLocatorResolution {
  /// Creates an exact-absence resolution.
  const MeasurementPublicationBundledRegistryLocatorAbsent();
}

/// The generated publication locator had one complete bundled registry entry.
final class MeasurementPublicationBundledRegistryLocatorAccepted
    extends MeasurementPublicationBundledRegistryLocatorResolution {
  /// Creates a resolution for one exact immutable entry.
  const MeasurementPublicationBundledRegistryLocatorAccepted(this.entry);

  /// The one exact immutable registry entry.
  final MeasurementPublicationBundledRegistryEntryV1 entry;
}

/// More than one bundled entry claimed the exact generated publication locator.
final class MeasurementPublicationBundledRegistryLocatorAmbiguous
    extends MeasurementPublicationBundledRegistryLocatorResolution {
  /// Creates an ambiguous-resolution disposition.
  const MeasurementPublicationBundledRegistryLocatorAmbiguous();
}

/// One complete registered bundled binding proof.
///
/// The entry carries the generated publication locator, candidate closure,
/// final binding, and registered attestation together. It never derives any of
/// them from a host request.
final class MeasurementPublicationBundledRegistryEntryV1
    extends CanonicalValue {
  /// Creates one closed exact bundled binding proof.
  MeasurementPublicationBundledRegistryEntryV1({
    required this.generatedPublicationLocator,
    required this.candidateProof,
    required this.candidateReference,
    required this.declaredArtifactBytesDigest,
    required this.reference,
    required this.binding,
    required this.registeredPublicationAttestation,
  }) {
    final authority = reference.publicationAuthorityReference;
    if (!_sameCanonicalBytes(reference, binding.reference) ||
        !_sameCanonicalBytes(
          reference,
          registeredPublicationAttestation.bindingReference,
        )) {
      throw ArgumentError(
        'A bundled registry entry requires matching reference, binding, and '
        'registered attestation',
      );
    }
    if (!_sameCanonicalBytes(candidateProof.reference, candidateReference) ||
        !_sameCanonicalBytes(
          candidateReference,
          authority.candidateReference,
        )) {
      throw ArgumentError(
        'A bundled registry entry requires its candidate proof and reference '
        'to match the registered authority',
      );
    }
    if (declaredArtifactBytesDigest !=
            candidateProof.declaredArtifactBytesDigest ||
        declaredArtifactBytesDigest !=
            candidateReference.declaredArtifactBytesDigest ||
        declaredArtifactBytesDigest != authority.declaredArtifactBytesDigest) {
      throw ArgumentError(
        'A bundled registry entry requires one declared artifact-byte '
        'authority across its complete proof',
      );
    }
    if (generatedPublicationLocator.selectedPublicationManifestDigest !=
            candidateReference.selectedPublicationManifestDigest ||
        generatedPublicationLocator.assembledPublicationUploadDigest !=
            candidateReference.assembledPublicationUploadDigest ||
        generatedPublicationLocator.declaredArtifactBytesDigest !=
            declaredArtifactBytesDigest) {
      throw ArgumentError(
        'A bundled registry entry locator must close its candidate proof and '
        'declared artifact-byte authority',
      );
    }
  }

  /// Decodes byte-exact canonical bundled-registry entry bytes.
  factory MeasurementPublicationBundledRegistryEntryV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementPublicationBundledRegistryEntryV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'measurementPublicationBundledRegistryEntry',
      );

  /// Decodes one strict exact bundled binding proof.
  factory MeasurementPublicationBundledRegistryEntryV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'binding',
        'candidateProof',
        'candidateReference',
        'declaredArtifactBytesDigest',
        'generatedPublicationLocator',
        'kind',
        'reference',
        'registeredPublicationAttestation',
      },
      requiredKeys: const {
        'binding',
        'candidateProof',
        'candidateReference',
        'declaredArtifactBytesDigest',
        'generatedPublicationLocator',
        'kind',
        'reference',
        'registeredPublicationAttestation',
      },
      path: 'measurementPublicationBundledRegistryEntry',
    );
    if (reader.string('kind') != 'measurementPublicationBundledRegistryEntry') {
      throw const CanonicalFormatException(
        'measurementPublicationBundledRegistryEntry.kind must be '
        '"measurementPublicationBundledRegistryEntry"',
      );
    }
    return _constructBundledRegistry(
      'measurementPublicationBundledRegistryEntry',
      () => MeasurementPublicationBundledRegistryEntryV1(
        generatedPublicationLocator:
            MeasurementBundledGeneratedPublicationLocatorV1.fromJson(
          reader.object('generatedPublicationLocator'),
        ),
        candidateProof: MeasurementPublicationCandidateProofV1.fromJson(
          reader.object('candidateProof'),
        ),
        candidateReference: MeasurementPublicationCandidateReferenceV1.fromJson(
          reader.object('candidateReference'),
        ),
        declaredArtifactBytesDigest: CanonicalDigest(
          reader.string('declaredArtifactBytesDigest'),
        ),
        reference: MeasurementPublicationBindingReferenceV1.fromJson(
          reader.object('reference'),
        ),
        binding: MeasurementPublicationBindingV1.fromJson(
          reader.object('binding'),
        ),
        registeredPublicationAttestation:
            RegisteredPublicationAttestationV1.fromJson(
          reader.object('registeredPublicationAttestation'),
        ),
      ),
    );
  }

  /// Exact generated publication-and-artifact closure key.
  final MeasurementBundledGeneratedPublicationLocatorV1
      generatedPublicationLocator;

  /// Exact target-neutral candidate closure retained with the final entry.
  final MeasurementPublicationCandidateProofV1 candidateProof;

  /// Candidate reference independently retained with [candidateProof].
  final MeasurementPublicationCandidateReferenceV1 candidateReference;

  /// Declared artifact-byte authority retained with the final entry.
  final CanonicalDigest declaredArtifactBytesDigest;

  /// Complete immutable handle for the carried binding proof.
  final MeasurementPublicationBindingReferenceV1 reference;

  /// Exact canonical binding document.
  final MeasurementPublicationBindingV1 binding;

  /// Backend-issued registered attestation for [reference].
  final RegisteredPublicationAttestationV1 registeredPublicationAttestation;

  /// The pre-closed read result represented by this immutable entry.
  late final MeasurementPublicationBindingReadAccepted acceptedRead =
      MeasurementPublicationBindingReadAccepted(
    reference: reference,
    binding: binding,
    registeredPublicationAttestation: registeredPublicationAttestation,
  );

  @override
  Map<String, Object?> toJson() => {
        'binding': binding.toJson(),
        'candidateProof': candidateProof.toJson(),
        'candidateReference': candidateReference.toJson(),
        'declaredArtifactBytesDigest': declaredArtifactBytesDigest.hex,
        'generatedPublicationLocator': generatedPublicationLocator.toJson(),
        'kind': 'measurementPublicationBundledRegistryEntry',
        'reference': reference.toJson(),
        'registeredPublicationAttestation':
            registeredPublicationAttestation.toJson(),
      };
}

/// Immutable exact binding registry for one complete [TargetCoordinate].
///
/// This document has no delivery-selection field. It is an exact proof asset:
/// callers can only resolve one complete generated publication locator.
final class MeasurementPublicationBundledRegistryV1 extends CanonicalDocument {
  /// Creates one target-specific immutable registry.
  MeasurementPublicationBundledRegistryV1({
    required this.target,
    required List<MeasurementPublicationBundledRegistryEntryV1> entries,
  }) : entries = _sortedUniqueBundledRegistryEntries(entries, target) {
    _validateCanonicalByteBound();
  }

  /// Decodes byte-exact canonical registry bytes.
  factory MeasurementPublicationBundledRegistryV1.fromCanonicalBytes(
    List<int> bytes,
  ) {
    if (bytes.length > kMaximumMeasurementPublicationBundledRegistryBytes) {
      throw const CanonicalFormatException(
        'measurementPublicationBundledRegistry exceeds its raw byte bound',
      );
    }
    return verifyCanonicalRoundTrip(
      MeasurementPublicationBundledRegistryV1.fromJson(
        decodeCanonicalObject(bytes),
      ),
      bytes,
      path: 'measurementPublicationBundledRegistry',
    );
  }

  /// Decodes one strict target-specific immutable registry.
  factory MeasurementPublicationBundledRegistryV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'entries', 'kind', 'schemaVersion', 'target'},
      requiredKeys: const {'entries', 'kind', 'schemaVersion', 'target'},
      path: 'measurementPublicationBundledRegistry',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'measurementPublicationBundledRegistry',
    );
    final rawEntries = reader.list('entries');
    if (rawEntries.length >
        kMaximumMeasurementPublicationBundledRegistryEntryCount) {
      throw const CanonicalFormatException(
        'measurementPublicationBundledRegistry.entries exceeds its raw input '
        'bound',
      );
    }
    return _constructBundledRegistry(
      'measurementPublicationBundledRegistry',
      () => MeasurementPublicationBundledRegistryV1(
        target: TargetCoordinate.fromJson(reader.object('target')),
        entries: [
          for (final rawEntry in rawEntries)
            MeasurementPublicationBundledRegistryEntryV1.fromJson(
              requireCanonicalObject(rawEntry, 'entries[]'),
            ),
        ],
      ),
    );
  }

  /// Exact resolved target whose bindings this registry may carry.
  final TargetCoordinate target;

  /// Deterministically sorted, immutable complete binding proofs.
  final List<MeasurementPublicationBundledRegistryEntryV1> entries;

  /// Resolves [generatedPublicationLocator] with exact zero/one/many rules.
  ///
  /// The result never exposes an ordered candidate list, so a caller cannot
  /// pick one of several matching final entries.
  MeasurementPublicationBundledRegistryLocatorResolution
      resolveExactGeneratedPublicationLocator(
    MeasurementBundledGeneratedPublicationLocatorV1 generatedPublicationLocator,
  ) {
    MeasurementPublicationBundledRegistryEntryV1? matched;
    for (final entry in entries) {
      if (!_sameCanonicalBytes(
        entry.generatedPublicationLocator,
        generatedPublicationLocator,
      )) {
        continue;
      }
      if (matched != null) {
        return const MeasurementPublicationBundledRegistryLocatorAmbiguous();
      }
      matched = entry;
    }
    return matched == null
        ? const MeasurementPublicationBundledRegistryLocatorAbsent()
        : MeasurementPublicationBundledRegistryLocatorAccepted(matched);
  }

  @override
  CanonicalHashDomain get hashDomain =>
      CanonicalHashDomain.measurementPublicationBundledRegistry;

  @override
  Map<String, Object?> toJson() => {
        'entries': [for (final entry in entries) entry.toJson()],
        'kind': 'measurementPublicationBundledRegistry',
        'schemaVersion': kMeasurementSchemaVersion,
        'target': target.toJson(),
      };

  void _validateCanonicalByteBound() {
    if (canonicalBytes.length >
        kMaximumMeasurementPublicationBundledRegistryBytes) {
      throw ArgumentError(
        'A bundled registry exceeds its '
        '$kMaximumMeasurementPublicationBundledRegistryBytes-byte limit',
      );
    }
  }
}

List<MeasurementPublicationBundledRegistryEntryV1>
    _sortedUniqueBundledRegistryEntries(
  List<MeasurementPublicationBundledRegistryEntryV1> values,
  TargetCoordinate target,
) {
  if (values.length > kMaximumMeasurementPublicationBundledRegistryEntryCount) {
    throw ArgumentError(
      'A bundled registry permits at most '
      '$kMaximumMeasurementPublicationBundledRegistryEntryCount entries',
    );
  }
  final copy = values.toList()
    ..sort((left, right) {
      final locatorComparison = _compareCanonicalBytes(
        left.generatedPublicationLocator.canonicalBytes,
        right.generatedPublicationLocator.canonicalBytes,
      );
      if (locatorComparison != 0) return locatorComparison;
      return _compareCanonicalBytes(
        left.reference.canonicalBytes,
        right.reference.canonicalBytes,
      );
    });
  final references = <String>{};
  final externalPublicationReferences = <String>{};
  final immutablePublicationDigests = <String>{};
  for (final entry in copy) {
    final bindingTarget = entry.binding.completeMeasurementManifest.target;
    if (!_sameCanonicalBytes(bindingTarget, target) ||
        !_sameCanonicalBytes(
          entry.binding.publishedSurfaceRevision.surfaceIdentity.target,
          target,
        )) {
      throw ArgumentError(
        'Every bundled registry binding must close the registry target',
      );
    }
    final referenceKey = String.fromCharCodes(entry.reference.canonicalBytes);
    if (!references.add(referenceKey)) {
      throw ArgumentError('Bundled registry binding references must be unique');
    }
    final authority = entry.reference.publicationAuthorityReference;
    // Exact binding-reference uniqueness alone would allow a second binding
    // digest to rebind one immutable external publication. Publication
    // authority issuance defines both of these fields as that publication's
    // identity.
    if (!externalPublicationReferences.add(
      authority.externalPublicationAuthorityRef,
    )) {
      throw ArgumentError(
        'Bundled registry immutable publication references must be unique',
      );
    }
    if (!immutablePublicationDigests.add(
      authority.immutablePublicationDigest.hex,
    )) {
      throw ArgumentError(
        'Bundled registry immutable publication digests must be unique',
      );
    }
  }
  return List.unmodifiable(copy);
}

bool _sameCanonicalBytes(CanonicalValue left, CanonicalValue right) =>
    _compareCanonicalBytes(left.canonicalBytes, right.canonicalBytes) == 0;

int _compareCanonicalBytes(List<int> left, List<int> right) {
  final sharedLength = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < sharedLength; index += 1) {
    final comparison = left[index].compareTo(right[index]);
    if (comparison != 0) return comparison;
  }
  return left.length.compareTo(right.length);
}

T _constructBundledRegistry<T>(String path, T Function() create) {
  try {
    return create();
    // Constructor admission failures must become canonical decoder failures.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}
