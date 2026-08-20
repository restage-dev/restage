// V1 publication and delivery DTOs mirror their frozen wire fields.
// ignore_for_file: public_member_api_docs, prefer_constructors_over_static_methods
// ignore_for_file: prefer_interpolation_to_compose_strings, require_trailing_commas
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_shared/src/capability/capability_manifest.dart';
import 'package:restage_shared/src/capability/capability_sidecar.dart';
import 'package:restage_shared/src/flow_document/flow_document.dart';
import 'package:restage_shared/src/flow_document/flow_document_codec.dart';
import 'package:restage_shared/src/generated_output_path_order.dart';
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';
import 'package:restage_shared/src/surface_contract/surface_screen_contract_fingerprint.dart';
import 'package:restage_shared/src/surface_contract/surface_screen_event_schema.dart';
import 'package:restage_shared/src/surface_delivery/surface_artifact_descriptor.dart';
import 'package:restage_shared/src/surface_document/surface_document.dart';

const int _surfacePublicationSchemaVersion = 1;

enum SurfacePublicationArtifactRoleV1 {
  flowDocument('flowDocument'),
  screenBlob('screenBlob'),
  capabilitySidecar('capabilitySidecar');

  const SurfacePublicationArtifactRoleV1(this.wireName);

  final String wireName;

  static SurfacePublicationArtifactRoleV1 fromWireName(String value) {
    for (final role in values) {
      if (role.wireName == value) return role;
    }
    throw FormatException('Unsupported publication artifact role "$value".');
  }
}

@immutable
final class SurfacePublicationArtifactV1 {
  factory SurfacePublicationArtifactV1({
    required String contentHash,
    required String path,
    required SurfacePublicationArtifactRoleV1 role,
    String? id,
  }) {
    SurfaceContractJson.requireSha256(contentHash, 'artifact.contentHash');
    _requirePackageRelativePath(path, 'artifact.path');
    if (role == SurfacePublicationArtifactRoleV1.flowDocument) {
      if (id != null) {
        throw const FormatException(
            'A flow document artifact cannot carry id.');
      }
    } else {
      _requireIdentity(id, 'artifact.id');
    }
    return SurfacePublicationArtifactV1._(
      contentHash: contentHash,
      path: path,
      role: role,
      id: id,
    );
  }

  const SurfacePublicationArtifactV1._({
    required this.contentHash,
    required this.path,
    required this.role,
    required this.id,
  });

  final String contentHash;
  final String path;
  final SurfacePublicationArtifactRoleV1 role;
  final String? id;

  Map<String, Object?> toJson() => <String, Object?>{
        'contentHash': contentHash,
        if (id != null) 'id': id,
        'path': path,
        'role': role.wireName,
      };

  static SurfacePublicationArtifactV1 fromJson(
    Object? value, {
    required String path,
  }) {
    final json = SurfaceContractJson.requireObject(value, path);
    final role = SurfacePublicationArtifactRoleV1.fromWireName(
      SurfaceContractJson.requiredString(json, 'role', path),
    );
    final expected = <String>{'contentHash', 'path', 'role'};
    if (role != SurfacePublicationArtifactRoleV1.flowDocument) {
      expected.add('id');
    }
    SurfaceContractJson.exactKeys(json, expected, path);
    return SurfacePublicationArtifactV1(
      contentHash: SurfaceContractJson.requiredString(
        json,
        'contentHash',
        path,
      ),
      id: role == SurfacePublicationArtifactRoleV1.flowDocument
          ? null
          : SurfaceContractJson.requiredString(json, 'id', path),
      path: SurfaceContractJson.requiredString(json, 'path', path),
      role: role,
    );
  }
}

@immutable
final class SurfacePublicationV1 {
  factory SurfacePublicationV1({
    required Surface surface,
    required String slug,
    required SurfaceSourceKind sourceKind,
    required SurfacePayloadKind payloadKind,
    required String payloadContentHash,
    FlowDeliveryMode? deliveryMode,
    int? contractVersion,
    CapabilityManifest? capabilities,
    SurfaceScreenEventSchemaV1? eventContract,
    String? eventContractHash,
    String? contractFingerprint,
  }) {
    _requireIdentity(slug, 'publication.slug');
    SurfaceContractJson.requireSha256(
      payloadContentHash,
      'publication.payloadContentHash',
    );

    switch (sourceKind) {
      case SurfaceSourceKind.screen:
        if (payloadKind != SurfacePayloadKind.blob) {
          throw const FormatException(
            'A screen publication must carry a blob payload.',
          );
        }
        if (deliveryMode != null) {
          throw const FormatException(
            'A blob publication cannot carry deliveryMode.',
          );
        }
        if (contractVersion == null || contractVersion < 1) {
          throw const FormatException(
            'A screen publication requires a positive contractVersion.',
          );
        }
        if (capabilities == null ||
            eventContract == null ||
            eventContractHash == null ||
            contractFingerprint == null) {
          throw const FormatException(
            'A screen publication requires its complete contract metadata.',
          );
        }
        SurfaceContractJson.requireSha256(
          eventContractHash,
          'publication.eventContractHash',
        );
        SurfaceContractJson.requireSha256(
          contractFingerprint,
          'publication.contractFingerprint',
        );
        final canonicalCapabilities = _canonicalManifest(capabilities);
        final expectedEventHash = SurfaceScreenEventContractHashV1.hash(
          eventContract,
        );
        if (eventContractHash != expectedEventHash) {
          throw const FormatException(
            'Screen eventContractHash does not match eventContract.',
          );
        }
        final expectedFingerprint = SurfaceScreenContractFingerprintV1.hash(
          sourceKind: sourceKind,
          payloadKind: payloadKind,
          capabilities: canonicalCapabilities,
          eventContractHash: eventContractHash,
        );
        if (contractFingerprint != expectedFingerprint) {
          throw const FormatException(
            'Screen contractFingerprint does not match the contract tuple.',
          );
        }
      case SurfaceSourceKind.flowGraph:
        if (payloadKind != SurfacePayloadKind.flow || deliveryMode == null) {
          throw const FormatException(
            'A flowGraph publication requires a flow payload and deliveryMode.',
          );
        }
        _requireNoScreenContract(
          contractVersion: contractVersion,
          capabilities: capabilities,
          eventContract: eventContract,
          eventContractHash: eventContractHash,
          contractFingerprint: contractFingerprint,
        );
      case SurfaceSourceKind.paywall:
        if (surface != Surface.paywall) {
          throw const FormatException(
            'A paywall publication must use the paywall surface.',
          );
        }
        if ((payloadKind == SurfacePayloadKind.flow) !=
            (deliveryMode != null)) {
          throw const FormatException(
            'deliveryMode is required exactly for a flow payload.',
          );
        }
        _requireNoScreenContract(
          contractVersion: contractVersion,
          capabilities: capabilities,
          eventContract: eventContract,
          eventContractHash: eventContractHash,
          contractFingerprint: contractFingerprint,
        );
    }

    return SurfacePublicationV1._(
      surface: surface,
      slug: slug,
      sourceKind: sourceKind,
      payloadKind: payloadKind,
      payloadContentHash: payloadContentHash,
      deliveryMode: deliveryMode,
      contractVersion: contractVersion,
      capabilities:
          capabilities == null ? null : _canonicalManifest(capabilities),
      eventContract: eventContract,
      eventContractHash: eventContractHash,
      contractFingerprint: contractFingerprint,
    );
  }

