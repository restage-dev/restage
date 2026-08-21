import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/publication_draft.dart';

/// Existing publication-body ceiling retained by this dependency-free API.
///
/// This package deliberately duplicates the frozen 512 KiB cap rather than
/// importing surface publication types or limits.
const int kMaximumMeasurementPublicationCandidatePayloadBytes = 512 * 1024;

/// Maximum opaque external bytes admitted for one selected publication
/// manifest.
const int kMaximumMeasurementPublicationCandidateManifestBytes =
    kMaximumMeasurementPublicationCandidatePayloadBytes;

/// Maximum opaque external bytes admitted for one assembled publication upload.
const int kMaximumMeasurementPublicationCandidateUploadBytes =
    kMaximumMeasurementPublicationCandidatePayloadBytes;

/// Maximum bytes this schema admits for one declared-artifact metadata tuple.
///
/// Tuple bytes contain only a path, role, optional identity, byte length, and
/// exact-byte digest as interpreted by a registered adapter; artifact payload
/// bytes never appear in this value.
const int kMaximumMeasurementPublicationCandidateArtifactTupleBytes = 4096;

/// Maximum declared artifact tuples admitted to one candidate proof.
const int kMaximumMeasurementPublicationCandidateArtifactTupleCount = 1024;

/// Maximum aggregate bytes this schema admits for declared-artifact metadata.
const int kMaximumMeasurementPublicationCandidateArtifactClosureBytes =
    512 * 1024;

/// Maximum target-neutral Measurement draft bytes this schema admits.
const int kMaximumMeasurementPublicationCandidateDraftBytes = 512 * 1024;

/// Maximum complete opaque and draft byte closure admitted to one proof.
///
/// This equals two existing publication 512 KiB bodies plus the artifact
/// metadata and draft limits. It bounds raw closure bytes before base64url
/// envelope expansion.
const int kMaximumMeasurementPublicationCandidateProofBytes =
    kMaximumMeasurementPublicationCandidateManifestBytes +
        kMaximumMeasurementPublicationCandidateUploadBytes +
        kMaximumMeasurementPublicationCandidateArtifactClosureBytes +
        kMaximumMeasurementPublicationCandidateDraftBytes;

/// Target-neutral digest reference over one exact publication candidate.
final class MeasurementPublicationCandidateReferenceV1 extends CanonicalValue {
  /// Creates one fully recomputed candidate reference.
  const MeasurementPublicationCandidateReferenceV1({
    required this.candidateDigest,
    required this.selectedPublicationManifestDigest,
    required this.declaredArtifactBytesDigest,
    required this.assembledPublicationUploadDigest,
    required this.measurementPublicationDraftDigest,
  });

  /// Decodes byte-exact canonical candidate-reference bytes.
  factory MeasurementPublicationCandidateReferenceV1.fromCanonicalBytes(
    List<int> bytes,
  ) {
    if (bytes.length != canonicalByteLength) {
      throw const CanonicalFormatException(
        'measurementPublicationCandidateReference must have the exact V1 '
        'canonical byte length',
      );
    }
    return verifyCanonicalRoundTrip(
      MeasurementPublicationCandidateReferenceV1.fromJson(
        decodeCanonicalObject(bytes),
      ),
      bytes,
      path: 'measurementPublicationCandidateReference',
    );
  }

