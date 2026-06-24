import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_shared/src/capability/capability_manifest.dart';
import 'package:restage_shared/src/flow_document/flow_document.dart';
import 'package:restage_shared/src/flow_document/flow_document_codec.dart';
import 'package:restage_shared/src/flow_document/flow_document_hash.dart';

/// Product surface category carried by a delivered document envelope.
enum SurfaceType {
  /// A surface used for onboarding flows.
  onboarding('onboarding'),

  /// A surface used for message flows.
  message('message'),

  /// A surface used for survey flows.
  survey('survey'),

  /// A surface used for a paywall (a single rendered screen, or a lowered
  /// multi-screen flow for a navigation paywall).
  paywall('paywall');

  const SurfaceType(this.wireName);

  /// Stable wire discriminator for this surface type.
  final String wireName;

  /// Parses a surface type wire discriminator.
  static SurfaceType fromWireName(String name) {
    for (final type in SurfaceType.values) {
      if (type.wireName == name) return type;
    }
    throw FormatException('Unsupported surface type "$name".');
  }
}

/// Payload carried inside a surface document envelope.
sealed class SurfacePayload {
  /// Creates a surface payload.
  const SurfacePayload();

  /// Stable payload-kind discriminator.
  String get payloadKind;

  /// Minimum client capability required to render this payload.
  ///
  /// A flow derives it from its document; a blob carries it directly. The
  /// envelope cross-checks its own `minClient` against this value, so it is
  /// always anchored against the hashed payload.
  int get minClient;

  /// Custom widget libraries this payload requires, canonical (sorted by
  /// namespace, possibly empty).
  ///
  /// Carried inside the hashed canonical bytes — exactly like [minClient] — so
  /// the envelope can cross-check its own header copy against a tamper-evident
  /// value. A pre-version-2 payload frame carries no such section and decodes
  /// to the empty list.
  List<LibraryRequirement> get requiredLibraries;

  /// Canonical payload bytes used as the content-hash domain.
  Uint8List get canonicalBytes;

  /// SHA-256 content hash for [canonicalBytes].
  String get contentHash;

  /// Decodes a canonical payload frame.
  ///
  /// When [requireRequiredLibraries] is true the frame MUST carry a
  /// required-libraries section (the envelope codec passes this for a
  /// format-version-2 envelope, so a v2 payload missing its section fails
  /// closed instead of silently decoding to the empty list). The default
  /// (false) preserves the standalone/cached-payload path, where a
  /// pre-version-2 frame is exactly-consuming and decodes to the empty list.
  static SurfacePayload decode(
    List<int> bytes, {
    bool requireRequiredLibraries = false,
  }) {
    try {
      final reader = _PayloadReader(bytes);
      final kind = reader.readLengthPrefixedUtf8('payload kind');
      switch (kind) {
        case _flowPayloadKind:
          return _decodeFlowPayload(
            reader,
            requireRequiredLibraries: requireRequiredLibraries,
          );
        case _blobPayloadKind:
          return _decodeBlobPayload(
            reader,
            requireRequiredLibraries: requireRequiredLibraries,
          );
        default:
          throw FormatException('Unsupported surface payload kind "$kind".');
      }
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      if (error is ArgumentError) {
        throw FormatException('Invalid surface payload: ${error.message}');
      }
      rethrow;
    }
  }
}

/// Flow document payload plus the screen blobs it references.
@immutable
final class FlowSurfacePayload extends SurfacePayload {
  /// Creates a flow payload and verifies that blobs match the flow document.
  factory FlowSurfacePayload({
    required FlowDocument flowDocument,
    required Map<String, Uint8List> screenBlobs,
    List<LibraryRequirement> requiredLibraries = const [],
  }) {
    _checkIsomorphicScreenBlobs(flowDocument, screenBlobs);
    final frozenBlobs = Map<String, Uint8List>.unmodifiable({
      for (final entry in screenBlobs.entries)
        entry.key: _freezeBytes(entry.value),
    });
    final canonicalLibraries = _canonicalRequiredLibraries(requiredLibraries);
    final canonicalBytes = _buildFlowCanonicalBytes(
      flowDocument: flowDocument,
      screenBlobs: frozenBlobs,
      requiredLibraries: canonicalLibraries,
    );
    return FlowSurfacePayload._(
      flowDocument: flowDocument,
      screenBlobs: frozenBlobs,
      requiredLibraries: canonicalLibraries,
      canonicalBytes: _freezeBytes(canonicalBytes),
      contentHash: 'sha256:${crypto.sha256.convert(canonicalBytes)}',
    );
  }