  const SurfacePublicationV1._({
    required this.surface,
    required this.slug,
    required this.sourceKind,
    required this.payloadKind,
    required this.payloadContentHash,
    required this.deliveryMode,
    required this.contractVersion,
    required this.capabilities,
    required this.eventContract,
    required this.eventContractHash,
    required this.contractFingerprint,
  });

  final Surface surface;
  final String slug;
  final SurfaceSourceKind sourceKind;
  final SurfacePayloadKind payloadKind;
  final String payloadContentHash;
  final FlowDeliveryMode? deliveryMode;
  final int? contractVersion;
  final CapabilityManifest? capabilities;
  final SurfaceScreenEventSchemaV1? eventContract;
  final String? eventContractHash;
  final String? contractFingerprint;

  Map<String, Object?> toJson() {
    if (sourceKind == SurfaceSourceKind.screen) {
      return <String, Object?>{
        'capabilities': SurfaceContractJson.encodeCapabilityManifest(
          capabilities!,
          path: 'publication.capabilities',
        ),
        'contractFingerprint': contractFingerprint,
        'eventContract': SurfaceScreenEventSchemaV1Codec.encode(
          eventContract!,
        ),
        'eventContractHash': eventContractHash,
        'payloadContentHash': payloadContentHash,
        'payloadKind': payloadKind.wireName,
        'slug': slug,
        'sourceKind': sourceKind.wireName,
        'surface': surface.wireName,
        'contractVersion': contractVersion,
      };
    }
    return <String, Object?>{
      if (deliveryMode != null) 'deliveryMode': deliveryMode!.wireName,
      'payloadContentHash': payloadContentHash,
      'payloadKind': payloadKind.wireName,
      'slug': slug,
      'sourceKind': sourceKind.wireName,
      'surface': surface.wireName,
    };
  }

  static SurfacePublicationV1 fromJson(
    Object? value, {
    required String path,
  }) {
    final json = SurfaceContractJson.requireObject(value, path);
    SurfaceContractJson.allowedKeys(json, _publicationFields, path);
    final sourceKind = SurfaceSourceKind.fromWireName(
      SurfaceContractJson.requiredString(json, 'sourceKind', path),
    );
    final payloadKind = SurfacePayloadKind.fromWireName(
      SurfaceContractJson.requiredString(json, 'payloadKind', path),
    );
    final expected = _publicationRequiredFields(
      sourceKind: sourceKind,
      payloadKind: payloadKind,
    );
    SurfaceContractJson.exactKeys(json, expected, path);
    return SurfacePublicationV1(
      surface: Surface.fromWireName(
        SurfaceContractJson.requiredString(json, 'surface', path),
      ),
      slug: SurfaceContractJson.requiredString(json, 'slug', path),
      sourceKind: sourceKind,
      payloadKind: payloadKind,
      payloadContentHash: SurfaceContractJson.requiredString(
        json,
        'payloadContentHash',
        path,
      ),
      deliveryMode: json.containsKey('deliveryMode')
          ? FlowDeliveryMode.fromWireName(
              SurfaceContractJson.requiredString(json, 'deliveryMode', path),
            )
          : null,
      contractVersion: json.containsKey('contractVersion')
          ? SurfaceContractJson.requiredPositiveInt(
              json,
              'contractVersion',
              path,
            )
          : null,
      capabilities: json.containsKey('capabilities')
          ? SurfaceContractJson.decodeCapabilityManifest(
              SurfaceContractJson.requiredValue(json, 'capabilities', path),
              path: '$path.capabilities',
            )
          : null,
      eventContract: json.containsKey('eventContract')
          ? SurfaceScreenEventSchemaV1Codec.decode(
              SurfaceContractJson.requiredValue(json, 'eventContract', path),
            )
          : null,
      eventContractHash: json.containsKey('eventContractHash')
          ? SurfaceContractJson.requiredString(json, 'eventContractHash', path)
          : null,
      contractFingerprint: json.containsKey('contractFingerprint')
          ? SurfaceContractJson.requiredString(
              json,
              'contractFingerprint',
              path,
            )
          : null,
    );
  }

  void validatePayload(SurfacePayload payload) {
    if (payload.contentHash != payloadContentHash) {
      throw const FormatException(
        'Publication payloadContentHash does not match assembled payload.',
      );
    }
    switch (payloadKind) {
      case SurfacePayloadKind.blob:
        if (payload is! BlobSurfacePayload) {
          throw const FormatException('Publication requires a blob payload.');
        }
        if (sourceKind == SurfaceSourceKind.screen) {
          final expectedCapabilities = capabilities!;
          final actualCapabilities = CapabilityManifest(
            builtInFloor: payload.minClient,
            requiredLibraries: payload.requiredLibraries,
          );
          if (!SurfaceContractJson.requirementsEqual(
            expectedCapabilities,
            actualCapabilities,
          )) {
            throw const FormatException(
              'Screen publication capabilities do not match blob payload.',
            );
          }
        }
      case SurfacePayloadKind.flow:
        if (payload is! FlowSurfacePayload) {
          throw const FormatException('Publication requires a flow payload.');
        }
        if (payload.flowDocument.flow != slug) {
          throw const FormatException(
            'Flow payload identity does not match publication slug.',
          );
        }
        if (payload.flowDocument.deliveryMode != deliveryMode) {
          throw const FormatException(
            'Flow payload deliveryMode does not match publication.',
          );
        }
    }
  }
}

@immutable
final class SurfacePublicationManifestEntryV1 {
  factory SurfacePublicationManifestEntryV1({
    required List<SurfacePublicationArtifactV1> artifacts,
    required SurfacePublicationV1 publication,
    List<String> sources = const <String>[],
    String path = 'entry',
  }) {
    if (artifacts.isEmpty) {
      throw const FormatException('A publication entry requires artifacts.');
    }
    final paths = <String>{};
    for (final artifact in artifacts) {
      if (!paths.add(artifact.path)) {
        throw FormatException(
            'Duplicate publication artifact path "${artifact.path}".');
      }
    }
    _validateAuthoringSources(sources, path);
    _validateArtifactShape(artifacts, publication);
    return SurfacePublicationManifestEntryV1._(
      artifacts: List.unmodifiable(artifacts),
      publication: publication,
      sources: List.unmodifiable(sources),
    );
  }

