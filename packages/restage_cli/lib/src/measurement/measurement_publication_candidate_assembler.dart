import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;

import '../api/surface_publication_api.dart';
import '../publication/publication_errors.dart';
import '../publication/publication_manifest.dart';

/// The generated package-wide index containing target-neutral Measurement
/// publication drafts.
const String restageMeasurementPublicationIndexFileName =
    'restage.measurement.index.json';

const String _artifactDefinitionDomain =
    'restage-measurement-artifact-definition-v1';
const String _publicationLineDomain = 'restage-surface-publication-line-v1';
const String _declaredArtifactBytesDomain =
    'restage-surface-publication-declared-artifact-bytes-v1';

/// Strictly joins optional generated Measurement output to one publication.
final class MeasurementPublicationCandidateAssembler {
  /// Assemble an additive upload when the selected draft has admitted routes.
  ///
  /// A missing index or a matching zero-route draft preserves ordinary publication
  /// publication only when the selected artifacts contain no Measurement
  /// carrier. Every partial or disagreeing Measurement input fails before the
  /// network boundary.
  Future<MeasurementBoundSurfacePublicationUploadWire?> assemble({
    required LoadedSurfacePublicationManifest loaded,
    required SurfacePublicationManifestEntry entry,
    required SurfacePublicationUploadRequest request,
    required Map<String, Uint8List> artifactBytes,
  }) async {
    try {
      final carriersByArtifact = _readCarriers(entry, artifactBytes);
      final indexFile = File(
        p.join(
          loaded.outputsFile.parent.path,
          restageMeasurementPublicationIndexFileName,
        ),
      );
      if (!indexFile.existsSync()) {
        if (carriersByArtifact.isNotEmpty) {
          throw const FormatException(
            'generated artifacts contain Measurement routes but the '
            'Measurement publication index is missing',
          );
        }
        return null;
      }

      final entries = await _readIndex(indexFile, loaded);
      final selected = [
        for (final indexed in entries)
          if (identical(indexed.publication, entry)) indexed,
      ];
      if (selected.length > 1) {
        throw const FormatException(
          'the Measurement publication index contains duplicate selected '
          'drafts',
        );
      }
      if (selected.isEmpty) {
        if (carriersByArtifact.isNotEmpty) {
          throw const FormatException(
            'generated artifacts contain Measurement routes without an exact '
            'matching draft',
          );
        }
        return null;
      }

      final indexed = selected.single;
      _validateDraftArtifactClosure(
        entry: entry,
        draft: indexed.draft,
        artifactBytes: artifactBytes,
      );
      if (indexed.draft.routes.isEmpty) {
        if (carriersByArtifact.isNotEmpty) {
          throw const FormatException(
            'a zero-route Measurement draft disagrees with generated '
            'artifact carriers',
          );
        }
        return null;
      }
      _validateRouteClosure(
        entry: entry,
        draft: indexed.draft,
        carriersByArtifact: carriersByArtifact,
      );

      final selectedManifestBytes = Uint8List.fromList(
        utf8.encode(
          SurfacePublicationManifestV1Codec.encodeCanonicalJson(
            SurfacePublicationManifest(publications: [entry]),
          ),
        ),
      );
      final uploadBytes = Uint8List.fromList(
        utf8.encode(
          SurfacePublicationUploadRequestV1Codec.encodeCanonicalJson(request),
        ),
      );
      final tupleRecords = <({Uint8List bytes, Map<String, Object?> value})>[];
      final uploadArtifacts =
          <MeasurementBoundSurfacePublicationArtifactWire>[];
      for (final artifact in entry.artifacts) {
        final bytes = artifactBytes[artifact.path];
        if (bytes == null) {
          throw FormatException(
            'the selected publication closure is missing ${artifact.path}',
          );
        }
        final value = <String, Object?>{
          'byteLength': bytes.length,
          if (artifact.id != null) 'id': artifact.id,
          'kind': 'restageSurfacePublicationDeclaredArtifactTuple',
          'path': artifact.path,
          'role': artifact.role.wireName,
          'schemaVersion': 1,
          'sha256': crypto.sha256.convert(bytes).toString(),
        };
        tupleRecords.add((
          bytes: CanonicalJsonCodec.encode(value),
          value: value,
        ));
        uploadArtifacts.add(
          MeasurementBoundSurfacePublicationArtifactWire(
            path: artifact.path,
            bytes: bytes,
          ),
        );
      }
      tupleRecords.sort(
        (left, right) => _compareBytes(left.bytes, right.bytes),
      );
      final declaredArtifactBytesDigest = CanonicalDigest(
        _privateDigest(_declaredArtifactBytesDomain, <String, Object?>{
          'kind': 'restageSurfacePublicationDeclaredArtifactBytes',
          'schemaVersion': 1,
          'tuples': [for (final tuple in tupleRecords) tuple.value],
        }),
      );
      final proof = MeasurementPublicationCandidateProofV1(
        selectedPublicationManifestCanonicalBytes: selectedManifestBytes,
        declaredArtifactTuples: [
          for (final tuple in tupleRecords)
            MeasurementPublicationCandidateArtifactTupleV1(
              canonicalTupleBytes: tuple.bytes,
            ),
        ],
        declaredArtifactBytesDigest: declaredArtifactBytesDigest,
        assembledPublicationUploadCanonicalBytes: uploadBytes,
        measurementPublicationDraft: indexed.draft,
      );
      return MeasurementBoundSurfacePublicationUploadWire(
        proof: proof,
        declaredArtifactClosure: uploadArtifacts,
      );
    } on PublicationException {
      rethrow;
    } on Object catch (error) {
      throw PublicationAssemblyException(
        'Generated Measurement publication input for '
        '${entry.publication.surface.wireName}/${entry.publication.slug} '
        'is stale, incomplete, or mismatched: $error. Re-run '
        '`dart run build_runner build` and retry.',
      );
    }
  }
}

