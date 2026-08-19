// Pure publication-manifest assembly from compiled artifact facts.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

/// One exact generated file supplied to the publication assembler.
///
/// The assembler computes the manifest hash from [bytes].  Callers cannot
/// provide a claimed hash that could get out of sync with the bytes.
@immutable
final class SurfacePublicationArtifactInput {
  SurfacePublicationArtifactInput({
    required this.path,
    required this.role,
    required List<int> bytes,
    this.id,
  }) : _bytes = _copyBytes(bytes);

  final String path;
  final SurfacePublicationArtifactRoleV1 role;
  final String? id;
  final Uint8List _bytes;

  List<int> get bytes => Uint8List.fromList(_bytes);
}

/// Flow-specific facts needed in addition to the exact flow artifact.
@immutable
final class SurfacePublicationFlowFacts {
  const SurfacePublicationFlowFacts({required this.deliveryMode});

  final FlowDeliveryMode deliveryMode;
}

/// Standalone-screen contract facts needed in addition to the exact blob and
/// capability-sidecar artifacts.
///
/// Both hashes are deliberately derived by the assembler from
/// [eventContract] and [capabilities] through the shared production encoders.
@immutable
final class SurfacePublicationScreenContractFacts {
  const SurfacePublicationScreenContractFacts({
    required this.contractVersion,
    required this.capabilities,
    required this.eventContract,
  });

  final int contractVersion;
  final CapabilityManifest capabilities;
  final SurfaceScreenEventSchemaV1 eventContract;

  String get eventContractHash =>
      SurfaceScreenEventContractHashV1.hash(eventContract);

  String get contractFingerprint => SurfaceScreenContractFingerprintV1.hash(
        sourceKind: SurfaceSourceKind.screen,
        payloadKind: SurfacePayloadKind.blob,
        capabilities: capabilities,
        eventContractHash: eventContractHash,
      );
}

/// The normalized facts and exact artifacts for one publication.
@immutable
final class SurfacePublicationAssemblyInput {
  SurfacePublicationAssemblyInput({
    required this.surface,
    required this.slug,
    required this.sourceKind,
    required this.payloadKind,
    required Iterable<SurfacePublicationArtifactInput> artifacts,
    this.flowFacts,
    this.screenContractFacts,
  }) : artifacts = List.unmodifiable(artifacts);

  final Surface surface;
  final String slug;
  final SurfaceSourceKind sourceKind;
  final SurfacePayloadKind payloadKind;
  final List<SurfacePublicationArtifactInput> artifacts;
  final SurfacePublicationFlowFacts? flowFacts;
  final SurfacePublicationScreenContractFacts? screenContractFacts;
}

/// The strict, canonical result of publication assembly.
@immutable
final class SurfacePublicationAssemblyResult {
  SurfacePublicationAssemblyResult({
    required this.manifest,
    required List<int> canonicalBytes,
  }) : _canonicalBytes = Uint8List.fromList(canonicalBytes);

  final SurfacePublicationManifestV1 manifest;
  final Uint8List _canonicalBytes;

  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);

  String get canonicalJson => utf8.decode(_canonicalBytes);
}

/// Deterministically assembles the production publication manifest.
abstract final class SurfacePublicationManifestAssembler {
  /// Assembles only the canonical manifest bytes.
  static Uint8List assembleBytes(
    Iterable<SurfacePublicationAssemblyInput> inputs,
  ) =>
      assemble(inputs).canonicalBytes;