  const SurfacePublicationManifestEntryV1._({
    required this.artifacts,
    required this.publication,
    required this.sources,
  });

  final List<SurfacePublicationArtifactV1> artifacts;
  final SurfacePublicationV1 publication;

  /// Package-relative authoring sources this publication was compiled from,
  /// in strictly ascending order.
  ///
  /// This is local build provenance, not wire state: it never reaches the
  /// upload request. It exists so a developer can name a publication by the
  /// file they are looking at and have the manifest, not a source scan,
  /// resolve which publication that is.
  ///
  /// The set is wider than "files that declare this publication". A flow
  /// lists the file declaring it plus the declaring file of every screen in
  /// its closure, so pointing at any screen of a flow resolves the flow that
  /// publishes it, and each declaration contributes both its own file and its
  /// owning library, which differ when a surface is declared in a part.
  ///
  /// Empty when nothing was recorded — in practice, a manifest generated
  /// before this field existed.
  final List<String> sources;

  /// This entry with its artifacts in canonical order.
  ///
  /// Canonicalization lives on the type, beside the validation that asserts
  /// it. A caller that rebuilt the entry field by field to sort one list
  /// would silently drop every field it forgot to transcribe, and an omitted
  /// optional field produces no decode error and no wire-format error — so
  /// nothing downstream would catch it.
  SurfacePublicationManifestEntryV1 canonical() =>
      SurfacePublicationManifestEntryV1(
        publication: publication,
        sources: sources,
        artifacts: [...artifacts]..sort(_compareArtifactsCanonically),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'artifacts': <Object?>[
          for (final artifact in artifacts) artifact.toJson(),
        ],
        'publication': publication.toJson(),
        if (sources.isNotEmpty) 'sources': <Object?>[...sources],
      };

  static SurfacePublicationManifestEntryV1 fromJson(
    Object? value, {
    required String path,
  }) {
    final json = SurfaceContractJson.requireObject(value, path);
    SurfaceContractJson.allowedKeys(
        json, const {'artifacts', 'publication', 'sources'}, path);
    final rawArtifacts = SurfaceContractJson.requireList(
      SurfaceContractJson.requiredValue(json, 'artifacts', path),
      '$path.artifacts',
    );
    final rawSources = json.containsKey('sources')
        ? SurfaceContractJson.requireList(json['sources'], '$path.sources')
        : const <Object?>[];
    return SurfacePublicationManifestEntryV1(
      artifacts: <SurfacePublicationArtifactV1>[
        for (var index = 0; index < rawArtifacts.length; index += 1)
          SurfacePublicationArtifactV1.fromJson(
            rawArtifacts[index],
            path: '$path.artifacts[$index]',
          ),
      ],
      publication: SurfacePublicationV1.fromJson(
        SurfaceContractJson.requiredValue(json, 'publication', path),
        path: '$path.publication',
      ),
      sources: <String>[
        for (var index = 0; index < rawSources.length; index += 1)
          _requireSourceString(rawSources[index], '$path.sources[$index]'),
      ],
      path: path,
    );
  }
}

int _compareArtifactsCanonically(
  SurfacePublicationArtifactV1 left,
  SurfacePublicationArtifactV1 right,
) {
  final path = compareGeneratedOutputPaths(left.path, right.path);
  if (path != 0) return path;
  final role = left.role.wireName.compareTo(right.role.wireName);
  if (role != 0) return role;
  return (left.id ?? '').compareTo(right.id ?? '');
}

String _requireSourceString(Object? value, String path) {
  if (value is! String) {
    throw FormatException('Expected "$path" to be a string.');
  }
  return value;
}

/// Sources are validated here, never repaired, in line with every other
/// field on this type. Ordering and uniqueness are the producer's job — the
/// assembler sorts and de-duplicates on the way in — so a constructor that
/// silently reordered its input would hide a producer defect rather than
/// surface it, and would make the canonical bytes depend on which code path
/// built the entry.
void _validateAuthoringSources(List<String> sources, String path) {
  if (sources.isEmpty) return;
  String? previous;
  for (var index = 0; index < sources.length; index += 1) {
    final source = sources[index];
    _requirePackageRelativePath(source, '$path.sources[$index]');
    if (!source.endsWith('.dart')) {
      throw FormatException(
          'Expected "$path.sources[$index]" to be a Dart source path.');
    }
    if (previous != null &&
        compareGeneratedOutputPaths(previous, source) >= 0) {
      throw FormatException(
        'Expected "$path.sources" to be unique and in ascending order.',
      );
    }
    previous = source;
  }
}

@immutable
final class SurfacePublicationArtifactClosureV1 {
  SurfacePublicationArtifactClosureV1._({
    required this.publication,
    required Map<String, Uint8List> screenBlobs,
    required Map<String, CapabilityManifest> sidecarCapabilities,
    required this.flowDocument,
  })  : _screenBlobs = Map.unmodifiable(screenBlobs),
        _sidecarCapabilities = Map.unmodifiable(sidecarCapabilities);

  final SurfacePublicationV1 publication;
  final Map<String, Uint8List> _screenBlobs;
  final Map<String, CapabilityManifest> _sidecarCapabilities;
  final FlowDocument? flowDocument;

  List<String> get screenIds => List.unmodifiable(_screenBlobs.keys);

  void validateAssembledPayload(List<int> payloadBytes) {
    final payload = _decodeCanonicalPayload(payloadBytes);
    publication.validatePayload(payload);
    switch (payload) {
      case BlobSurfacePayload():
        final blob = _screenBlobs[publication.slug];
        final capabilities = _sidecarCapabilities[publication.slug];
        if (blob == null || capabilities == null) {
          throw const FormatException(
              'Missing standalone blob artifact closure.');
        }
        if (!SurfaceContractJson.bytesEqual(blob, payload.blob)) {
          throw const FormatException(
            'Assembled blob payload does not match declared artifact bytes.',
          );
        }
        final actualCapabilities = CapabilityManifest(
          builtInFloor: payload.minClient,
          requiredLibraries: payload.requiredLibraries,
        );
        if (!SurfaceContractJson.requirementsEqual(
          capabilities,
          actualCapabilities,
        )) {
          throw const FormatException(
            'Blob payload capabilities do not match its sidecar.',
          );
        }
      case FlowSurfacePayload():
        final expectedFlowDocument = flowDocument;
        if (expectedFlowDocument == null) {
          throw const FormatException(
              'Missing declared flow document artifact.');
        }
        if (!SurfaceContractJson.bytesEqual(
          FlowDocumentCodec.encodeCanonicalJson(expectedFlowDocument),
          FlowDocumentCodec.encodeCanonicalJson(payload.flowDocument),
        )) {
          throw const FormatException(
            'Assembled flow payload does not match declared flow document.',
          );
        }
        if (payload.screenBlobs.length != _screenBlobs.length) {
          throw const FormatException(
            'Assembled flow payload has a different screen closure.',
          );
        }
        for (final entry in _screenBlobs.entries) {
          final actual = payload.screenBlobs[entry.key];
          if (actual == null ||
              !SurfaceContractJson.bytesEqual(entry.value, actual)) {
            throw FormatException(
              'Assembled flow payload does not match screen artifact "${entry.key}".',
            );
          }
        }
        final sidecarUnion = _capabilityUnion(_sidecarCapabilities.values);
        final payloadCapabilities = CapabilityManifest(
          builtInFloor: payload.minClient,
          requiredLibraries: payload.requiredLibraries,
        );
        if (payload.minClient < sidecarUnion.builtInFloor ||
            !_sameRequirements(
              sidecarUnion.requiredLibraries,
              payloadCapabilities.requiredLibraries,
            )) {
          throw const FormatException(
            'Flow payload capabilities do not match its sidecar closure.',
          );
        }
    }
  }
}