final class _IndexedMeasurementPublication {
  const _IndexedMeasurementPublication({
    required this.publication,
    required this.draft,
  });

  final SurfacePublicationManifestEntry publication;
  final MeasurementPublicationDraftV1 draft;
}

Future<List<_IndexedMeasurementPublication>> _readIndex(
  File file,
  LoadedSurfacePublicationManifest loaded,
) async {
  final perEntryLimit =
      ((kMaximumMeasurementPublicationCandidateDraftBytes + 2) ~/ 3) * 4 +
      kMaximumMeasurementPublicationCandidateDraftBytes +
      4096;
  final maximumBytes =
      1024 + loaded.manifest.publications.length * perEntryLimit;
  final length = await file.length();
  if (length < 1 || length > maximumBytes) {
    throw const FormatException(
      'the Measurement publication index exceeds its generated-output bound',
    );
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > maximumBytes) {
    throw const FormatException(
      'the Measurement publication index exceeds its generated-output bound',
    );
  }
  final root = _object(CanonicalJsonCodec.decode(bytes), 'Measurement index');
  _exactKeys(root, const {
    'entries',
    'kind',
    'package',
    'schemaVersion',
  }, 'Measurement index');
  if (_string(root, 'kind', 'Measurement index') !=
          'restageMeasurementPublicationIndex' ||
      _integer(root, 'schemaVersion', 'Measurement index') != 1) {
    throw const FormatException(
      'the Measurement publication index uses an unsupported contract',
    );
  }
  if (_string(root, 'package', 'Measurement index') !=
      loaded.outputIndex.packageName) {
    throw const FormatException(
      'the Measurement publication index belongs to another package',
    );
  }
  final rawEntries = _list(root, 'entries', 'Measurement index');
  if (rawEntries.length > loaded.manifest.publications.length) {
    throw const FormatException(
      'the Measurement publication index has more drafts than publication '
      'publications',
    );
  }

  final seen = <SurfacePublicationManifestEntry>{};
  final result = <_IndexedMeasurementPublication>[];
  for (var index = 0; index < rawEntries.length; index++) {
    final path = 'Measurement index entry $index';
    final value = _object(rawEntries[index], path);
    _exactKeys(value, const {
      'draftBase64',
      'draftDigest',
      'routePlanDigest',
      'selector',
      'surfaceId',
    }, path);
    final publication = _publicationForSelector(
      loaded.manifest,
      _object(value['selector'], '$path selector'),
    );
    if (!seen.add(publication)) {
      throw const FormatException(
        'the Measurement publication index repeats a publication selector',
      );
    }
    final draftBytes = _canonicalBase64Url(
      _string(value, 'draftBase64', path),
      '$path draftBase64',
      maximumDecodedLength: kMaximumMeasurementPublicationCandidateDraftBytes,
    );
    if (draftBytes.length > kMaximumMeasurementPublicationCandidateDraftBytes) {
      throw FormatException('$path draft exceeds its byte limit');
    }
    final draft = MeasurementPublicationDraftV1.fromCanonicalBytes(draftBytes);
    if (_string(value, 'draftDigest', path) != draft.canonicalDigest.hex ||
        _string(value, 'routePlanDigest', path) !=
            draft.routeDraftClosureDigest.hex ||
        _string(value, 'surfaceId', path) != draft.surfaceId.value) {
      throw FormatException('$path digest or surface identity is stale');
    }
    _validateDraftArtifactClosure(entry: publication, draft: draft);
    result.add(
      _IndexedMeasurementPublication(publication: publication, draft: draft),
    );
  }
  return result;
}