  /// Assembles and strictly round-trips one package publication manifest.
  static SurfacePublicationAssemblyResult assemble(
    Iterable<SurfacePublicationAssemblyInput> inputs,
  ) {
    final prepared = [
      for (final input in inputs) _prepare(input),
    ]..sort(_comparePreparedPublications);

    final identities = <String>{};
    for (final publication in prepared) {
      final identity = '${publication.publication.surface.wireName}\u0000'
          '${publication.publication.slug}';
      if (!identities.add(identity)) {
        throw FormatException(
          'Duplicate publication identity '
          '"${publication.publication.surface.wireName}/'
          '${publication.publication.slug}".',
        );
      }
    }

    final filesByPath = <String, Uint8List>{};
    final declarationsByPath = <String, SurfacePublicationArtifactV1>{};
    for (final publication in prepared) {
      for (final artifact in publication.artifacts) {
        final previousBytes = filesByPath[artifact.declaration.path];
        if (previousBytes != null &&
            !_bytesEqual(previousBytes, artifact.bytes)) {
          throw FormatException(
            'Artifact path "${artifact.declaration.path}" is reused with '
            'different exact bytes.',
          );
        }
        final previousDeclaration =
            declarationsByPath[artifact.declaration.path];
        if (previousDeclaration != null &&
            !_sameArtifactDeclaration(
              previousDeclaration,
              artifact.declaration,
            )) {
          throw FormatException(
            'Artifact path "${artifact.declaration.path}" is reused with '
            'different hash, role, or ID.',
          );
        }
        filesByPath[artifact.declaration.path] = artifact.bytes;
        declarationsByPath[artifact.declaration.path] = artifact.declaration;
      }
    }

    final manifest = SurfacePublicationManifestV1(
      publications: [
        for (final publication in prepared)
          SurfacePublicationManifestEntryV1(
            artifacts: [
              for (final artifact in publication.artifacts)
                artifact.declaration,
            ],
            publication: publication.publication,
          ),
      ],
    );

    // This is intentionally a production closure check.  It independently
    // re-hashes every input, decodes every sidecar, checks flow cardinality,
    // and rejects undeclared or stale files before the manifest is returned.
    final closures = manifest.validateArtifactClosure(filesByPath);
    if (closures.length != prepared.length) {
      throw StateError('Manifest closure count changed during assembly.');
    }
    for (var index = 0; index < closures.length; index += 1) {
      closures[index].validateAssembledPayload(
        prepared[index].payload.canonicalBytes,
      );
    }

    final encoded = SurfacePublicationManifestV1Codec.encodeCanonicalJson(
      manifest,
    );
    final decoded = SurfacePublicationManifestV1Codec.decodeJson(encoded);
    final roundTripped =
        SurfacePublicationManifestV1Codec.encodeCanonicalJson(decoded);
    if (roundTripped != encoded) {
      throw StateError(
        'Surface publication manifest codec did not preserve canonical bytes.',
      );
    }
    return SurfacePublicationAssemblyResult(
      manifest: decoded,
      canonicalBytes: utf8.encode(roundTripped),
    );
  }

  static _PreparedPublication _prepare(
    SurfacePublicationAssemblyInput input,
  ) {
    _validateFactShape(input);

    final artifacts = <_PreparedArtifact>[];
    final paths = <String>{};
    for (final artifact in input.artifacts) {
      final bytes = _copyBytes(artifact.bytes);
      final declaration = SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(bytes),
        path: artifact.path,
        role: artifact.role,
        id: artifact.id,
      );
      if (!paths.add(declaration.path)) {
        throw FormatException(
          'Publication "${input.slug}" declares duplicate artifact path '
          '"${declaration.path}".',
        );
      }
      artifacts.add(
        _PreparedArtifact(
          declaration: declaration,
          bytes: bytes,
        ),
      );
    }

    final flowDocuments = artifacts
        .where(
          (artifact) =>
              artifact.declaration.role ==
              SurfacePublicationArtifactRoleV1.flowDocument,
        )
        .toList(growable: false);
    final blobs = _artifactsById(
      artifacts,
      SurfacePublicationArtifactRoleV1.screenBlob,
    );
    final sidecars = _artifactsById(
      artifacts,
      SurfacePublicationArtifactRoleV1.capabilitySidecar,
    );

    if (flowDocuments.length > 1) {
      throw FormatException(
        'Publication "${input.slug}" declares more than one flow document.',
      );
    }
    if (blobs.length != sidecars.length ||
        !blobs.keys.toSet().containsAll(sidecars.keys)) {
      throw FormatException(
        'Publication "${input.slug}" requires one capability sidecar for '
        'each screen blob with the same ID.',
      );
    }

    final decodedSidecars = <String, _DecodedSidecar>{};
    for (final entry in sidecars.entries) {
      final blob = blobs[entry.key];
      if (blob == null) {
        throw FormatException(
          'Capability sidecar ID "${entry.key}" has no matching blob.',
        );
      }
      decodedSidecars[entry.key] = _decodeSidecar(
        entry.value.bytes,
        entry.value.declaration.path,
        blob.bytes,
      );
    }