  /// Decodes a strict target-neutral candidate reference.
  factory MeasurementPublicationCandidateReferenceV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'assembledPublicationUploadDigest',
        'candidateDigest',
        'declaredArtifactBytesDigest',
        'kind',
        'measurementPublicationDraftDigest',
        'selectedPublicationManifestDigest',
      },
      requiredKeys: const {
        'assembledPublicationUploadDigest',
        'candidateDigest',
        'declaredArtifactBytesDigest',
        'kind',
        'measurementPublicationDraftDigest',
        'selectedPublicationManifestDigest',
      },
      path: 'measurementPublicationCandidateReference',
    );
    if (reader.string('kind') != 'measurementPublicationCandidateReference') {
      throw const CanonicalFormatException(
        'measurementPublicationCandidateReference.kind must be '
        '"measurementPublicationCandidateReference"',
      );
    }
    return _constructCandidate(
      'measurementPublicationCandidateReference',
      () => MeasurementPublicationCandidateReferenceV1(
        candidateDigest: CanonicalDigest(reader.string('candidateDigest')),
        selectedPublicationManifestDigest: CanonicalDigest(
          reader.string('selectedPublicationManifestDigest'),
        ),
        declaredArtifactBytesDigest: CanonicalDigest(
          reader.string('declaredArtifactBytesDigest'),
        ),
        assembledPublicationUploadDigest: CanonicalDigest(
          reader.string('assembledPublicationUploadDigest'),
        ),
        measurementPublicationDraftDigest: CanonicalDigest(
          reader.string('measurementPublicationDraftDigest'),
        ),
      ),
    );
  }

  /// Exact canonical byte length of this closed V1 reference object.
  ///
  /// The V1 shape contains one literal kind and five fixed-width SHA-256
  /// digests. This is a schema invariant, not a product transport allowance.
  static const int canonicalByteLength = 541;

  /// Domain-separated digest of the complete exact candidate closure.
  final CanonicalDigest candidateDigest;

  /// Digest of the exact selected opaque manifest bytes.
  final CanonicalDigest selectedPublicationManifestDigest;

  /// Adapter-issued digest of the exact declared artifact byte closure.
  final CanonicalDigest declaredArtifactBytesDigest;

  /// Digest of the exact assembled opaque upload bytes.
  final CanonicalDigest assembledPublicationUploadDigest;

  /// Digest of the exact target-neutral Measurement draft bytes.
  final CanonicalDigest measurementPublicationDraftDigest;

  @override
  Map<String, Object?> toJson() => {
        'assembledPublicationUploadDigest':
            assembledPublicationUploadDigest.hex,
        'candidateDigest': candidateDigest.hex,
        'declaredArtifactBytesDigest': declaredArtifactBytesDigest.hex,
        'kind': 'measurementPublicationCandidateReference',
        'measurementPublicationDraftDigest':
            measurementPublicationDraftDigest.hex,
        'selectedPublicationManifestDigest':
            selectedPublicationManifestDigest.hex,
      };
}

/// One Measurement-canonical opaque declared-artifact tuple in a candidate
/// proof.
///
/// The tuple's grammar and vocabulary are supplied by a registered adapter.
/// This schema verifies only its bounded, byte-exact Measurement canonical JSON
/// representation; it does not supply the tuple's external semantics.
final class MeasurementPublicationCandidateArtifactTupleV1
    extends CanonicalValue {
  /// Creates one bounded Measurement-canonical opaque tuple.
  MeasurementPublicationCandidateArtifactTupleV1({
    required List<int> canonicalTupleBytes,
  }) : _canonicalTupleBytes = _copyMeasurementCanonicalObject(
          canonicalTupleBytes,
          maximumLength:
              kMaximumMeasurementPublicationCandidateArtifactTupleBytes,
          label: 'declared artifact tuple',
        );

  /// Decodes byte-exact canonical tuple-envelope bytes.
  factory MeasurementPublicationCandidateArtifactTupleV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementPublicationCandidateArtifactTupleV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'measurementPublicationCandidateArtifactTuple',
      );

  /// Decodes one strict opaque tuple envelope.
  factory MeasurementPublicationCandidateArtifactTupleV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'canonicalTupleBase64Url', 'kind'},
      requiredKeys: const {'canonicalTupleBase64Url', 'kind'},
      path: 'measurementPublicationCandidateArtifactTuple',
    );
    if (reader.string('kind') !=
        'measurementPublicationCandidateArtifactTuple') {
      throw const CanonicalFormatException(
        'measurementPublicationCandidateArtifactTuple.kind must be '
        '"measurementPublicationCandidateArtifactTuple"',
      );
    }
    return _constructCandidate(
      'measurementPublicationCandidateArtifactTuple',
      () => MeasurementPublicationCandidateArtifactTupleV1(
        canonicalTupleBytes: _decodeBase64UrlNoPadding(
          reader.string('canonicalTupleBase64Url'),
          label: 'canonicalTupleBase64Url',
          maximumDecodedLength:
              kMaximumMeasurementPublicationCandidateArtifactTupleBytes,
        ),
      ),
    );
  }

  final Uint8List _canonicalTupleBytes;

  /// Defensive copy of the exact opaque canonical tuple bytes.
  Uint8List get canonicalTupleBytes => Uint8List.fromList(_canonicalTupleBytes);

  @override
  Map<String, Object?> toJson() => {
        'canonicalTupleBase64Url': _base64UrlNoPadding(_canonicalTupleBytes),
        'kind': 'measurementPublicationCandidateArtifactTuple',
      };
}