SurfacePublicationManifestEntry _publicationForSelector(
  SurfacePublicationManifest manifest,
  Map<String, Object?> selector,
) {
  final sourceKind = SurfaceSourceKind.fromWireName(
    _string(selector, 'sourceKind', 'Measurement selector'),
  );
  final expectedKeys = <String>{'slug', 'sourceKind', 'surface'};
  if (sourceKind == SurfaceSourceKind.screen) {
    expectedKeys.add('contractVersion');
  }
  _exactKeys(selector, expectedKeys, 'Measurement selector');
  final surface = Surface.fromWireName(
    _string(selector, 'surface', 'Measurement selector'),
  );
  final slug = _string(selector, 'slug', 'Measurement selector');
  final contractVersion = sourceKind == SurfaceSourceKind.screen
      ? _positiveInteger(selector, 'contractVersion', 'Measurement selector')
      : null;
  final matches = [
    for (final entry in manifest.publications)
      if (entry.publication.surface == surface &&
          entry.publication.slug == slug &&
          entry.publication.sourceKind == sourceKind &&
          entry.publication.contractVersion == contractVersion)
        entry,
  ];
  if (matches.length != 1) {
    throw const FormatException(
      'a Measurement selector does not name exactly one publication',
    );
  }
  return matches.single;
}

void _validateDraftArtifactClosure({
  required SurfacePublicationManifestEntry entry,
  required MeasurementPublicationDraftV1 draft,
  Map<String, Uint8List>? artifactBytes,
}) {
  final expectedSurfaceId = _measurementSurfaceId(entry.publication);
  if (draft.surfaceId.value != expectedSurfaceId ||
      draft.deliverySurfaceType.value != entry.publication.surface.wireName ||
      draft.artifacts.length != entry.artifacts.length) {
    throw const FormatException(
      'the Measurement draft does not match its exact publication',
    );
  }
  final draftById = <String, MeasurementPublicationDraftArtifactV1>{};
  for (final artifact in draft.artifacts) {
    if (draftById.putIfAbsent(artifact.artifactId.value, () => artifact) !=
        artifact) {
      throw const FormatException(
        'the Measurement draft repeats a publication artifact definition',
      );
    }
  }
  for (final artifact in entry.artifacts) {
    final artifactId = _measurementArtifactId(entry.publication, artifact);
    final measured = draftById[artifactId];
    final expectedKind = switch (artifact.role) {
      SurfacePublicationArtifactRole.flowDocument =>
        'publication.flow-document',
      SurfacePublicationArtifactRole.screenBlob => 'rfw.blob',
      SurfacePublicationArtifactRole.capabilitySidecar =>
        'publication.capability-sidecar',
    };
    if (measured == null ||
        measured.artifactKind.value != expectedKind ||
        measured.contentHash.hex != artifact.contentHash.substring(7)) {
      throw FormatException(
        'the Measurement draft artifact does not match ${artifact.path}',
      );
    }
    final bytes = artifactBytes?[artifact.path];
    if (artifactBytes != null &&
        (bytes == null ||
            crypto.sha256.convert(bytes).toString() !=
                measured.contentHash.hex)) {
      throw FormatException(
        'the Measurement draft bytes do not match ${artifact.path}',
      );
    }
  }
}