@immutable
final class SurfacePublicationManifestV1 {
  factory SurfacePublicationManifestV1({
    required List<SurfacePublicationManifestEntryV1> publications,
  }) {
    final identities = <String>{};
    final artifactsByPath = <String, SurfacePublicationArtifactV1>{};
    for (final entry in publications) {
      final identity =
          '${entry.publication.surface.wireName}\u0000${entry.publication.slug}';
      if (!identities.add(identity)) {
        throw FormatException(
          'Duplicate publication identity "${entry.publication.surface.wireName}/${entry.publication.slug}".',
        );
      }
      for (final artifact in entry.artifacts) {
        final existing = artifactsByPath[artifact.path];
        if (existing == null) {
          artifactsByPath[artifact.path] = artifact;
        } else if (existing.contentHash != artifact.contentHash ||
            existing.role != artifact.role ||
            existing.id != artifact.id) {
          throw FormatException(
            'Artifact path "${artifact.path}" has conflicting declarations.',
          );
        }
      }
    }
    // Entry construction rejects duplicate paths within one closure. Paths may
    // repeat across entries only for the same source artifact declaration.
    return SurfacePublicationManifestV1._(List.unmodifiable(publications));
  }

  const SurfacePublicationManifestV1._(this.publications);

  static const int schemaVersion = _surfacePublicationSchemaVersion;

  final List<SurfacePublicationManifestEntryV1> publications;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'publications': <Object?>[
          for (final publication in publications) publication.toJson(),
        ],
      };

  /// This manifest with every entry and the entry list in canonical order.
  SurfacePublicationManifestV1 canonical() => SurfacePublicationManifestV1(
        publications: [
          for (final entry in publications) entry.canonical(),
        ]..sort((left, right) {
            final surface = left.publication.surface.wireName.compareTo(
              right.publication.surface.wireName,
            );
            if (surface != 0) return surface;
            return left.publication.slug.compareTo(right.publication.slug);
          }),
      );

  List<SurfacePublicationArtifactClosureV1> validateArtifactClosure(
    Map<String, List<int>> files,
  ) {
    final declaredPaths = <String>{
      for (final entry in publications)
        for (final artifact in entry.artifacts) artifact.path,
    };
    for (final path in files.keys) {
      if (!declaredPaths.contains(path)) {
        throw FormatException('Undeclared artifact path "$path".');
      }
    }
    final closures = <SurfacePublicationArtifactClosureV1>[];
    for (final entry in publications) {
      final bytesByPath = <String, Uint8List>{};
      for (final artifact in entry.artifacts) {
        final bytes = files[artifact.path];
        if (bytes == null) {
          throw FormatException(
              'Missing declared artifact "${artifact.path}".');
        }
        final frozen = Uint8List.fromList(bytes);
        final actualHash = CapabilitySidecar.hashBlob(frozen);
        if (actualHash != artifact.contentHash) {
          throw FormatException(
            'Artifact hash does not match "${artifact.path}".',
          );
        }
        bytesByPath[artifact.path] = frozen;
      }
      closures.add(_validateEntryBytes(entry, bytesByPath));
    }
    return List.unmodifiable(closures);
  }

  static SurfacePublicationManifestV1 fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$');
    SurfaceContractJson.exactKeys(
      json,
      const {'schemaVersion', 'publications'},
      r'$',
    );
    final schemaVersion = SurfaceContractJson.requiredInt(
      json,
      'schemaVersion',
      r'$',
    );
    if (schemaVersion != SurfacePublicationManifestV1.schemaVersion) {
      throw FormatException(
        'Unsupported surface publication manifest schemaVersion $schemaVersion.',
      );
    }
    final rawPublications = SurfaceContractJson.requireList(
      SurfaceContractJson.requiredValue(json, 'publications', r'$'),
      r'$.publications',
    );
    return SurfacePublicationManifestV1(
      publications: <SurfacePublicationManifestEntryV1>[
        for (var index = 0; index < rawPublications.length; index += 1)
          SurfacePublicationManifestEntryV1.fromJson(
            rawPublications[index],
            path: r'$.publications[' + index.toString() + ']',
          ),
      ],
    );
  }
}

abstract final class SurfacePublicationManifestV1Codec {
  static SurfacePublicationManifestV1 decode(Object? value) =>
      SurfacePublicationManifestV1.fromJson(value);

  static SurfacePublicationManifestV1 decodeJson(String source) => decode(
        SurfaceContractJson.decode(
          source,
          label: 'surface publication manifest',
        ),
      );

  static Map<String, Object?> encode(SurfacePublicationManifestV1 manifest) =>
      manifest.toJson();

  static String encodeCanonicalJson(SurfacePublicationManifestV1 manifest) =>
      SurfaceContractJson.encode(encode(manifest));
}

@immutable
final class SurfacePublicationUploadRequestV1 {
  factory SurfacePublicationUploadRequestV1({
    required SurfacePublicationV1 publication,
    required List<int> payload,
  }) {
    final canonicalPayload = _decodeCanonicalPayload(payload);
    publication.validatePayload(canonicalPayload);
    return SurfacePublicationUploadRequestV1._(
      publication: publication,
      payload: Uint8List.fromList(payload),
    );
  }

  const SurfacePublicationUploadRequestV1._({
    required this.publication,
    required Uint8List payload,
  }) : _payload = payload;

  static const int schemaVersion = _surfacePublicationSchemaVersion;

  final SurfacePublicationV1 publication;
  final Uint8List _payload;

  Uint8List get payload => Uint8List.fromList(_payload);

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'publication': publication.toJson(),
        'payload': SurfaceContractJson.encodeBase64Url(_payload),
      };

  static SurfacePublicationUploadRequestV1 fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$');
    SurfaceContractJson.exactKeys(
      json,
      const {'schemaVersion', 'publication', 'payload'},
      r'$',
    );
    _requireSchemaVersion(json, 'surface publication upload request');
    return SurfacePublicationUploadRequestV1(
      publication: SurfacePublicationV1.fromJson(
        SurfaceContractJson.requiredValue(json, 'publication', r'$'),
        path: r'$.publication',
      ),
      payload: SurfaceContractJson.decodeCanonicalBase64Url(
        SurfaceContractJson.requiredString(json, 'payload', r'$'),
        r'$.payload',
      ),
    );
  }
}