/// Bounded exact proof over publication-owned external bytes and one
/// Measurement draft.
///
/// The selected manifest and assembled upload retain the publication-owned
/// canonical byte profile exactly. This dependency-free schema bounds, copies,
/// hashes, and base64url-frames those bytes, but never parses, reserializes, or
/// claims their publication validity. A registered adapter owns publication
/// profile and semantic validation, and recomputes the declared artifact-byte
/// digest before finalization. Declared-artifact tuple bytes remain
/// Measurement-canonical objects, although their external meaning is also
/// adapter-owned.
final class MeasurementPublicationCandidateProofV1 extends CanonicalDocument {
  /// Creates one exact proof and recomputes its candidate reference.
  MeasurementPublicationCandidateProofV1({
    required List<int> selectedPublicationManifestCanonicalBytes,
    required List<MeasurementPublicationCandidateArtifactTupleV1>
        declaredArtifactTuples,
    required this.declaredArtifactBytesDigest,
    required List<int> assembledPublicationUploadCanonicalBytes,
    required this.measurementPublicationDraft,
  })  : _selectedPublicationManifestCanonicalBytes = _copyOpaqueExternalBytes(
          selectedPublicationManifestCanonicalBytes,
          maximumLength: kMaximumMeasurementPublicationCandidateManifestBytes,
          label: 'selected publication manifest',
        ),
        declaredArtifactTuples = _sortedUniqueArtifactTuples(
          declaredArtifactTuples,
        ),
        _assembledPublicationUploadCanonicalBytes = _copyOpaqueExternalBytes(
          assembledPublicationUploadCanonicalBytes,
          maximumLength: kMaximumMeasurementPublicationCandidateUploadBytes,
          label: 'assembled publication upload',
        ) {
    _validateTotalBytes();
  }