void _validateRouteClosure({
  required SurfacePublicationManifestEntry entry,
  required MeasurementPublicationDraftV1 draft,
  required Map<String, String> carriersByArtifact,
}) {
  final draftRoutes = {for (final route in draft.routes) route.carrier: route};
  if (draftRoutes.length != carriersByArtifact.length ||
      !draftRoutes.keys.toSet().containsAll(carriersByArtifact.keys) ||
      !carriersByArtifact.keys.toSet().containsAll(draftRoutes.keys)) {
    throw const FormatException(
      'the Measurement route carriers do not match the generated draft',
    );
  }
  final artifactByEdge = {
    for (final artifact in draft.artifacts)
      artifact.occurrenceEdgeToken.value: artifact,
  };
  final pathByArtifactId = {
    for (final artifact in entry.artifacts)
      _measurementArtifactId(entry.publication, artifact): artifact.path,
  };
  for (final route in draft.routes) {
    final measuredArtifact =
        artifactByEdge[route.artifactOccurrenceEdgeToken.value];
    final expectedPath = measuredArtifact == null
        ? null
        : pathByArtifactId[measuredArtifact.artifactId.value];
    if (expectedPath == null ||
        carriersByArtifact[route.carrier] != expectedPath) {
      throw const FormatException(
        'a Measurement route carrier is attached to the wrong publication artifact',
      );
    }
  }
}

Map<String, String> _readCarriers(
  SurfacePublicationManifestEntry entry,
  Map<String, Uint8List> artifactBytes,
) {
  final carriers = <String, String>{};
  for (final artifact in entry.artifacts) {
    if (artifact.role != SurfacePublicationArtifactRole.screenBlob) continue;
    final bytes = artifactBytes[artifact.path];
    if (bytes == null) {
      throw FormatException(
        'the selected publication closure is missing ${artifact.path}',
      );
    }
    final library = rfw.decodeLibraryBlob(bytes);
    late void Function(rfw.BlobNode node) visitNode;
    void visitValue(Object? value) {
      if (value is rfw.BlobNode) {
        visitNode(value);
      } else if (value is Map) {
        for (final nested in value.values) {
          visitValue(nested);
        }
      } else if (value is List) {
        for (final nested in value) {
          visitValue(nested);
        }
      }
    }

    void recordEvent(rfw.EventHandler event) {
      for (final argument in event.eventArguments.entries) {
        if (!argument.key.startsWith(
          kMeasurementPublicationReservedArgumentPrefixV1,
        )) {
          visitValue(argument.value);
          continue;
        }
        final carrier = argument.value;
        if (argument.key != kMeasurementPublicationRouteArgumentKeyV1 ||
            carrier is! String) {
          throw const FormatException(
            'a generated event contains a malformed Measurement argument',
          );
        }
        try {
          MeasurementPublicationRouteCarrierV1.parse(carrier);
        } on ArgumentError {
          throw const FormatException(
            'a generated event contains a malformed Measurement carrier',
          );
        }
        if (carriers.containsKey(carrier)) {
          throw const FormatException(
            'a Measurement route carrier occurs more than once',
          );
        }
        carriers[carrier] = artifact.path;
      }
    }

    visitNode = (rfw.BlobNode node) {
      switch (node) {
        case rfw.ConstructorCall():
          visitValue(node.arguments);
        case rfw.EventHandler():
          recordEvent(node);
        case rfw.WidgetBuilderDeclaration():
          visitNode(node.widget);
        case rfw.Loop():
          visitValue(node.input);
          visitValue(node.output);
        case rfw.Switch():
          visitValue(node.input);
          visitValue(node.outputs);
        default:
          break;
      }
    };

    for (final widget in library.widgets) {
      visitValue(widget.initialState);
      visitNode(widget.root);
    }
  }
  return carriers;
}