abstract final class SurfacePublicationUploadRequestV1Codec {
  static SurfacePublicationUploadRequestV1 decode(Object? value) =>
      SurfacePublicationUploadRequestV1.fromJson(value);

  static SurfacePublicationUploadRequestV1 decodeJson(String source) => decode(
        SurfaceContractJson.decode(
          source,
          label: 'surface publication upload request',
        ),
      );

  static Map<String, Object?> encode(
    SurfacePublicationUploadRequestV1 request,
  ) =>
      request.toJson();

  static String encodeCanonicalJson(
          SurfacePublicationUploadRequestV1 request) =>
      SurfaceContractJson.encode(encode(request));
}

@immutable
final class SurfaceScreenDeliveryRequestV1 {
  factory SurfaceScreenDeliveryRequestV1({
    required Surface surface,
    required String slug,
    required int contractVersion,
    String? assignmentKey,
    String? meteringKey,
  }) {
    _requireIdentity(slug, 'delivery request.slug');
    if (contractVersion < 1) {
      throw const FormatException(
          'delivery request.contractVersion must be positive.');
    }
    return SurfaceScreenDeliveryRequestV1._(
      surface: surface,
      slug: slug,
      contractVersion: contractVersion,
      assignmentKey: normalizeAssignmentKey(assignmentKey),
      meteringKey: normalizeMeteringKey(meteringKey),
    );
  }

  const SurfaceScreenDeliveryRequestV1._({
    required this.surface,
    required this.slug,
    required this.contractVersion,
    required this.assignmentKey,
    required this.meteringKey,
  });

  static const int schemaVersion = _surfacePublicationSchemaVersion;

  static String? normalizeAssignmentKey(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return value.trim() == value && !value.contains('\u0000') ? value : null;
  }

  static String? normalizeMeteringKey(Object? value) {
    if (value is! String || value.length != 36) return null;
    for (var index = 0; index < value.length; index += 1) {
      final unit = value.codeUnitAt(index);
      if (index == 8 || index == 13 || index == 18 || index == 23) {
        if (unit != 0x2D) return null;
        continue;
      }
      final hex = (unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x46) ||
          (unit >= 0x61 && unit <= 0x66);
      if (!hex) return null;
    }
    return value;
  }

  final Surface surface;
  final String slug;
  final int contractVersion;
  final String? assignmentKey;
  final String? meteringKey;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'surface': surface.wireName,
        'slug': slug,
        'contractVersion': contractVersion,
        if (assignmentKey != null) 'assignmentKey': assignmentKey,
        if (meteringKey != null) 'meteringKey': meteringKey,
      };

  static SurfaceScreenDeliveryRequestV1 fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$');
    SurfaceContractJson.allowedKeys(
      json,
      const {
        'schemaVersion',
        'surface',
        'slug',
        'contractVersion',
        'assignmentKey',
        'meteringKey',
      },
      r'$',
    );
    _requireSchemaVersion(json, 'surface screen delivery request');
    return SurfaceScreenDeliveryRequestV1(
      surface: Surface.fromWireName(
        SurfaceContractJson.requiredString(json, 'surface', r'$'),
      ),
      slug: SurfaceContractJson.requiredString(json, 'slug', r'$'),
      contractVersion: SurfaceContractJson.requiredPositiveInt(
        json,
        'contractVersion',
        r'$',
      ),
      assignmentKey: normalizeAssignmentKey(json['assignmentKey']),
      meteringKey: normalizeMeteringKey(json['meteringKey']),
    );
  }
}

abstract final class SurfaceScreenDeliveryRequestV1Codec {
  static SurfaceScreenDeliveryRequestV1 decode(Object? value) =>
      SurfaceScreenDeliveryRequestV1.fromJson(value);

  static SurfaceScreenDeliveryRequestV1 decodeJson(String source) => decode(
        SurfaceContractJson.decode(
          source,
          label: 'surface screen delivery request',
        ),
      );

  static Map<String, Object?> encode(SurfaceScreenDeliveryRequestV1 request) =>
      request.toJson();

  static String encodeCanonicalJson(SurfaceScreenDeliveryRequestV1 request) =>
      SurfaceContractJson.encode(encode(request));
}

@immutable
final class SurfaceExperimentAssignmentV1 {
  factory SurfaceExperimentAssignmentV1({
    required String experimentId,
    required String variantId,
    required int experimentEpoch,
  }) {
    _requireIdentity(experimentId, 'assignment.experimentId');
    _requireIdentity(variantId, 'assignment.variantId');
    if (experimentEpoch < 1) {
      throw const FormatException(
          'assignment.experimentEpoch must be positive.');
    }
    return SurfaceExperimentAssignmentV1._(
      experimentId: experimentId,
      variantId: variantId,
      experimentEpoch: experimentEpoch,
    );
  }

  const SurfaceExperimentAssignmentV1._({
    required this.experimentId,
    required this.variantId,
    required this.experimentEpoch,
  });

  final String experimentId;
  final String variantId;
  final int experimentEpoch;

  Map<String, Object?> toJson() => <String, Object?>{
        'experimentId': experimentId,
        'variantId': variantId,
        'experimentEpoch': experimentEpoch,
      };

  static SurfaceExperimentAssignmentV1 fromJson(
    Object? value, {
    required String path,
  }) {
    final json = SurfaceContractJson.requireObject(value, path);
    SurfaceContractJson.exactKeys(
      json,
      const {'experimentId', 'variantId', 'experimentEpoch'},
      path,
    );
    return SurfaceExperimentAssignmentV1(
      experimentId:
          SurfaceContractJson.requiredString(json, 'experimentId', path),
      variantId: SurfaceContractJson.requiredString(json, 'variantId', path),
      experimentEpoch: SurfaceContractJson.requiredPositiveInt(
        json,
        'experimentEpoch',
        path,
      ),
    );
  }
}