  const FlowSurfacePayload._({
    required this.flowDocument,
    required this.screenBlobs,
    required this.requiredLibraries,
    required Uint8List canonicalBytes,
    required this.contentHash,
  }) : _canonicalBytes = canonicalBytes;

  /// Flow payload-kind discriminator.
  @override
  String get payloadKind => _flowPayloadKind;

  /// Minimum client capability, derived from the embedded flow document.
  @override
  int get minClient => flowDocument.minClient;

  /// Custom widget libraries this flow requires, canonical (sorted by
  /// namespace). Carried in the flow payload frame, not inside the flow
  /// document, so the document's own contract is untouched.
  @override
  final List<LibraryRequirement> requiredLibraries;

  /// Flow document carried by this payload.
  final FlowDocument flowDocument;

  /// Screen blobs keyed by screen identifier.
  final Map<String, Uint8List> screenBlobs;

  final Uint8List _canonicalBytes;

  /// Canonical payload bytes used as the content-hash domain.
  @override
  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);

  /// SHA-256 content hash for [canonicalBytes].
  @override
  final String contentHash;

  @override
  bool operator ==(Object other) {
    return other is FlowSurfacePayload &&
        _bytesEqual(_canonicalBytes, other._canonicalBytes);
  }

  @override
  int get hashCode => contentHash.hashCode;
}

/// A single rendered-screen payload: one blob plus the minimum client
/// capability required to render it.
///
/// Unlike a flow (which embeds its minimum client inside the flow document),
/// a raw blob has no place to carry that floor, so [minClient] is an explicit
/// field — and it is written into the canonical bytes so the content hash
/// covers it. That keeps the envelope's minClient cross-check anchored against
/// a hashed value (tamper-evident), exactly as a flow's is.
@immutable
final class BlobSurfacePayload extends SurfacePayload {
  /// Creates a blob payload carrying [blob] with an explicit [minClient] floor.
  factory BlobSurfacePayload({
    required int minClient,
    required Uint8List blob,
    List<LibraryRequirement> requiredLibraries = const [],
  }) {
    final frozenBlob = _freezeBytes(blob);
    final canonicalLibraries = _canonicalRequiredLibraries(requiredLibraries);
    final canonicalBytes = _buildBlobCanonicalBytes(
      minClient: minClient,
      blob: frozenBlob,
      requiredLibraries: canonicalLibraries,
    );
    return BlobSurfacePayload._(
      minClient: minClient,
      blob: frozenBlob,
      requiredLibraries: canonicalLibraries,
      canonicalBytes: _freezeBytes(canonicalBytes),
      contentHash: 'sha256:${crypto.sha256.convert(canonicalBytes)}',
    );
  }

  const BlobSurfacePayload._({
    required this.minClient,
    required this.blob,
    required this.requiredLibraries,
    required Uint8List canonicalBytes,
    required this.contentHash,
  }) : _canonicalBytes = canonicalBytes;

  /// Blob payload-kind discriminator.
  @override
  String get payloadKind => _blobPayloadKind;

  /// Minimum client capability required to render [blob]. Carried in the
  /// canonical bytes so the content hash covers it.
  @override
  final int minClient;

  /// Custom widget libraries this blob requires, canonical (sorted by
  /// namespace). Carried in the canonical bytes so the content hash covers it.
  @override
  final List<LibraryRequirement> requiredLibraries;

  /// The single rendered-screen blob.
  final Uint8List blob;

  final Uint8List _canonicalBytes;

  /// Canonical payload bytes used as the content-hash domain.
  @override
  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);

  /// SHA-256 content hash for [canonicalBytes].
  @override
  final String contentHash;

  @override
  bool operator ==(Object other) {
    return other is BlobSurfacePayload &&
        _bytesEqual(_canonicalBytes, other._canonicalBytes);
  }

  @override
  int get hashCode => contentHash.hashCode;
}