  /// Decodes byte-exact canonical candidate-proof bytes.
  factory MeasurementPublicationCandidateProofV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementPublicationCandidateProofV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'measurementPublicationCandidateProof',
      );

  /// Decodes a closed candidate proof and re-proves its nested reference.
  factory MeasurementPublicationCandidateProofV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'assembledPublicationUploadCanonicalBase64Url',
        'declaredArtifactBytesDigest',
        'declaredArtifactTuples',
        'kind',
        'measurementPublicationDraft',
        'reference',
        'schemaVersion',
        'selectedPublicationManifestCanonicalBase64Url',
      },
      requiredKeys: const {
        'assembledPublicationUploadCanonicalBase64Url',
        'declaredArtifactBytesDigest',
        'declaredArtifactTuples',
        'kind',
        'measurementPublicationDraft',
        'reference',
        'schemaVersion',
        'selectedPublicationManifestCanonicalBase64Url',
      },
      path: 'measurementPublicationCandidateProof',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'measurementPublicationCandidateProof',
    );
    final declaredArtifactTuples = reader.list('declaredArtifactTuples');
    if (declaredArtifactTuples.isEmpty ||
        declaredArtifactTuples.length >
            kMaximumMeasurementPublicationCandidateArtifactTupleCount) {
      throw const CanonicalFormatException(
        'measurementPublicationCandidateProof.declaredArtifactTuples '
        'exceeds its raw input bound',
      );
    }
    return _constructCandidate(
      'measurementPublicationCandidateProof',
      () {
        final proof = MeasurementPublicationCandidateProofV1(
          selectedPublicationManifestCanonicalBytes: _decodeBase64UrlNoPadding(
            reader.string('selectedPublicationManifestCanonicalBase64Url'),
            label: 'selectedPublicationManifestCanonicalBase64Url',
            maximumDecodedLength:
                kMaximumMeasurementPublicationCandidateManifestBytes,
          ),
          declaredArtifactTuples: [
            for (final value in declaredArtifactTuples)
              MeasurementPublicationCandidateArtifactTupleV1.fromJson(
                requireCanonicalObject(value, 'declaredArtifactTuples[]'),
              ),
          ],
          declaredArtifactBytesDigest: CanonicalDigest(
            reader.string('declaredArtifactBytesDigest'),
          ),
          assembledPublicationUploadCanonicalBytes: _decodeBase64UrlNoPadding(
            reader.string('assembledPublicationUploadCanonicalBase64Url'),
            label: 'assembledPublicationUploadCanonicalBase64Url',
            maximumDecodedLength:
                kMaximumMeasurementPublicationCandidateUploadBytes,
          ),
          measurementPublicationDraft: MeasurementPublicationDraftV1.fromJson(
            reader.object('measurementPublicationDraft'),
          ),
        );
        final reference = MeasurementPublicationCandidateReferenceV1.fromJson(
          reader.object('reference'),
        );
        if (reference != proof.reference) {
          throw ArgumentError(
            'The candidate proof reference must exactly recompute from its '
            'opaque closure and draft',
          );
        }
        return proof;
      },
    );
  }

  final Uint8List _selectedPublicationManifestCanonicalBytes;

  /// Defensive copy of exact publication-owned selected-manifest canonical
  /// bytes.
  ///
  /// Their canonical profile is external to this schema and is validated by a
  /// registered adapter.
  Uint8List get selectedPublicationManifestCanonicalBytes =>
      Uint8List.fromList(_selectedPublicationManifestCanonicalBytes);

  /// Sorted exact opaque declared-artifact tuples.
  final List<MeasurementPublicationCandidateArtifactTupleV1>
      declaredArtifactTuples;

  /// Registered-adapter digest of the exact declared artifact byte closure.
  final CanonicalDigest declaredArtifactBytesDigest;

  final Uint8List _assembledPublicationUploadCanonicalBytes;

  /// Defensive copy of exact publication-owned assembled-upload canonical
  /// bytes.
  ///
  /// Their canonical profile is external to this schema and is validated by a
  /// registered adapter.
  Uint8List get assembledPublicationUploadCanonicalBytes =>
      Uint8List.fromList(_assembledPublicationUploadCanonicalBytes);

  /// Exact target-neutral generated Measurement draft.
  final MeasurementPublicationDraftV1 measurementPublicationDraft;

  /// Candidate reference recomputed from every exact proof component.
  MeasurementPublicationCandidateReferenceV1 get reference =>
      recomputeReference();

  /// Recomputes the complete candidate reference from the proof inputs.
  MeasurementPublicationCandidateReferenceV1 recomputeReference() =>
      MeasurementPublicationCandidateReferenceV1(
        candidateDigest: canonicalSha256(
          CanonicalHashDomain.measurementPublicationCandidate,
          CanonicalJsonCodec.encode({
            'assembledPublicationUploadCanonicalBase64Url':
                _base64UrlNoPadding(_assembledPublicationUploadCanonicalBytes),
            'declaredArtifactBytesDigest': declaredArtifactBytesDigest.hex,
            'measurementPublicationDraft': measurementPublicationDraft.toJson(),
            'selectedPublicationManifestCanonicalBase64Url':
                _base64UrlNoPadding(_selectedPublicationManifestCanonicalBytes),
          }),
        ),
        selectedPublicationManifestDigest: canonicalSha256(
          CanonicalHashDomain.measurementPublicationCandidateManifest,
          _selectedPublicationManifestCanonicalBytes,
        ),
        declaredArtifactBytesDigest: declaredArtifactBytesDigest,
        assembledPublicationUploadDigest: canonicalSha256(
          CanonicalHashDomain.measurementPublicationCandidateUpload,
          _assembledPublicationUploadCanonicalBytes,
        ),
        measurementPublicationDraftDigest:
            measurementPublicationDraft.canonicalDigest,
      );

  @override
  CanonicalHashDomain get hashDomain =>
      CanonicalHashDomain.measurementPublicationCandidateProof;

  @override
  Map<String, Object?> toJson() => {
        'assembledPublicationUploadCanonicalBase64Url':
            _base64UrlNoPadding(_assembledPublicationUploadCanonicalBytes),
        'declaredArtifactBytesDigest': declaredArtifactBytesDigest.hex,
        'declaredArtifactTuples': [
          for (final tuple in declaredArtifactTuples) tuple.toJson(),
        ],
        'kind': 'measurementPublicationCandidateProof',
        'measurementPublicationDraft': measurementPublicationDraft.toJson(),
        'reference': reference.toJson(),
        'schemaVersion': kMeasurementSchemaVersion,
        'selectedPublicationManifestCanonicalBase64Url':
            _base64UrlNoPadding(_selectedPublicationManifestCanonicalBytes),
      };

  void _validateTotalBytes() {
    final draftBytes = measurementPublicationDraft.canonicalBytes;
    if (draftBytes.length > kMaximumMeasurementPublicationCandidateDraftBytes) {
      throw ArgumentError(
        'The candidate proof exceeds its target-neutral draft byte limit',
      );
    }
    final artifactClosureBytes = declaredArtifactTuples.fold<int>(
      0,
      (sum, tuple) => sum + tuple.canonicalTupleBytes.length,
    );
    if (artifactClosureBytes >
        kMaximumMeasurementPublicationCandidateArtifactClosureBytes) {
      throw ArgumentError(
        'The candidate proof exceeds its declared-artifact metadata limit',
      );
    }
    final total = _selectedPublicationManifestCanonicalBytes.length +
        _assembledPublicationUploadCanonicalBytes.length +
        draftBytes.length +
        artifactClosureBytes;
    if (total > kMaximumMeasurementPublicationCandidateProofBytes) {
      throw ArgumentError(
        'The candidate proof exceeds its bounded complete byte closure',
      );
    }
  }
}