@immutable
final class SurfaceScreenDeliveryResponseV1 {
  factory SurfaceScreenDeliveryResponseV1({
    required SurfaceDocument document,
    required SurfaceSourceKind sourceKind,
    required SurfacePayloadKind payloadKind,
    required int contractVersion,
    required int publishedRevision,
    required String contractFingerprint,
    required String eventContractHash,
    SurfaceExperimentAssignmentV1? assignment,
  }) {
    if (sourceKind != SurfaceSourceKind.screen ||
        payloadKind != SurfacePayloadKind.blob ||
        document.payload is! BlobSurfacePayload) {
      throw const FormatException(
        'A generic screen delivery response requires a screen blob document.',
      );
    }
    _requireIdentity(
      document.surfaceSlug,
      'delivery response.document.surfaceSlug',
    );
    if (contractVersion < 1 || publishedRevision < 1 || document.version < 1) {
      throw const FormatException(
          'Delivery response versions must be positive.');
    }
    if (publishedRevision != document.version) {
      throw const FormatException(
        'publishedRevision must equal document.version.',
      );
    }
    SurfaceContractJson.requireSha256(
      contractFingerprint,
      'delivery response.contractFingerprint',
    );
    SurfaceContractJson.requireSha256(
      eventContractHash,
      'delivery response.eventContractHash',
    );
    if (document.minClient < 1) {
      throw const FormatException(
          'Delivery document minClient must be positive.');
    }
    final capabilities = CapabilityManifest(
      builtInFloor: document.minClient,
      requiredLibraries: document.requiredLibraries,
    );
    final expectedFingerprint = SurfaceScreenContractFingerprintV1.hash(
      sourceKind: sourceKind,
      payloadKind: payloadKind,
      capabilities: capabilities,
      eventContractHash: eventContractHash,
    );
    if (contractFingerprint != expectedFingerprint) {
      throw const FormatException(
        'Delivery response contractFingerprint does not match document metadata.',
      );
    }
    return SurfaceScreenDeliveryResponseV1._(
      document: document,
      sourceKind: sourceKind,
      payloadKind: payloadKind,
      contractVersion: contractVersion,
      publishedRevision: publishedRevision,
      contractFingerprint: contractFingerprint,
      eventContractHash: eventContractHash,
      assignment: assignment,
    );
  }

  const SurfaceScreenDeliveryResponseV1._({
    required this.document,
    required this.sourceKind,
    required this.payloadKind,
    required this.contractVersion,
    required this.publishedRevision,
    required this.contractFingerprint,
    required this.eventContractHash,
    required this.assignment,
  });

  static const int schemaVersion = _surfacePublicationSchemaVersion;

  final SurfaceDocument document;
  final SurfaceSourceKind sourceKind;
  final SurfacePayloadKind payloadKind;
  final int contractVersion;
  final int publishedRevision;
  final String contractFingerprint;
  final String eventContractHash;
  final SurfaceExperimentAssignmentV1? assignment;
}

/// What a standalone-screen delivery puts on the wire.
///
/// Everything [SurfaceScreenDeliveryResponseV1] carries EXCEPT the rendered
/// document, plus where to fetch the bytes that make one. The rendered document
/// is no longer sent inline; it is assembled by the reader from
/// [artifact] and the payload frame that artifact names, and only then handed
/// to [SurfaceScreenDeliveryResponseV1]'s constructor — which is unchanged, so
/// every correlation this contract has ever enforced (the fingerprint recompute
/// against the assembled document, `publishedRevision == document.version`, the
/// screen/blob shape requirement) is enforced on exactly the same terms and in
/// exactly the same place.
///
/// The payload SHAPE is not a field here: it rides [artifact] with everything
/// else the publication record claims about the bytes, so there is one place a
/// claim about the artifact can be made and one place it is checked.
@immutable
final class SurfaceScreenDeliveryDescriptorV1 {
  /// Creates a standalone-screen delivery descriptor.
  factory SurfaceScreenDeliveryDescriptorV1({
    required SurfaceArtifactDescriptorV1 artifact,
    required SurfaceSourceKind sourceKind,
    required int contractVersion,
    required int publishedRevision,
    required String contractFingerprint,
    required String eventContractHash,
    SurfaceExperimentAssignmentV1? assignment,
  }) {
    if (sourceKind != SurfaceSourceKind.screen) {
      throw const FormatException(
        'A generic screen delivery descriptor requires a screen source.',
      );
    }
    // The shape claim is optional on an artifact descriptor in general — the
    // shape-agnostic serve route legitimately makes none. This wire is not
    // general: it delivers exactly one shape, so an absent claim here is a
    // missing field rather than a deliberate silence.
    if (artifact.payloadKind != SurfacePayloadKind.blob.wireName) {
      throw const FormatException(
        'A generic screen delivery descriptor requires a blob artifact.',
      );
    }
    if (contractVersion < 1 || publishedRevision < 1) {
      throw const FormatException(
        'Delivery descriptor versions must be positive.',
      );
    }
    if (publishedRevision != artifact.version) {
      throw const FormatException(
        'publishedRevision must equal the artifact version.',
      );
    }
    SurfaceContractJson.requireSha256(
      contractFingerprint,
      'delivery descriptor.contractFingerprint',
    );
    SurfaceContractJson.requireSha256(
      eventContractHash,
      'delivery descriptor.eventContractHash',
    );
    return SurfaceScreenDeliveryDescriptorV1._(
      artifact: artifact,
      sourceKind: sourceKind,
      contractVersion: contractVersion,
      publishedRevision: publishedRevision,
      contractFingerprint: contractFingerprint,
      eventContractHash: eventContractHash,
      assignment: assignment,
    );
  }

  const SurfaceScreenDeliveryDescriptorV1._({
    required this.artifact,
    required this.sourceKind,
    required this.contractVersion,
    required this.publishedRevision,
    required this.contractFingerprint,
    required this.eventContractHash,
    required this.assignment,
  });

  /// The publication schema this descriptor speaks.
  static const int schemaVersion = _surfacePublicationSchemaVersion;

  /// Where the payload frame is, what it must hash to, and what the record
  /// claims about it.
  final SurfaceArtifactDescriptorV1 artifact;

  /// Always [SurfaceSourceKind.screen] on this wire.
  final SurfaceSourceKind sourceKind;

  /// The contract family version this delivery answers.
  final int contractVersion;

  /// The published revision being delivered.
  final int publishedRevision;

  /// Fingerprint of the family's declared contract.
  final String contractFingerprint;

  /// Content hash of the family's event contract.
  final String eventContractHash;

  /// The experiment arm this delivery was assigned, when there was one.
  final SurfaceExperimentAssignmentV1? assignment;