/// A versioned document for delivering a product surface.
@immutable
final class SurfaceDocument {
  /// Creates a surface document envelope.
  factory SurfaceDocument({
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required int version,
    required int minClient,
    required SurfacePayload payload,
    required DateTime publishedAt,
    List<LibraryRequirement> requiredLibraries = const [],
  }) {
    if (minClient != payload.minClient) {
      throw ArgumentError.value(
        minClient,
        'minClient',
        'must match the payload minimum client',
      );
    }
    final canonicalLibraries = _canonicalRequiredLibraries(requiredLibraries);
    // Cross-check the envelope-level requirement against the hashed payload's,
    // exactly as minClient is cross-checked — the payload copy is
    // tamper-evident (covered by the content hash); the envelope copy must
    // agree with it.
    if (!_requiredLibrariesEqual(
      canonicalLibraries,
      payload.requiredLibraries,
    )) {
      throw ArgumentError.value(
        requiredLibraries,
        'requiredLibraries',
        'must match the payload required libraries',
      );
    }
    return SurfaceDocument._(
      surfaceType: surfaceType,
      surfaceSlug: surfaceSlug,
      version: version,
      minClient: minClient,
      requiredLibraries: canonicalLibraries,
      payload: payload,
      contentHash: payload.contentHash,
      publishedAt: publishedAt.toUtc(),
    );
  }

  const SurfaceDocument._({
    required this.surfaceType,
    required this.surfaceSlug,
    required this.version,
    required this.minClient,
    required this.requiredLibraries,
    required this.payload,
    required this.contentHash,
    required this.publishedAt,
  });

  /// Surface category carried by this document.
  final SurfaceType surfaceType;

  /// Stable surface identifier within its [surfaceType].
  final String surfaceSlug;

  /// Version of this surface document.
  final int version;

  /// Minimum client capability required by this document.
  final int minClient;

  /// Custom widget libraries required to render this document, canonical
  /// (sorted by namespace, possibly empty). Mirrors the hashed payload copy.
  final List<LibraryRequirement> requiredLibraries;

  /// Payload carried by this document.
  final SurfacePayload payload;

  /// Content hash derived from [payload].
  final String contentHash;

  /// UTC publication timestamp.
  final DateTime publishedAt;

  @override
  bool operator ==(Object other) {
    return other is SurfaceDocument &&
        other.surfaceType == surfaceType &&
        other.surfaceSlug == surfaceSlug &&
        other.version == version &&
        other.minClient == minClient &&
        _requiredLibrariesEqual(other.requiredLibraries, requiredLibraries) &&
        other.payload == payload &&
        other.contentHash == contentHash &&
        other.publishedAt == publishedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      surfaceType,
      surfaceSlug,
      version,
      minClient,
      Object.hashAll(requiredLibraries),
      payload,
      contentHash,
      publishedAt,
    );
  }
}

/// Order-sensitive element equality for two canonical (sorted) requirement
/// lists. Both sides are canonicalized at construction, so this is a
/// position-wise compare.
bool _requiredLibrariesEqual(
  List<LibraryRequirement> a,
  List<LibraryRequirement> b,
) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

const _flowPayloadKind = 'flow';
const _blobPayloadKind = 'blob';

SurfacePayload _decodeBlobPayload(
  _PayloadReader reader, {
  required bool requireRequiredLibraries,
}) {
  final minClient = reader.readUint32('blob minClient');
  final blob = reader.readLengthPrefixedBytes('blob');
  // A format-version-2 frame appends a required-libraries section after the
  // blob; a pre-version-2 frame is exactly-consuming, so its absence decodes to
  // the empty list — UNLESS the caller knows the frame is version 2, in which
  // case a missing section fails closed. After the optional section the frame
  // must be fully consumed.
  final requiredLibraries =
      _readOptionalRequiredLibraries(reader, requireRequiredLibraries);
  if (reader.hasRemaining) {
    throw const FormatException('Unexpected trailing payload bytes.');
  }
  return BlobSurfacePayload(
    minClient: minClient,
    blob: blob,
    requiredLibraries: requiredLibraries,
  );
}

SurfacePayload _decodeFlowPayload(
  _PayloadReader reader, {
  required bool requireRequiredLibraries,
}) {
  final flowDocumentJson = reader.readLengthPrefixedUtf8('flow document');
  final flowDocument = FlowDocumentCodec.decodeJson(flowDocumentJson);
  final screenCount = reader.readUint32('screen count');
  final screenBlobs = <String, Uint8List>{};
  for (var index = 0; index < screenCount; index += 1) {
    final id = reader.readLengthPrefixedUtf8('screen id');
    if (screenBlobs.containsKey(id)) {
      throw FormatException('Duplicate screen blob id "$id".');
    }
    screenBlobs[id] = reader.readLengthPrefixedBytes('screen blob');
  }
  // A format-version-2 frame appends a required-libraries section after the
  // screen blobs; a pre-version-2 frame is exactly-consuming, so its absence
  // decodes to the empty list — UNLESS the caller knows the frame is version 2,
  // in which case a missing section fails closed. After the optional section
  // the frame must be fully consumed.
  final requiredLibraries =
      _readOptionalRequiredLibraries(reader, requireRequiredLibraries);
  if (reader.hasRemaining) {
    throw const FormatException('Unexpected trailing payload bytes.');
  }
  try {
    return FlowSurfacePayload(
      flowDocument: flowDocument,
      screenBlobs: screenBlobs,
      requiredLibraries: requiredLibraries,
    );
  } on Object catch (error) {
    if (error is ArgumentError) {
      throw FormatException('Invalid flow payload: ${error.message}');
    }
    rethrow;
  }
}

