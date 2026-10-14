import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_shared/src/capability/capability_manifest.dart';
import 'package:restage_shared/src/flow_document/flow_document.dart';
import 'package:restage_shared/src/flow_document/flow_document_codec.dart';
import 'package:restage_shared/src/flow_document/flow_document_hash.dart';
import 'package:restage_shared/src/surface_feature_client_floor.dart';

/// Product surface category carried by a delivered document envelope.
///
/// The wire vocabulary is deliberately closed. Adding a product category is a
/// coordinated contract change rather than an application-defined string.
enum Surface {
  /// A surface used for onboarding flows.
  onboarding('onboarding'),

  /// A surface used for message flows.
  message('message'),

  /// A surface used for survey flows.
  survey('survey'),

  /// A surface used for a paywall (a single rendered screen, or a lowered
  /// multi-screen flow for a navigation paywall).
  paywall('paywall'),

  /// A surface with no specialized product semantics.
  general('general');

  const Surface(this.wireName);

  /// Stable wire discriminator for this surface type.
  final String wireName;

  /// Parses a surface type wire discriminator.
  static Surface fromWireName(String name) {
    for (final type in Surface.values) {
      if (type.wireName == name) return type;
    }
    throw FormatException('Unsupported surface "$name".');
  }
}

/// Deprecated compatibility spelling for [Surface].
@Deprecated('Use Surface instead.')
typedef SurfaceType = Surface;

/// The authored source shape for a publication.
enum SurfaceSourceKind {
  /// A standalone ordinary screen.
  screen('screen'),

  /// A specialized paywall source.
  paywall('paywall'),

  /// A flow declaration.
  flowGraph('flowGraph');

  const SurfaceSourceKind(this.wireName);

  /// Stable wire discriminator.
  final String wireName;

  /// Parses a strict source-kind discriminator.
  static SurfaceSourceKind fromWireName(String name) {
    for (final kind in values) {
      if (kind.wireName == name) return kind;
    }
    throw FormatException('Unsupported surface source kind "$name".');
  }
}

/// The artifact shape carried by a publication.
enum SurfacePayloadKind {
  /// One rendered RFW blob.
  blob('blob'),

  /// A flow document and its screen closure.
  flow('flow');

  const SurfacePayloadKind(this.wireName);

  /// Stable wire discriminator.
  final String wireName;