  /// The descriptor as wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'artifact': artifact.toJson(),
        'sourceKind': sourceKind.wireName,
        'contractVersion': contractVersion,
        'publishedRevision': publishedRevision,
        'contractFingerprint': contractFingerprint,
        'eventContractHash': eventContractHash,
        if (assignment != null) 'assignment': assignment!.toJson(),
      };

  /// Decodes a descriptor strictly.
  static SurfaceScreenDeliveryDescriptorV1 fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$');
    SurfaceContractJson.allowedKeys(
      json,
      const {
        'schemaVersion',
        'artifact',
        'sourceKind',
        'contractVersion',
        'publishedRevision',
        'contractFingerprint',
        'eventContractHash',
        'assignment',
      },
      r'$',
    );
    _requireSchemaVersion(json, 'surface screen delivery descriptor');
    return SurfaceScreenDeliveryDescriptorV1(
      artifact: SurfaceArtifactDescriptorV1Codec.decode(
        SurfaceContractJson.requiredValue(json, 'artifact', r'$'),
      ),
      sourceKind: SurfaceSourceKind.fromWireName(
        SurfaceContractJson.requiredString(json, 'sourceKind', r'$'),
      ),
      contractVersion: SurfaceContractJson.requiredPositiveInt(
        json,
        'contractVersion',
        r'$',
      ),
      publishedRevision: SurfaceContractJson.requiredPositiveInt(
        json,
        'publishedRevision',
        r'$',
      ),
      contractFingerprint: SurfaceContractJson.requiredString(
        json,
        'contractFingerprint',
        r'$',
      ),
      eventContractHash: SurfaceContractJson.requiredString(
        json,
        'eventContractHash',
        r'$',
      ),
      assignment: json.containsKey('assignment')
          ? SurfaceExperimentAssignmentV1.fromJson(
              SurfaceContractJson.requiredValue(json, 'assignment', r'$'),
              path: r'$.assignment',
            )
          : null,
    );
  }

  /// Completes this descriptor into a delivery response with [document].
  ///
  /// The one place the two halves are joined. It deliberately routes through
  /// [SurfaceScreenDeliveryResponseV1]'s own constructor rather than
  /// reconstructing the checks: the fingerprint recompute has to run against
  /// the document that was actually assembled from fetched bytes, or it proves
  /// nothing about them.
  SurfaceScreenDeliveryResponseV1 completeWith(SurfaceDocument document) =>
      SurfaceScreenDeliveryResponseV1(
        document: document,
        sourceKind: sourceKind,
        payloadKind: SurfacePayloadKind.fromWireName(artifact.payloadKind!),
        contractVersion: contractVersion,
        publishedRevision: publishedRevision,
        contractFingerprint: contractFingerprint,
        eventContractHash: eventContractHash,
        assignment: assignment,
      );
}

/// Strict codec for [SurfaceScreenDeliveryDescriptorV1].
abstract final class SurfaceScreenDeliveryDescriptorV1Codec {
  /// Decodes a descriptor from a decoded JSON value.
  static SurfaceScreenDeliveryDescriptorV1 decode(Object? value) =>
      SurfaceScreenDeliveryDescriptorV1.fromJson(value);

  /// Decodes a descriptor from a JSON document.
  static SurfaceScreenDeliveryDescriptorV1 decodeJson(String source) => decode(
        SurfaceContractJson.decode(
          source,
          label: 'surface screen delivery descriptor',
        ),
      );

  /// Encodes a descriptor to wire JSON.
  static Map<String, Object?> encode(
    SurfaceScreenDeliveryDescriptorV1 descriptor,
  ) =>
      descriptor.toJson();

  /// Encodes a descriptor to a canonical JSON document.
  static String encodeCanonicalJson(
    SurfaceScreenDeliveryDescriptorV1 descriptor,
  ) =>
      SurfaceContractJson.encode(encode(descriptor));
}

const Set<String> _publicationFields = <String>{
  'capabilities',
  'contractFingerprint',
  'contractVersion',
  'deliveryMode',
  'eventContract',
  'eventContractHash',
  'payloadContentHash',
  'payloadKind',
  'slug',
  'sourceKind',
  'surface',
};

Set<String> _publicationRequiredFields({
  required SurfaceSourceKind sourceKind,
  required SurfacePayloadKind payloadKind,
}) {
  final fields = <String>{
    'payloadContentHash',
    'payloadKind',
    'slug',
    'sourceKind',
    'surface',
  };
  if (sourceKind == SurfaceSourceKind.screen) {
    return <String>{
      ...fields,
      'capabilities',
      'contractFingerprint',
      'contractVersion',
      'eventContract',
      'eventContractHash',
    };
  }
  if (payloadKind == SurfacePayloadKind.flow) fields.add('deliveryMode');
  return fields;
}

void _requireNoScreenContract({
  required int? contractVersion,
  required CapabilityManifest? capabilities,
  required SurfaceScreenEventSchemaV1? eventContract,
  required String? eventContractHash,
  required String? contractFingerprint,
}) {
  if (contractVersion != null ||
      capabilities != null ||
      eventContract != null ||
      eventContractHash != null ||
      contractFingerprint != null) {
    throw const FormatException(
      'Only a screen publication may carry generic screen contract metadata.',
    );
  }
}

void _validateArtifactShape(
  List<SurfacePublicationArtifactV1> artifacts,
  SurfacePublicationV1 publication,
) {
  final flowDocuments = <SurfacePublicationArtifactV1>[];
  final blobs = <String, SurfacePublicationArtifactV1>{};
  final sidecars = <String, SurfacePublicationArtifactV1>{};
  for (final artifact in artifacts) {
    switch (artifact.role) {
      case SurfacePublicationArtifactRoleV1.flowDocument:
        flowDocuments.add(artifact);
      case SurfacePublicationArtifactRoleV1.screenBlob:
        final id = artifact.id!;
        if (blobs.containsKey(id)) {
          throw FormatException('Duplicate screen blob artifact id "$id".');
        }
        blobs[id] = artifact;
      case SurfacePublicationArtifactRoleV1.capabilitySidecar:
        final id = artifact.id!;
        if (sidecars.containsKey(id)) {
          throw FormatException('Duplicate capability sidecar id "$id".');
        }
        sidecars[id] = artifact;
    }
  }
  if (flowDocuments.length > 1 ||
      (publication.payloadKind == SurfacePayloadKind.flow &&
          flowDocuments.length != 1) ||
      (publication.payloadKind == SurfacePayloadKind.blob &&
          flowDocuments.isNotEmpty)) {
    throw const FormatException(
      'Artifact closure must carry exactly one flow document for a flow payload.',
    );
  }
  if (blobs.length != sidecars.length ||
      !blobs.keys.toSet().containsAll(sidecars.keys)) {
    throw const FormatException(
      'Every screen blob requires exactly one same-id capability sidecar.',
    );
  }
  if (publication.payloadKind == SurfacePayloadKind.blob &&
      (blobs.length != 1 || !blobs.containsKey(publication.slug))) {
    throw const FormatException(
      'A blob publication requires one slug-id screen blob and sidecar.',
    );
  }
}