List<MeasurementPublicationCandidateArtifactTupleV1>
    _sortedUniqueArtifactTuples(
  List<MeasurementPublicationCandidateArtifactTupleV1> values,
) {
  if (values.isEmpty ||
      values.length >
          kMaximumMeasurementPublicationCandidateArtifactTupleCount) {
    throw ArgumentError(
      'A candidate proof requires 1..'
      '$kMaximumMeasurementPublicationCandidateArtifactTupleCount '
      'declared artifact tuples',
    );
  }
  final copy = values.toList()
    ..sort(
      (left, right) => _base64UrlNoPadding(left.canonicalTupleBytes)
          .compareTo(_base64UrlNoPadding(right.canonicalTupleBytes)),
    );
  String? prior;
  for (final tuple in copy) {
    final key = _base64UrlNoPadding(tuple.canonicalTupleBytes);
    if (key == prior) {
      throw ArgumentError('Declared artifact tuples must be unique');
    }
    prior = key;
  }
  return List.unmodifiable(copy);
}

Uint8List _copyMeasurementCanonicalObject(
  List<int> bytes, {
  required int maximumLength,
  required String label,
}) {
  if (bytes.isEmpty || bytes.length > maximumLength) {
    throw ArgumentError.value(
      bytes.length,
      label,
      'Expected 1..$maximumLength canonical bytes',
    );
  }
  try {
    decodeCanonicalObject(bytes);
  } on CanonicalFormatException catch (error) {
    throw ArgumentError.value(
      bytes,
      label,
      'Expected canonical object: $error',
    );
  }
  return Uint8List.fromList(bytes);
}

/// Bounds and copies bytes whose canonical profile belongs to another owner.
///
/// The size check deliberately happens before reading an element or allocating
/// the defensive copy. This schema must not parse or reserialize external
/// bytes, because doing so would replace their owning contract's byte profile.
Uint8List _copyOpaqueExternalBytes(
  List<int> bytes, {
  required int maximumLength,
  required String label,
}) {
  final byteLength = bytes.length;
  if (byteLength == 0 || byteLength > maximumLength) {
    throw ArgumentError.value(
      byteLength,
      label,
      'Expected 1..$maximumLength opaque external bytes',
    );
  }
  final copy = Uint8List(byteLength);
  for (var index = 0; index < byteLength; index++) {
    final byte = bytes[index];
    if (byte < 0 || byte > 0xff) {
      throw ArgumentError.value(
        byte,
        label,
        'Expected octets in the range 0..255',
      );
    }
    copy[index] = byte;
  }
  return copy;
}

List<int> _decodeBase64UrlNoPadding(
  String value, {
  required String label,
  int? maximumDecodedLength,
}) {
  if (value.isEmpty || !_base64UrlNoPaddingPattern.hasMatch(value)) {
    throw ArgumentError.value(value, label, 'Expected unpadded base64url');
  }
  if (maximumDecodedLength != null &&
      value.length > _maximumBase64UrlNoPaddingLength(maximumDecodedLength)) {
    throw ArgumentError.value(
      value.length,
      label,
      'Expected at most $maximumDecodedLength decoded bytes',
    );
  }
  try {
    final decoded = base64Url.decode(base64Url.normalize(value));
    if (maximumDecodedLength != null && decoded.length > maximumDecodedLength) {
      throw const FormatException('decoded byte bound exceeded');
    }
    if (_base64UrlNoPadding(decoded) != value) {
      throw const FormatException('noncanonical base64url');
    }
    return decoded;
  } on FormatException {
    throw ArgumentError.value(value, label, 'Expected canonical base64url');
  }
}

String _base64UrlNoPadding(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

int _maximumBase64UrlNoPaddingLength(int byteLength) {
  final paddedLength = ((byteLength + 2) ~/ 3) * 4;
  return switch (byteLength % 3) {
    1 => paddedLength - 2,
    2 => paddedLength - 1,
    _ => paddedLength,
  };
}

final RegExp _base64UrlNoPaddingPattern = RegExp(r'^[A-Za-z0-9_-]+$');

T _constructCandidate<T>(String path, T Function() create) {
  try {
    return create();
    // Constructor admission failures must become canonical decoder failures.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}