String _measurementSurfaceId(SurfacePublication publication) {
  final line = <String, Object?>{
    if (publication.sourceKind == SurfaceSourceKind.screen)
      'contractVersion': publication.contractVersion,
    'kind': 'publicationLine',
    'schemaVersion': 1,
    'slug': publication.slug,
    'sourceKind': publication.sourceKind.wireName,
    'surface': publication.surface.wireName,
  };
  return 'surface.v1.${_privateDigest(_publicationLineDomain, line)}';
}

String _measurementArtifactId(
  SurfacePublication publication,
  SurfacePublicationArtifact artifact,
) {
  final selector = <String, Object?>{
    if (publication.sourceKind == SurfaceSourceKind.screen)
      'contractVersion': publication.contractVersion,
    'slug': publication.slug,
    'sourceKind': publication.sourceKind.wireName,
    'surface': publication.surface.wireName,
  };
  final identity = <String, Object?>{
    'artifactSlot': '${artifact.role.wireName}:${artifact.id ?? ''}',
    'publication': selector,
  };
  return 'artifact.v1.${_privateDigest(_artifactDefinitionDomain, identity)}';
}

String _privateDigest(String domain, Object? value) => crypto.sha256.convert(
  <int>[...utf8.encode('$domain\u0000'), ...CanonicalJsonCodec.encode(value)],
).toString();

Uint8List _canonicalBase64Url(
  String value,
  String path, {
  required int maximumDecodedLength,
}) {
  final maximumEncodedLength = ((maximumDecodedLength + 2) ~/ 3) * 4;
  if (value.contains('=') || value.length > maximumEncodedLength) {
    throw FormatException('$path must use unpadded base64url');
  }
  try {
    final bytes = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(value)),
    );
    if (base64UrlEncode(bytes).replaceAll('=', '') != value) {
      throw const FormatException('noncanonical base64url');
    }
    return bytes;
  } on FormatException {
    throw FormatException('$path must use canonical unpadded base64url');
  }
}

int _compareBytes(List<int> left, List<int> right) {
  final shared = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < shared; index++) {
    final difference = left[index] - right[index];
    if (difference != 0) return difference;
  }
  return left.length - right.length;
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map) throw FormatException('$path must be an object');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$path keys must be strings');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _exactKeys(Map<String, Object?> value, Set<String> keys, String path) {
  if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
    throw FormatException('$path has unsupported or missing fields');
  }
}

String _string(Map<String, Object?> value, String key, String path) {
  final result = value[key];
  if (result is! String || result.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return result;
}

int _integer(Map<String, Object?> value, String key, String path) {
  final result = value[key];
  if (result is! int) throw FormatException('$path.$key must be an integer');
  return result;
}

int _positiveInteger(Map<String, Object?> value, String key, String path) {
  final result = _integer(value, key, path);
  if (result < 1) {
    throw FormatException('$path.$key must be a positive integer');
  }
  return result;
}

List<Object?> _list(Map<String, Object?> value, String key, String path) {
  final result = value[key];
  if (result is! List) throw FormatException('$path.$key must be a list');
  return List<Object?>.from(result);
}