    final SurfacePayload payload;
    if (input.payloadKind == SurfacePayloadKind.flow) {
      if (flowDocuments.length != 1) {
        throw FormatException(
          'Flow publication "${input.slug}" requires exactly one flow '
          'document artifact.',
        );
      }
      final document = _decodeFlowDocument(flowDocuments.single);
      final flowFacts = input.flowFacts!;
      if (document.flow != input.slug) {
        throw FormatException(
          'Flow document identity "${document.flow}" does not match '
          'publication slug "${input.slug}".',
        );
      }
      if (document.deliveryMode != flowFacts.deliveryMode) {
        throw const FormatException(
          'Flow document deliveryMode does not match publication facts.',
        );
      }
      final expectedIds = document.screenArtifacts.keys.toSet();
      if (expectedIds.length != blobs.length ||
          !expectedIds.containsAll(blobs.keys)) {
        throw const FormatException(
          'Flow publication screen artifact closure does not match its '
          'screen blob IDs.',
        );
      }
      for (final id in expectedIds) {
        final screenArtifact = document.screenArtifacts[id]!;
        final decoded = decodedSidecars[id];
        if (decoded == null) {
          throw FormatException(
            'Flow publication screen artifact "$id" has no sidecar.',
          );
        }
        if (screenArtifact.minClient < decoded.manifest.builtInFloor) {
          throw FormatException(
            'Capability sidecar for flow screen "$id" has built-in floor '
            '${decoded.manifest.builtInFloor}, above the screen artifact '
            'minClient ${screenArtifact.minClient}.',
          );
        }
        if (document.minClient < screenArtifact.minClient) {
          throw FormatException(
            'Flow document minClient ${document.minClient} is below screen '
            'artifact "$id" minClient ${screenArtifact.minClient}.',
          );
        }
      }
      final capabilities = _capabilityUnion(
        decodedSidecars.values.map((sidecar) => sidecar.manifest),
      );
      if (document.minClient < capabilities.builtInFloor) {
        throw const FormatException(
          'Flow document minClient is below its sidecar capability union.',
        );
      }
      try {
        payload = FlowSurfacePayload(
          flowDocument: document,
          screenBlobs: {
            for (final entry in blobs.entries)
              entry.key: _copyBytes(entry.value.bytes),
          },
          requiredLibraries: capabilities.requiredLibraries,
        );
      } on Object catch (error) {
        if (error is ArgumentError) {
          throw FormatException('Invalid flow artifact closure: $error');
        }
        rethrow;
      }
    } else {
      if (flowDocuments.isNotEmpty) {
        throw FormatException(
          'Blob publication "${input.slug}" cannot declare a flow '
          'document artifact.',
        );
      }
      if (blobs.length != 1 || !blobs.containsKey(input.slug)) {
        throw FormatException(
          'Blob publication "${input.slug}" requires exactly one blob '
          'and sidecar with ID equal to its slug.',
        );
      }
      final sidecar = decodedSidecars[input.slug]!;
      final contractFacts = input.screenContractFacts;
      if (contractFacts != null &&
          !_sameCapabilities(sidecar.manifest, contractFacts.capabilities)) {
        throw const FormatException(
          'Standalone screen capabilities do not match its sidecar.',
        );
      }
      final capabilities = contractFacts?.capabilities ?? sidecar.manifest;
      try {
        payload = BlobSurfacePayload(
          minClient: capabilities.builtInFloor,
          blob: _copyBytes(blobs[input.slug]!.bytes),
          requiredLibraries: capabilities.requiredLibraries,
        );
      } on Object catch (error) {
        if (error is ArgumentError) {
          throw FormatException('Invalid blob artifact closure: $error');
        }
        rethrow;
      }
    }

    final contractFacts = input.screenContractFacts;
    final publication = SurfacePublicationV1(
      surface: input.surface,
      slug: input.slug,
      sourceKind: input.sourceKind,
      payloadKind: input.payloadKind,
      payloadContentHash: payload.contentHash,
      deliveryMode: input.flowFacts?.deliveryMode,
      contractVersion: contractFacts?.contractVersion,
      capabilities: contractFacts?.capabilities,
      eventContract: contractFacts?.eventContract,
      eventContractHash: contractFacts?.eventContractHash,
      contractFingerprint: contractFacts?.contractFingerprint,
    );

    artifacts.sort(_compareArtifacts);
    return _PreparedPublication(
      publication: publication,
      artifacts: List.unmodifiable(artifacts),
      payload: payload,
    );
  }
}

final class _PreparedPublication {
  const _PreparedPublication({
    required this.publication,
    required this.artifacts,
    required this.payload,
  });

  final SurfacePublicationV1 publication;
  final List<_PreparedArtifact> artifacts;
  final SurfacePayload payload;
}

final class _PreparedArtifact {
  const _PreparedArtifact({required this.declaration, required this.bytes});

  final SurfacePublicationArtifactV1 declaration;
  final Uint8List bytes;
}

final class _DecodedSidecar {
  const _DecodedSidecar({required this.manifest});

  final CapabilityManifest manifest;
}