SurfacePublicationArtifactClosureV1 _validateEntryBytes(
  SurfacePublicationManifestEntryV1 entry,
  Map<String, Uint8List> bytesByPath,
) {
  final artifactsByRole =
      <SurfacePublicationArtifactRoleV1, List<SurfacePublicationArtifactV1>>{};
  for (final artifact in entry.artifacts) {
    (artifactsByRole[artifact.role] ??= <SurfacePublicationArtifactV1>[])
        .add(artifact);
  }
  final blobs = <String, Uint8List>{};
  final sidecars = <String, CapabilityManifest>{};
  for (final artifact
      in artifactsByRole[SurfacePublicationArtifactRoleV1.screenBlob] ??
          const <SurfacePublicationArtifactV1>[]) {
    blobs[artifact.id!] = bytesByPath[artifact.path]!;
  }
  for (final artifact
      in artifactsByRole[SurfacePublicationArtifactRoleV1.capabilitySidecar] ??
          const <SurfacePublicationArtifactV1>[]) {
    final manifest = _decodeStrictSidecar(
      bytesByPath[artifact.path]!,
      path: artifact.path,
    );
    final blob = blobs[artifact.id!];
    if (blob == null ||
        manifest.blobSha256 != CapabilitySidecar.hashBlob(blob)) {
      throw FormatException(
        'Capability sidecar "${artifact.path}" does not match its blob.',
      );
    }
    sidecars[artifact.id!] = manifest.manifest;
  }
  FlowDocument? flowDocument;
  final flowArtifacts =
      artifactsByRole[SurfacePublicationArtifactRoleV1.flowDocument];
  if (flowArtifacts != null) {
    final artifact = flowArtifacts.single;
    try {
      flowDocument = FlowDocumentCodec.decodeJson(
        utf8.decode(bytesByPath[artifact.path]!),
      );
    } on Object catch (error) {
      throw FormatException(
          'Invalid flow document artifact "${artifact.path}": $error');
    }
    if (flowDocument.flow != entry.publication.slug ||
        flowDocument.deliveryMode != entry.publication.deliveryMode) {
      throw const FormatException(
        'Flow document does not match its publication identity or deliveryMode.',
      );
    }
    final expectedIds = flowDocument.screenArtifacts.keys.toSet();
    if (expectedIds.length != blobs.length ||
        !expectedIds.containsAll(blobs.keys)) {
      throw const FormatException(
        'Flow artifact closure does not match the flow screen artifacts.',
      );
    }
    for (final id in expectedIds) {
      // FlowDocument paths address assembled-payload entries, while manifest
      // paths address package-local source artifacts. The unique id and exact
      // content hash form the cross-namespace closure binding.
      final expectedHash = flowDocument.screenArtifacts[id]!.contentHash.value;
      if (CapabilitySidecar.hashBlob(blobs[id]!) != expectedHash) {
        throw FormatException(
            'Flow screen artifact "$id" has a hash mismatch.');
      }
    }
  }
  if (entry.publication.sourceKind == SurfaceSourceKind.screen) {
    final sidecar = sidecars[entry.publication.slug];
    if (sidecar == null ||
        !SurfaceContractJson.requirementsEqual(
          sidecar,
          entry.publication.capabilities!,
        )) {
      throw const FormatException(
        'Screen publication capabilities do not match its sidecar.',
      );
    }
  }
  return SurfacePublicationArtifactClosureV1._(
    publication: entry.publication,
    screenBlobs: <String, Uint8List>{
      for (final entry in blobs.entries)
        entry.key: Uint8List.fromList(entry.value),
    },
    sidecarCapabilities: sidecars,
    flowDocument: flowDocument,
  );
}

CapabilitySidecar _decodeStrictSidecar(Uint8List bytes,
    {required String path}) {
  final value = SurfaceContractJson.decode(
    utf8.decode(bytes),
    label: 'capability sidecar "$path"',
  );
  final json = SurfaceContractJson.requireObject(value, path);
  SurfaceContractJson.exactKeys(json, const {'blobSha256', 'manifest'}, path);
  final blobSha256 = SurfaceContractJson.requireSha256(
    SurfaceContractJson.requiredString(json, 'blobSha256', path),
    '$path.blobSha256',
  );
  return CapabilitySidecar(
    blobSha256: blobSha256,
    manifest: SurfaceContractJson.decodeCapabilityManifest(
      SurfaceContractJson.requiredValue(json, 'manifest', path),
      path: '$path.manifest',
    ),
  );
}

SurfacePayload _decodeCanonicalPayload(List<int> payloadBytes) {
  final payload = SurfacePayload.decode(payloadBytes);
  if (!SurfaceContractJson.bytesEqual(payload.canonicalBytes, payloadBytes)) {
    throw const FormatException(
        'Payload bytes are not a canonical payload frame.');
  }
  return payload;
}

CapabilityManifest _canonicalManifest(CapabilityManifest source) {
  final encoded = SurfaceContractJson.encodeCapabilityManifest(
    source,
    path: 'capabilities',
  );
  return SurfaceContractJson.decodeCapabilityManifest(
    encoded,
    path: 'capabilities',
  );
}

CapabilityManifest _capabilityUnion(Iterable<CapabilityManifest> manifests) {
  var builtInFloor = 1;
  final versions = <String, int>{};
  for (final manifest in manifests) {
    if (manifest.builtInFloor > builtInFloor) {
      builtInFloor = manifest.builtInFloor;
    }
    for (final requirement in manifest.requiredLibraries) {
      final existing = versions[requirement.namespace];
      if (existing == null || requirement.minVersion > existing) {
        versions[requirement.namespace] = requirement.minVersion;
      }
    }
  }
  final requirements = SurfaceContractJson.canonicalRequirements(
    <LibraryRequirement>[
      for (final entry in versions.entries)
        LibraryRequirement(namespace: entry.key, minVersion: entry.value),
    ],
    path: 'sidecar requirements',
  );
  return CapabilityManifest(
    builtInFloor: builtInFloor,
    requiredLibraries: requirements,
  );
}

bool _sameRequirements(
  List<LibraryRequirement> left,
  List<LibraryRequirement> right,
) {
  final leftCanonical = SurfaceContractJson.canonicalRequirements(
    left,
    path: 'left requirements',
  );
  final rightCanonical = SurfaceContractJson.canonicalRequirements(
    right,
    path: 'right requirements',
  );
  if (leftCanonical.length != rightCanonical.length) return false;
  for (var index = 0; index < leftCanonical.length; index += 1) {
    if (leftCanonical[index] != rightCanonical[index]) return false;
  }
  return true;
}

void _requirePackageRelativePath(String value, String path) {
  _requireIdentity(value, path);
  if (!isPackageRelativePath(value)) {
    throw FormatException(
        'Expected "$path" to be a package-relative path with canonical '
        'segments.');
  }
}

void _requireIdentity(String? value, String path) {
  if (value == null ||
      value.isEmpty ||
      value.trim() != value ||
      value.contains('\u0000')) {
    throw FormatException(
        'Expected "$path" to be nonempty, trimmed, and NUL-free.');
  }
  SurfaceContractJson.requireUnicodeScalars(value, path);
}

void _requireSchemaVersion(Map<String, Object?> json, String label) {
  final version = SurfaceContractJson.requiredInt(json, 'schemaVersion', r'$');
  if (version != _surfacePublicationSchemaVersion) {
    throw FormatException('Unsupported $label schemaVersion $version.');
  }
}