void _checkIsomorphicScreenBlobs(
  FlowDocument flowDocument,
  Map<String, Uint8List> screenBlobs,
) {
  final artifactIds = flowDocument.screenArtifacts.keys.toSet();
  final blobIds = screenBlobs.keys.toSet();
  if (artifactIds.length != blobIds.length ||
      !artifactIds.containsAll(blobIds)) {
    throw ArgumentError.value(
      screenBlobs.keys.toList(),
      'screenBlobs',
      'must match the flow document screen artifacts',
    );
  }

  for (final id in artifactIds) {
    final blob = screenBlobs[id];
    if (blob == null) {
      throw ArgumentError.value(
        screenBlobs.keys.toList(),
        'screenBlobs',
        'must include a blob for every screen artifact',
      );
    }
    final artifact = flowDocument.screenArtifacts[id]!;
    final actualHash = FlowContentHash.compute(blob);
    if (actualHash != artifact.contentHash) {
      throw ArgumentError(
        artifact.contentHash.diagnosticForMismatch(
          path: id,
          actual: actualHash,
        ),
      );
    }
  }
}

Uint8List _buildFlowCanonicalBytes({
  required FlowDocument flowDocument,
  required Map<String, Uint8List> screenBlobs,
  required List<LibraryRequirement> requiredLibraries,
}) {
  final builder = BytesBuilder();
  _addLengthPrefixedBytes(builder, utf8.encode(_flowPayloadKind));
  _addLengthPrefixedBytes(
    builder,
    FlowDocumentCodec.encodeCanonicalJson(flowDocument),
  );
  _addUint32(builder, screenBlobs.length);
  final screenIds = screenBlobs.keys.toList()..sort();
  for (final id in screenIds) {
    _addLengthPrefixedBytes(builder, utf8.encode(id));
    _addLengthPrefixedBytes(builder, screenBlobs[id]!);
  }
  _addRequiredLibraries(builder, requiredLibraries);
  return builder.toBytes();
}

Uint8List _buildBlobCanonicalBytes({
  required int minClient,
  required Uint8List blob,
  required List<LibraryRequirement> requiredLibraries,
}) {
  final builder = BytesBuilder();
  _addLengthPrefixedBytes(builder, utf8.encode(_blobPayloadKind));
  _addUint32(builder, minClient);
  _addLengthPrefixedBytes(builder, blob);
  _addRequiredLibraries(builder, requiredLibraries);
  return builder.toBytes();
}

/// Returns [requiredLibraries] in canonical form: sorted by namespace, frozen.
/// The sole canonicalization point shared by all three constructors, so the
/// wire bytes are deterministic regardless of caller input order.
///
/// Validates the same invariants the wire decoder ([_readRequiredLibraries])
/// enforces — non-empty namespace, `minVersion >= 1`, no duplicate namespace —
/// failing loud with an [ArgumentError] (release-safe, unlike the
/// [LibraryRequirement] constructor's debug-only asserts). This keeps the
/// construct/encode side symmetric with decode: a value that would not decode
/// cannot be constructed.
List<LibraryRequirement> _canonicalRequiredLibraries(
  List<LibraryRequirement> requiredLibraries,
) {
  final sorted = List<LibraryRequirement>.of(requiredLibraries)
    ..sort((a, b) => a.namespace.compareTo(b.namespace));
  String? previousNamespace;
  for (final requirement in sorted) {
    if (requirement.namespace.isEmpty) {
      throw ArgumentError.value(
        requirement.namespace,
        'requiredLibraries',
        'namespace must not be empty',
      );
    }
    if (requirement.minVersion < 1) {
      throw ArgumentError.value(
        requirement.minVersion,
        'requiredLibraries',
        'minVersion must be >= 1',
      );
    }
    if (previousNamespace != null &&
        requirement.namespace == previousNamespace) {
      throw ArgumentError.value(
        requirement.namespace,
        'requiredLibraries',
        'duplicate namespace',
      );
    }
    previousNamespace = requirement.namespace;
  }
  return List<LibraryRequirement>.unmodifiable(sorted);
}