void _validateFactShape(SurfacePublicationAssemblyInput input) {
  final hasFlowFacts = input.flowFacts != null;
  final hasScreenFacts = input.screenContractFacts != null;
  switch (input.sourceKind) {
    case SurfaceSourceKind.screen:
      if (input.payloadKind != SurfacePayloadKind.blob ||
          !hasScreenFacts ||
          hasFlowFacts) {
        throw const FormatException(
          'A screen publication requires standalone-screen contract facts '
          'and a blob payload.',
        );
      }
    case SurfaceSourceKind.flowGraph:
      if (input.payloadKind != SurfacePayloadKind.flow ||
          !hasFlowFacts ||
          hasScreenFacts) {
        throw const FormatException(
          'A flowGraph publication requires flow delivery facts and a flow '
          'payload.',
        );
      }
    case SurfaceSourceKind.paywall:
      if (input.payloadKind == SurfacePayloadKind.flow) {
        if (!hasFlowFacts || hasScreenFacts) {
          throw const FormatException(
            'A paywall navigation publication requires flow delivery facts.',
          );
        }
      } else if (hasFlowFacts || hasScreenFacts) {
        throw const FormatException(
          'A standalone paywall publication cannot carry flow or screen '
          'contract facts.',
        );
      }
  }
}

Map<String, _PreparedArtifact> _artifactsById(
  List<_PreparedArtifact> artifacts,
  SurfacePublicationArtifactRoleV1 role,
) {
  final result = <String, _PreparedArtifact>{};
  for (final artifact in artifacts.where(
    (candidate) => candidate.declaration.role == role,
  )) {
    final id = artifact.declaration.id;
    if (id == null) {
      throw FormatException('Artifact role ${role.wireName} requires an ID.');
    }
    if (result.containsKey(id)) {
      throw FormatException(
        'Duplicate ${role.wireName} artifact ID "$id".',
      );
    }
    result[id] = artifact;
  }
  return result;
}

_DecodedSidecar _decodeSidecar(
  Uint8List bytes,
  String path,
  Uint8List blob,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object catch (error) {
    throw FormatException(
      'Could not decode capability sidecar "$path": $error',
    );
  }
  if (decoded is! Map) {
    throw FormatException('Capability sidecar "$path" must be an object.');
  }
  final json = <String, Object?>{};
  for (final entry in decoded.entries) {
    if (entry.key is! String) {
      throw FormatException('Capability sidecar "$path" has a non-string key.');
    }
    json[entry.key as String] = entry.value;
  }
  _exactKeys(json, const {'blobSha256', 'manifest'}, path);
  final blobSha256 = json['blobSha256'];
  if (blobSha256 is! String || !_sha256Pattern.hasMatch(blobSha256)) {
    throw FormatException(
      'Capability sidecar "$path" has an invalid blob hash.',
    );
  }
  final expectedBlobHash = CapabilitySidecar.hashBlob(blob);
  if (blobSha256 != expectedBlobHash) {
    throw FormatException(
      'Capability sidecar "$path" does not match its exact blob bytes.',
    );
  }
  final manifestValue = json['manifest'];
  if (manifestValue is! Map) {
    throw FormatException(
      'Capability sidecar "$path" manifest must be an object.',
    );
  }
  final manifestJson = <String, Object?>{};
  for (final entry in manifestValue.entries) {
    if (entry.key is! String) {
      throw FormatException(
        'Capability sidecar "$path" has a non-string manifest key.',
      );
    }
    manifestJson[entry.key as String] = entry.value;
  }
  _exactKeys(
    manifestJson,
    const {'builtInFloor', 'requiredLibraries'},
    '$path.manifest',
  );
  final builtInFloor = manifestJson['builtInFloor'];
  if (builtInFloor is! int || builtInFloor < 1) {
    throw FormatException(
      'Capability sidecar "$path" has an invalid built-in floor.',
    );
  }
  final rawLibraries = manifestJson['requiredLibraries'];
  if (rawLibraries is! List) {
    throw FormatException(
      'Capability sidecar "$path" libraries must be an array.',
    );
  }
  final libraries = <LibraryRequirement>[];
  final seenNamespaces = <String>{};
  for (var index = 0; index < rawLibraries.length; index += 1) {
    final value = rawLibraries[index];
    if (value is! Map) {
      throw FormatException(
        'Capability sidecar "$path" has an invalid library.',
      );
    }
    final libraryJson = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException(
          'Capability sidecar "$path" has a non-string library key.',
        );
      }
      libraryJson[entry.key as String] = entry.value;
    }
    final libraryPath = '$path.manifest.requiredLibraries[$index]';
    _exactKeys(libraryJson, const {'namespace', 'minVersion'}, libraryPath);
    final namespace = libraryJson['namespace'];
    final minVersion = libraryJson['minVersion'];
    if (namespace is! String ||
        namespace.isEmpty ||
        minVersion is! int ||
        minVersion < 1 ||
        !_isUnicodeScalarString(namespace)) {
      throw FormatException('Capability sidecar "$libraryPath" is invalid.');
    }
    if (!seenNamespaces.add(namespace)) {
      throw FormatException('Capability sidecar "$path" repeats "$namespace".');
    }
    libraries
        .add(LibraryRequirement(namespace: namespace, minVersion: minVersion));
  }
  return _DecodedSidecar(
    manifest: CapabilityManifest(
      builtInFloor: builtInFloor,
      requiredLibraries: libraries,
    ),
  );
}