  /// Parses a strict payload-kind discriminator.
  static SurfacePayloadKind fromWireName(String name) {
    for (final kind in values) {
      if (kind.wireName == name) return kind;
    }
    throw FormatException('Unsupported surface payload kind "$name".');
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

  /// Subset icon fonts delivered with this payload, sorted by family then
  /// package (possibly empty).
  List<DeliveredIconFont> get iconFonts;

  /// Initial screen-local values, keyed by root widget or screen name, then by
  /// value key (possibly empty).
  Map<String, Map<String, Object>> get localSeeds;

  /// Opaque editor document state saved with a draft, or null.
  ///
  /// It is covered by [contentHash] but never published: a published payload
  /// carries none, and a device never reads it.
  Uint8List? get editorState;

  /// This payload without its [editorState]; the payload itself when it has
  /// none.
  SurfacePayload withoutEditorState();

  /// Whether this payload carries an icon-font or local-seed section. Such a
  /// payload requires [kSurfaceFeatureClientFloor].
  bool get carriesSections => iconFonts.isNotEmpty || localSeeds.isNotEmpty;

  /// Canonical payload bytes used as the content-hash domain.
  Uint8List get canonicalBytes;

  /// SHA-256 content hash for [canonicalBytes].
  String get contentHash;

  /// Decodes a canonical payload frame.
  /// [requireRequiredLibraries] requires the libraries section for v2 envelopes;
  /// otherwise older frames may decode to an empty list.
  /// [allowSections] controls whether icon-font and local-seed sections are accepted.
  static SurfacePayload decode(
    List<int> bytes, {
    bool requireRequiredLibraries = false,
    bool allowSections = true,
  }) {
    try {
      final reader = _PayloadReader(bytes);
      final kind = reader.readLengthPrefixedUtf8('payload kind');
      switch (kind) {
        case _flowPayloadKind:
          return _decodeFlowPayload(
            reader,
            requireRequiredLibraries: requireRequiredLibraries,
            allowSections: allowSections,
          );
        case _blobPayloadKind:
          return _decodeBlobPayload(
            reader,
            requireRequiredLibraries: requireRequiredLibraries,
            allowSections: allowSections,
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
    List<DeliveredIconFont> iconFonts = const [],
    Map<String, Map<String, Object>> localSeeds = const {},
    Uint8List? editorState,
  }) =>
      FlowSurfacePayload._create(
        flowDocument: flowDocument,
        screenBlobs: screenBlobs,
        requiredLibraries: requiredLibraries,
        iconFonts: iconFonts,
        localSeeds: localSeeds,
        editorState: editorState,
      );

  factory FlowSurfacePayload._create({
    required FlowDocument flowDocument,
    required Map<String, Uint8List> screenBlobs,
    required List<LibraryRequirement> requiredLibraries,
    required List<DeliveredIconFont> iconFonts,
    required Map<String, Map<String, Object>> localSeeds,
    Uint8List? editorState,
    _SeedWireMap? seedWire,
  }) {
    _checkEditorState(editorState);
    _checkIsomorphicScreenBlobs(flowDocument, screenBlobs);
    final frozenBlobs = Map<String, Uint8List>.unmodifiable({
      for (final entry in screenBlobs.entries)
        entry.key: _freezeBytes(entry.value),
    });
    final canonicalLibraries = _canonicalRequiredLibraries(requiredLibraries);
    final canonicalFonts = _canonicalIconFonts(iconFonts);
    final canonicalSeeds = _canonicalLocalSeeds(localSeeds);
    for (final root in canonicalSeeds.keys) {
      if (!frozenBlobs.containsKey(root)) {
        throw ArgumentError.value(
          root,
          'localSeeds',
          'must name a screen of the flow',
        );
      }
    }
    _checkSectionFloor(
      flowDocument.minClient,
      carriesSections: canonicalFonts.isNotEmpty || canonicalSeeds.isNotEmpty,
    );
    final frozenEditorState =
        editorState == null ? null : _freezeBytes(editorState);
    final canonicalBytes = _buildFlowCanonicalBytes(
      flowDocument: flowDocument,
      screenBlobs: frozenBlobs,
      requiredLibraries: canonicalLibraries,
      iconFonts: canonicalFonts,
      seedWire: seedWire ?? _seedWireOf(canonicalSeeds),
      editorState: frozenEditorState,
    );
    return FlowSurfacePayload._(
      flowDocument: flowDocument,
      screenBlobs: frozenBlobs,
      requiredLibraries: canonicalLibraries,
      iconFonts: canonicalFonts,
      localSeeds: canonicalSeeds,
      editorState: frozenEditorState,
      canonicalBytes: _freezeBytes(canonicalBytes),
      contentHash: 'sha256:${crypto.sha256.convert(canonicalBytes)}',
    );
  }

  const FlowSurfacePayload._({
    required this.flowDocument,
    required this.screenBlobs,
    required this.requiredLibraries,
    required this.iconFonts,
    required this.localSeeds,
    required this.editorState,
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

  @override
  final List<DeliveredIconFont> iconFonts;

  /// Initial screen-local values keyed by screen identifier.
  @override
  final Map<String, Map<String, Object>> localSeeds;

  /// Flow document carried by this payload.
  final FlowDocument flowDocument;

  /// Screen blobs keyed by screen identifier.
  final Map<String, Uint8List> screenBlobs;

  @override
  final Uint8List? editorState;

  @override
  FlowSurfacePayload withoutEditorState() {
    final state = editorState;
    if (state == null) return this;
    return SurfacePayload.decode(_withoutLastSection(_canonicalBytes, state))
        as FlowSurfacePayload;
  }

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
    List<DeliveredIconFont> iconFonts = const [],
    Map<String, Map<String, Object>> localSeeds = const {},
    Uint8List? editorState,
  }) =>
      BlobSurfacePayload._create(
        minClient: minClient,
        blob: blob,
        requiredLibraries: requiredLibraries,
        iconFonts: iconFonts,
        localSeeds: localSeeds,
        editorState: editorState,
      );

  factory BlobSurfacePayload._create({
    required int minClient,
    required Uint8List blob,
    required List<LibraryRequirement> requiredLibraries,
    required List<DeliveredIconFont> iconFonts,
    required Map<String, Map<String, Object>> localSeeds,
    Uint8List? editorState,
    _SeedWireMap? seedWire,
  }) {
    _checkEditorState(editorState);
    final frozenBlob = _freezeBytes(blob);
    final canonicalLibraries = _canonicalRequiredLibraries(requiredLibraries);
    final canonicalFonts = _canonicalIconFonts(iconFonts);
    final canonicalSeeds = _canonicalLocalSeeds(localSeeds);
    final frozenEditorState =
        editorState == null ? null : _freezeBytes(editorState);
    _checkSectionFloor(
      minClient,
      carriesSections: canonicalFonts.isNotEmpty || canonicalSeeds.isNotEmpty,
    );
    final canonicalBytes = _buildBlobCanonicalBytes(
      minClient: minClient,
      blob: frozenBlob,
      requiredLibraries: canonicalLibraries,
      iconFonts: canonicalFonts,
      seedWire: seedWire ?? _seedWireOf(canonicalSeeds),
      editorState: frozenEditorState,
    );
    return BlobSurfacePayload._(
      minClient: minClient,
      blob: frozenBlob,
      requiredLibraries: canonicalLibraries,
      iconFonts: canonicalFonts,
      localSeeds: canonicalSeeds,
      editorState: frozenEditorState,
      canonicalBytes: _freezeBytes(canonicalBytes),
      contentHash: 'sha256:${crypto.sha256.convert(canonicalBytes)}',
    );
  }

  const BlobSurfacePayload._({
    required this.minClient,
    required this.blob,
    required this.requiredLibraries,
    required this.iconFonts,
    required this.localSeeds,
    required this.editorState,
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

  @override
  final List<DeliveredIconFont> iconFonts;

  /// Initial screen-local values keyed by root widget name.
  @override
  final Map<String, Map<String, Object>> localSeeds;

  /// The single rendered-screen blob.
  final Uint8List blob;

  @override
  final Uint8List? editorState;

  @override
  BlobSurfacePayload withoutEditorState() {
    final state = editorState;
    if (state == null) return this;
    return SurfacePayload.decode(_withoutLastSection(_canonicalBytes, state))
        as BlobSurfacePayload;
  }

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

/// A subset icon font delivered inside a payload for one icon font family.
@immutable
final class DeliveredIconFont {
  /// Creates a delivered font for [family], optionally owned by [fontPackage].
  factory DeliveredIconFont({
    required String family,
    required Uint8List bytes,
    String? fontPackage,
  }) {
    if (family.isEmpty) {
      throw ArgumentError.value(family, 'family', 'must not be empty');
    }
    if (fontPackage != null && fontPackage.isEmpty) {
      throw ArgumentError.value(
        fontPackage,
        'fontPackage',
        'must be absent or non-empty',
      );
    }
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes.length, 'bytes', 'must not be empty');
    }
    return DeliveredIconFont._(family, fontPackage, _freezeBytes(bytes));
  }

  const DeliveredIconFont._(this.family, this.fontPackage, this.bytes);

  /// The icon font family the author's code points belong to.
  final String family;

  /// The package that declares [family], or null for an app or SDK font.
  final String? fontPackage;

  /// The font file (sfnt) bytes.
  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      other is DeliveredIconFont &&
      other.family == family &&
      other.fontPackage == fontPackage &&
      _bytesEqual(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(family, fontPackage, bytes.length);
}

/// A versioned document for delivering a product surface.
@immutable
final class SurfaceDocument {
  /// Creates a surface document envelope.
  factory SurfaceDocument({
    required Surface surfaceType,
    required String surfaceSlug,
    required int version,
    required int minClient,
    required SurfacePayload payload,
    required DateTime publishedAt,
    List<LibraryRequirement> requiredLibraries = const [],
  }) {
    if (payload.editorState != null) {
      throw ArgumentError.value(
        payload,
        'payload',
        'must not carry editor state',
      );
    }
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
  final Surface surfaceType;

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

/// The [SurfacePayload.payloadKind] value for a [FlowSurfacePayload].
///
/// Use this to distinguish a flow-shaped payload from a blob-shaped one
/// without a runtime type check.
const kFlowPayloadKind = 'flow';

/// The [SurfacePayload.payloadKind] value for a [BlobSurfacePayload].
///
/// See [kFlowPayloadKind].
const kBlobPayloadKind = 'blob';

// Internal aliases kept for the canonical-bytes builders + decoder switch —
// single source of truth.
const String _flowPayloadKind = kFlowPayloadKind;
const String _blobPayloadKind = kBlobPayloadKind;

SurfacePayload _decodeBlobPayload(
  _PayloadReader reader, {
  required bool requireRequiredLibraries,
  required bool allowSections,
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
  final sections = _readSections(reader, allowSections: allowSections);
  return BlobSurfacePayload._create(
    minClient: minClient,
    blob: blob,
    requiredLibraries: requiredLibraries,
    iconFonts: sections.iconFonts,
    localSeeds: sections.localSeeds,
    editorState: sections.editorState,
    seedWire: sections.seedWire,
  );
}

SurfacePayload _decodeFlowPayload(
  _PayloadReader reader, {
  required bool requireRequiredLibraries,
  required bool allowSections,
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
  final sections = _readSections(reader, allowSections: allowSections);
  try {
    return FlowSurfacePayload._create(
      flowDocument: flowDocument,
      screenBlobs: screenBlobs,
      requiredLibraries: requiredLibraries,
      iconFonts: sections.iconFonts,
      localSeeds: sections.localSeeds,
      editorState: sections.editorState,
      seedWire: sections.seedWire,
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
  required List<DeliveredIconFont> iconFonts,
  required _SeedWireMap seedWire,
  Uint8List? editorState,
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
  _addSections(builder, iconFonts, seedWire, editorState: editorState);
  return builder.toBytes();
}

Uint8List _buildBlobCanonicalBytes({
  required int minClient,
  required Uint8List blob,
  required List<LibraryRequirement> requiredLibraries,
  required List<DeliveredIconFont> iconFonts,
  required _SeedWireMap seedWire,
  Uint8List? editorState,
}) {
  final builder = BytesBuilder();
  _addLengthPrefixedBytes(builder, utf8.encode(_blobPayloadKind));
  _addUint32(builder, minClient);
  _addLengthPrefixedBytes(builder, blob);
  _addRequiredLibraries(builder, requiredLibraries);
  _addSections(builder, iconFonts, seedWire, editorState: editorState);
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

const int _iconFontsSectionTag = 1;
const int _localSeedsSectionTag = 2;
const int _editorStateSectionTag = 3;

const int _seedString = 1;
const int _seedInt = 2;
const int _seedDouble = 3;
const int _seedBool = 4;

const int _maxSeedStringLength = 4096;
final RegExp _seedKeyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$');

void _checkSectionFloor(int minClient, {required bool carriesSections}) {
  if (carriesSections && minClient < kSurfaceFeatureClientFloor) {
    throw ArgumentError.value(
      minClient,
      'minClient',
      'must be at least $kSurfaceFeatureClientFloor for a payload with icon '
          'fonts or local seeds',
    );
  }
}

void _checkEditorState(Uint8List? editorState) {
  if (editorState != null && editorState.isEmpty) {
    throw ArgumentError.value(
      editorState.length,
      'editorState',
      'must be absent or non-empty',
    );
  }
}

/// [frame] without its trailing editor-state section, which is always the
/// last one: `[u32 tag][u32 length][state]`.
Uint8List _withoutLastSection(Uint8List frame, Uint8List state) =>
    Uint8List.sublistView(frame, 0, frame.length - 8 - state.length);

int _compareIconFonts(DeliveredIconFont a, DeliveredIconFont b) {
  final byFamily = a.family.compareTo(b.family);
  if (byFamily != 0) return byFamily;
  return (a.fontPackage ?? '').compareTo(b.fontPackage ?? '');
}

List<DeliveredIconFont> _canonicalIconFonts(List<DeliveredIconFont> fonts) {
  final sorted = List<DeliveredIconFont>.of(fonts)..sort(_compareIconFonts);
  for (var index = 1; index < sorted.length; index += 1) {
    if (_compareIconFonts(sorted[index - 1], sorted[index]) == 0) {
      throw ArgumentError.value(
        sorted[index].family,
        'iconFonts',
        'duplicate family and package',
      );
    }
  }
  return List<DeliveredIconFont>.unmodifiable(sorted);
}

Map<String, Map<String, Object>> _canonicalLocalSeeds(
  Map<String, Map<String, Object>> seeds,
) {
  final roots = seeds.keys.toList()..sort();
  return Map<String, Map<String, Object>>.unmodifiable({
    for (final root in roots) root: _canonicalSeedMap(root, seeds[root]!),
  });
}

Map<String, Object> _canonicalSeedMap(String root, Map<String, Object> seed) {
  if (root.isEmpty) {
    throw ArgumentError.value(root, 'localSeeds', 'root must not be empty');
  }
  if (seed.isEmpty) {
    throw ArgumentError.value(root, 'localSeeds', 'root has no values');
  }
  final keys = seed.keys.toList()..sort();
  return Map<String, Object>.unmodifiable({
    for (final key in keys) key: _checkSeedValue(key, seed[key]),
  });
}

Object _checkSeedValue(String key, Object? value) {
  if (!_seedKeyPattern.hasMatch(key)) {
    throw ArgumentError.value(key, 'localSeeds', 'invalid key');
  }
  if (value is bool) return value;
  if (value is String) {
    if (value.length > _maxSeedStringLength) {
      throw ArgumentError.value(
        value.length,
        'localSeeds',
        'string "$key" exceeds $_maxSeedStringLength UTF-16 units',
      );
    }
    return value;
  }
  if (value is num) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'localSeeds', 'must be finite');
    }
    return value;
  }
  throw ArgumentError.value(
    value,
    'localSeeds',
    'value "$key" must be a string, number or bool',
  );
}

/// Appends each non-empty section as `[u32 tag][section]`, tags ascending. A
/// payload without sections keeps the frame it had before sections existed.
void _addSections(
  BytesBuilder builder,
  List<DeliveredIconFont> iconFonts,
  _SeedWireMap localSeeds, {
  Uint8List? editorState,
}) {
  if (iconFonts.isNotEmpty) {
    _addUint32(builder, _iconFontsSectionTag);
    _addUint32(builder, iconFonts.length);
    for (final font in iconFonts) {
      _addLengthPrefixedBytes(builder, utf8.encode(font.family));
      final package = font.fontPackage;
      _addUint32(builder, package == null ? 0 : 1);
      if (package != null) {
        _addLengthPrefixedBytes(builder, utf8.encode(package));
      }
      _addLengthPrefixedBytes(builder, font.bytes);
    }
  }
  if (localSeeds.isNotEmpty) {
    _addUint32(builder, _localSeedsSectionTag);
    _addUint32(builder, localSeeds.length);
    for (final root in localSeeds.entries) {
      _addLengthPrefixedBytes(builder, utf8.encode(root.key));
      _addUint32(builder, root.value.length);
      for (final entry in root.value.entries) {
        _addLengthPrefixedBytes(builder, utf8.encode(entry.key));
        _addUint32(builder, entry.value.type);
        _addLengthPrefixedBytes(builder, utf8.encode(entry.value.text));
      }
    }
  }
  if (editorState != null) {
    _addUint32(builder, _editorStateSectionTag);
    _addLengthPrefixedBytes(builder, editorState);
  }
}

typedef _Sections = ({
  List<DeliveredIconFont> iconFonts,
  Map<String, Map<String, Object>> localSeeds,
  Uint8List? editorState,
  _SeedWireMap? seedWire,
});

/// A seed value's wire type and spelling.
typedef _SeedWire = ({int type, String text});

typedef _SeedWireMap = Map<String, Map<String, _SeedWire>>;

/// Wire form of canonical seeds. A decoded payload keeps the form it was read
/// with instead, so it re-encodes to the same bytes on every platform.
_SeedWireMap _seedWireOf(Map<String, Map<String, Object>> seeds) => {
      for (final root in seeds.entries)
        root.key: {
          for (final entry in root.value.entries)
            entry.key: switch (entry.value) {
              final bool value => (
                  type: _seedBool,
                  text: value ? 'true' : 'false',
                ),
              final String value => (type: _seedString, text: value),
              final int value => (type: _seedInt, text: value.toString()),
              final Object value => (
                  type: _seedDouble,
                  text: (value as double).toString(),
                ),
            },
        },
    };

/// Reads the sections [_addSections] writes and requires the frame to end.
/// Order, emptiness and value spelling are checked so only canonical bytes
/// decode.
_Sections _readSections(
  _PayloadReader reader, {
  required bool allowSections,
}) {
  var iconFonts = const <DeliveredIconFont>[];
  Uint8List? editorState;
  var localSeeds = const <String, Map<String, Object>>{};
  _SeedWireMap? seedWire;
  var previousTag = 0;
  while (reader.hasRemaining) {
    final tag = reader.readUint32('section tag');
    if (!allowSections) {
      throw const FormatException(
        'This payload format does not carry icon-font or local-seed sections.',
      );
    }
    if (tag <= previousTag) {
      throw FormatException('Payload section $tag is out of order.');
    }
    previousTag = tag;
    switch (tag) {
      case _iconFontsSectionTag:
        iconFonts = _readIconFonts(reader);
      case _localSeedsSectionTag:
        (localSeeds, seedWire) = _readLocalSeeds(reader);
      case _editorStateSectionTag:
        editorState = reader.readLengthPrefixedBytes('editor state');
        if (editorState.isEmpty) {
          throw const FormatException(
            'An editor-state section must not be empty.',
          );
        }
      default:
        throw FormatException('Unsupported payload section $tag.');
    }
  }
  return (
    iconFonts: iconFonts,
    localSeeds: localSeeds,
    editorState: editorState,
    seedWire: seedWire,
  );
}

List<DeliveredIconFont> _readIconFonts(_PayloadReader reader) {
  final count = reader.readUint32('icon font count');
  if (count == 0) {
    throw const FormatException('An icon-font section must not be empty.');
  }
  final fonts = <DeliveredIconFont>[];
  for (var index = 0; index < count; index += 1) {
    final family = reader.readLengthPrefixedUtf8('icon font family');
    final hasPackage = reader.readUint32('icon font package flag');
    if (hasPackage > 1) {
      throw const FormatException('Invalid icon font package flag.');
    }
    final package = hasPackage == 1
        ? reader.readLengthPrefixedUtf8('icon font package')
        : null;
    final bytes = reader.readLengthPrefixedBytes('icon font');
    final font = DeliveredIconFont(
      family: family,
      fontPackage: package,
      bytes: bytes,
    );
    if (fonts.isNotEmpty && _compareIconFonts(fonts.last, font) >= 0) {
      throw const FormatException(
        'Icon fonts must be strictly ascending by family and package.',
      );
    }
    fonts.add(font);
  }
  return fonts;
}

(Map<String, Map<String, Object>>, _SeedWireMap) _readLocalSeeds(
  _PayloadReader reader,
) {
  final rootCount = reader.readUint32('local seed root count');
  if (rootCount == 0) {
    throw const FormatException('A local-seed section must not be empty.');
  }
  final seeds = <String, Map<String, Object>>{};
  final wire = <String, Map<String, _SeedWire>>{};
  String? previousRoot;
  for (var index = 0; index < rootCount; index += 1) {
    final root = reader.readLengthPrefixedUtf8('local seed root');
    if (previousRoot != null && root.compareTo(previousRoot) <= 0) {
      throw const FormatException(
        'Local seed roots must be strictly ascending.',
      );
    }
    previousRoot = root;
    final entryCount = reader.readUint32('local seed count');
    final values = <String, Object>{};
    final spelled = <String, _SeedWire>{};
    String? previousKey;
    for (var entry = 0; entry < entryCount; entry += 1) {
      final key = reader.readLengthPrefixedUtf8('local seed key');
      if (previousKey != null && key.compareTo(previousKey) <= 0) {
        throw const FormatException(
          'Local seed keys must be strictly ascending.',
        );
      }
      previousKey = key;
      final type = reader.readUint32('local seed type');
      final text = reader.readLengthPrefixedUtf8('local seed value');
      values[key] = _parseSeedValue(type, text);
      spelled[key] = (type: type, text: text);
    }
    seeds[root] = values;
    wire[root] = spelled;
  }
  return (seeds, wire);
}

Object _parseSeedValue(int type, String text) {
  switch (type) {
    case _seedString:
      return text;
    case _seedBool:
      if (text != 'true' && text != 'false') {
        throw FormatException('Invalid local seed bool "$text".');
      }
      return text == 'true';
    case _seedInt:
      final parsed = int.tryParse(text);
      if (parsed == null || parsed.toString() != text) {
        throw FormatException('Invalid local seed int "$text".');
      }
      return parsed;
    case _seedDouble:
      final parsed = double.tryParse(text);
      if (parsed == null || text.trim() != text) {
        throw FormatException('Invalid local seed double "$text".');
      }
      return parsed;
    default:
      throw FormatException('Unsupported local seed type $type.');
  }
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