/// Appends the canonical required-libraries section to a payload frame:
/// `[u32 count]` then, per entry in namespace order,
/// `[u32 nsLen][ns utf8][u32 minVersion]`. Always written (count 0 for the
/// empty list) so a format-version-2 frame is self-describing.
void _addRequiredLibraries(
  BytesBuilder builder,
  List<LibraryRequirement> requiredLibraries,
) {
  _addUint32(builder, requiredLibraries.length);
  for (final requirement in requiredLibraries) {
    _addLengthPrefixedBytes(builder, utf8.encode(requirement.namespace));
    _addUint32(builder, requirement.minVersion);
  }
}

/// Reads the trailing required-libraries section if present. A frame with no
/// trailing bytes is a pre-version-2 frame and decodes to the empty list —
/// unless [require] is set (the caller knows it is a version-2 frame), in which
/// case a missing section fails closed rather than silently defaulting.
List<LibraryRequirement> _readOptionalRequiredLibraries(
  _PayloadReader reader,
  bool require,
) {
  if (reader.hasRemaining) return _readRequiredLibraries(reader);
  if (require) {
    throw const FormatException(
      'A format-version-2 payload is missing its required-libraries section.',
    );
  }
  return const [];
}

/// Reads a required-libraries section written by [_addRequiredLibraries].
///
/// Validates the wire is canonical and well-formed — entries strictly
/// ascending by namespace (which also rejects duplicates), each namespace
/// non-empty, each `minVersion >= 1` — so a tampered or non-canonical frame
/// fails closed rather than decoding to a value that would not re-encode to
/// the same bytes. Symmetric with the constructor's invariants.
List<LibraryRequirement> _readRequiredLibraries(_PayloadReader reader) {
  final count = reader.readUint32('requiredLibraries count');
  final libraries = <LibraryRequirement>[];
  String? previousNamespace;
  for (var index = 0; index < count; index += 1) {
    final namespace =
        reader.readLengthPrefixedUtf8('requiredLibrary namespace');
    final minVersion = reader.readUint32('requiredLibrary minVersion');
    if (namespace.isEmpty) {
      throw const FormatException(
        'requiredLibrary namespace must not be empty.',
      );
    }
    if (minVersion < 1) {
      throw FormatException(
        'requiredLibrary minVersion must be >= 1, got $minVersion.',
      );
    }
    if (previousNamespace != null &&
        namespace.compareTo(previousNamespace) <= 0) {
      throw FormatException(
        'requiredLibraries must be strictly ascending by namespace; '
        '"$namespace" does not follow "$previousNamespace".',
      );
    }
    previousNamespace = namespace;
    libraries.add(
      LibraryRequirement(namespace: namespace, minVersion: minVersion),
    );
  }
  return libraries;
}

void _addLengthPrefixedBytes(BytesBuilder builder, List<int> bytes) {
  _addUint32(builder, bytes.length);
  builder.add(bytes);
}

void _addUint32(BytesBuilder builder, int value) {
  if (value < 0 || value > 0xFFFFFFFF) {
    throw ArgumentError.value(value, 'value', 'must fit in u32');
  }
  final bytes = Uint8List(4);
  ByteData.view(bytes.buffer).setUint32(0, value);
  builder.add(bytes);
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Uint8List _freezeBytes(List<int> bytes) {
  return Uint8List.fromList(bytes).asUnmodifiableView();
}

final class _PayloadReader {
  _PayloadReader(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get hasRemaining => _offset != _bytes.length;

  int readUint32(String label) {
    _ensureAvailable(4, label);
    final value = ByteData.view(_bytes.buffer).getUint32(_offset);
    _offset += 4;
    return value;
  }

  String readLengthPrefixedUtf8(String label) {
    try {
      return utf8.decode(readLengthPrefixedBytes(label));
    } on FormatException catch (error) {
      throw FormatException('Invalid UTF-8 for $label: ${error.message}');
    }
  }

  Uint8List readLengthPrefixedBytes(String label) {
    final length = readUint32('$label length');
    _ensureAvailable(length, label);
    final bytes = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return Uint8List.fromList(bytes);
  }

  void _ensureAvailable(int length, String label) {
    if (_offset + length > _bytes.length) {
      throw FormatException('Truncated $label.');
    }
  }
}