FlowDocument _decodeFlowDocument(_PreparedArtifact artifact) {
  try {
    return FlowDocumentCodec.decodeJson(utf8.decode(artifact.bytes));
  } on Object catch (error) {
    throw FormatException(
      'Could not decode flow document "${artifact.declaration.path}": $error',
    );
  }
}

CapabilityManifest _capabilityUnion(Iterable<CapabilityManifest> manifests) {
  var builtInFloor = 1;
  final versions = <String, int>{};
  for (final manifest in manifests) {
    if (manifest.builtInFloor > builtInFloor) {
      builtInFloor = manifest.builtInFloor;
    }
    for (final requirement in manifest.requiredLibraries) {
      final previous = versions[requirement.namespace];
      if (previous == null || requirement.minVersion > previous) {
        versions[requirement.namespace] = requirement.minVersion;
      }
    }
  }
  return CapabilityManifest(
    builtInFloor: builtInFloor,
    requiredLibraries: [
      for (final entry in versions.entries)
        LibraryRequirement(namespace: entry.key, minVersion: entry.value),
    ],
  );
}

bool _sameCapabilities(CapabilityManifest left, CapabilityManifest right) {
  if (left.builtInFloor != right.builtInFloor ||
      left.requiredLibraries.length != right.requiredLibraries.length) {
    return false;
  }
  final rightByNamespace = <String, int>{
    for (final requirement in right.requiredLibraries)
      requirement.namespace: requirement.minVersion,
  };
  for (final requirement in left.requiredLibraries) {
    if (rightByNamespace[requirement.namespace] != requirement.minVersion) {
      return false;
    }
  }
  return true;
}

int _comparePreparedPublications(
  _PreparedPublication left,
  _PreparedPublication right,
) {
  final surface = left.publication.surface.wireName.compareTo(
    right.publication.surface.wireName,
  );
  if (surface != 0) return surface;
  return left.publication.slug.compareTo(right.publication.slug);
}

int _compareArtifacts(_PreparedArtifact left, _PreparedArtifact right) {
  final role = _roleOrder(left.declaration.role).compareTo(
    _roleOrder(right.declaration.role),
  );
  if (role != 0) return role;
  final id = (left.declaration.id ?? '').compareTo(right.declaration.id ?? '');
  if (id != 0) return id;
  return left.declaration.path.compareTo(right.declaration.path);
}

int _roleOrder(SurfacePublicationArtifactRoleV1 role) => switch (role) {
      SurfacePublicationArtifactRoleV1.flowDocument => 0,
      SurfacePublicationArtifactRoleV1.screenBlob => 1,
      SurfacePublicationArtifactRoleV1.capabilitySidecar => 2,
    };

bool _sameArtifactDeclaration(
  SurfacePublicationArtifactV1 left,
  SurfacePublicationArtifactV1 right,
) =>
    left.contentHash == right.contentHash &&
    left.path == right.path &&
    left.role == right.role &&
    left.id == right.id;

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Uint8List _copyBytes(List<int> bytes) {
  for (final byte in bytes) {
    if (byte < 0 || byte > 255) {
      throw const FormatException('Artifact bytes must be unsigned octets.');
    }
  }
  return Uint8List.fromList(bytes);
}

void _exactKeys(
  Map<String, Object?> json,
  Set<String> expected,
  String path,
) {
  for (final key in json.keys) {
    if (!expected.contains(key)) {
      throw FormatException('Unsupported field "$path.$key".');
    }
  }
  for (final key in expected) {
    if (!json.containsKey(key) || json[key] == null) {
      throw FormatException('Missing or null field "$path.$key".');
    }
  }
}

bool _isUnicodeScalarString(String value) {
  for (var index = 0; index < value.length; index += 1) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 1 >= value.length) return false;
      final next = value.codeUnitAt(index + 1);
      if (next < 0xDC00 || next > 0xDFFF) return false;
      index += 1;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false;
    }
  }
  return true;
}

final _sha256Pattern = RegExp(r'^sha256:[0-9a-f]{64}$');
