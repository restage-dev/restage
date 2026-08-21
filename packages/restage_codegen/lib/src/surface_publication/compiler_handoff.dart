import 'dart:convert';

import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

/// The package-local, fixed compiler-to-builder handoff asset.
///
/// The compiler lane produces this normalized bundle under its
/// `lib/src/surface_publication` seam. The unified outputs builder consumes
/// only this asset; it does not rediscover declarations or infer sibling
/// artifact paths.
const String kRestageSurfacePublicationCompilerBundlePath =
    'lib/src/surface_publication/surface_publication.compiler.json';

/// Reads this package's compiler handoff, or returns `null` when there is
/// nothing safe to materialize from.
///
/// Every materializing builder consumes the handoff on exactly these terms —
/// an absent asset means this package compiles no surfaces, and a malformed
/// or failed handoff is reported once and then produces no output — so they
/// share one reader rather than each restating the terms and risking drift.
///
/// The materializing builders run once per Dart library, and decoding the
/// handoff means decoding every compiled artifact's bytes, so the decode is
/// performed once per package per build and shared. The `canRead` below is
/// deliberately not shared: it is what declares the handoff an input of *this*
/// step, and without it an edited handoff would not invalidate the steps that
/// consumed it. Sharing also makes the "reported once" above literally true —
/// a failed decode is remembered, not re-reported per library.
Future<RestageSurfacePublicationBundle?> readRestageCompilerHandoff(
  BuildStep buildStep,
) async {
  final compilerInput = AssetId(
    buildStep.inputId.package,
    kRestageSurfacePublicationCompilerBundlePath,
  );
  if (!await buildStep.canRead(compilerInput)) return null;

  final cache = await buildStep.fetchResource(_compilerHandoffResource);
  return cache.get(buildStep, compilerInput);
}

final Resource<_CompilerHandoffCache> _compilerHandoffResource =
    Resource<_CompilerHandoffCache>(_CompilerHandoffCache.new);

/// One decoded handoff per package, for the lifetime of one build.
final class _CompilerHandoffCache {
  final Map<String, Future<RestageSurfacePublicationBundle?>> _byPackage = {};

  Future<RestageSurfacePublicationBundle?> get(
    BuildStep buildStep,
    AssetId compilerInput,
  ) =>
      _byPackage.putIfAbsent(
        compilerInput.package,
        () => _decodeCompilerHandoff(buildStep, compilerInput),
      );
}

Future<RestageSurfacePublicationBundle?> _decodeCompilerHandoff(
  BuildStep buildStep,
  AssetId compilerInput,
) async {
  final RestageSurfacePublicationBundle bundle;
  try {
    bundle = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(await buildStep.readAsString(compilerInput)),
    );
  } on Object catch (error) {
    log.severe('Surface publication compiler handoff is invalid: $error');
    return null;
  }
  if (!bundle.valid) {
    log.severe(
      'Surface publication compilation failed: ${bundle.errors.join('; ')}',
    );
    return null;
  }
  return bundle;
}

/// A strict, deterministic handoff between aggregate compilation and the
/// unified outputs builder.
@immutable
final class RestageSurfacePublicationBundle {
  RestageSurfacePublicationBundle._({
    required this.valid,
    required List<String> errors,
    required this.manifest,
    required Map<String, List<int>> artifacts,
    required Map<String, List<int>> borrowedArtifacts,
    required Map<String, List<int>> ownedOutputs,
    required Map<String, String> artifactLibraryPaths,
  })  : errors = List.unmodifiable(errors),
        artifacts = Map.unmodifiable({
          for (final entry in artifacts.entries)
            entry.key: List<int>.unmodifiable(entry.value),
        }),
        borrowedArtifacts = Map.unmodifiable({
          for (final entry in borrowedArtifacts.entries)
            entry.key: List<int>.unmodifiable(entry.value),
        }),
        ownedOutputs = Map.unmodifiable({
          for (final entry in ownedOutputs.entries)
            entry.key: List<int>.unmodifiable(entry.value),
        }),
        artifactLibraryPaths = Map.unmodifiable(
          Map.of(artifactLibraryPaths),
        );

  /// Creates and validates a complete delivery bundle.
  factory RestageSurfacePublicationBundle.valid({
    required SurfacePublicationManifest manifest,
    required Map<String, List<int>> artifacts,
    Map<String, List<int>> borrowedArtifacts = const {},
    Map<String, List<int>> ownedOutputs = const {},
    Map<String, String> artifactLibraryPaths = const {},
  }) {
    final canonicalManifest = _canonicalizeManifest(manifest);
    final frozenArtifacts = <String, List<int>>{
      for (final entry in artifacts.entries)
        entry.key: List<int>.unmodifiable(entry.value),
    };
    final frozenOwnedOutputs = <String, List<int>>{
      for (final entry in ownedOutputs.entries)
        entry.key: List<int>.unmodifiable(entry.value),
    };
    final frozenBorrowedArtifacts = <String, List<int>>{
      for (final entry in borrowedArtifacts.entries)
        entry.key: List<int>.unmodifiable(entry.value),
    };
    final overlaps = <String>{
      ...frozenArtifacts.keys.where(frozenBorrowedArtifacts.containsKey),
      ...frozenArtifacts.keys.where(frozenOwnedOutputs.containsKey),
      ...frozenBorrowedArtifacts.keys.where(frozenOwnedOutputs.containsKey),
    }.toList()
      ..sort();
    if (overlaps.isNotEmpty) {
      throw FormatException(
        'Bundle outputs are declared as both manifest artifacts and ancillary '
        'owned outputs: ${overlaps.join(', ')}.',
      );
    }
    _validateOutputPaths([
      ...frozenArtifacts.keys,
      ...frozenBorrowedArtifacts.keys,
      ...frozenOwnedOutputs.keys,
    ]);
    canonicalManifest.validateArtifactClosure({
      ...frozenArtifacts,
      ...frozenBorrowedArtifacts,
    });
    final unattributed = <String>{
      ...frozenArtifacts.keys,
      ...frozenBorrowedArtifacts.keys,
    }.where((path) => !artifactLibraryPaths.containsKey(path)).toList()
      ..sort();
    if (unattributed.isNotEmpty) {
      throw FormatException(
        'Bundle manifest artifacts have no authored-library attribution: '
        '${unattributed.join(', ')}.',
      );
    }
    return RestageSurfacePublicationBundle._(
      valid: true,
      errors: const [],
      manifest: canonicalManifest,
      artifacts: frozenArtifacts,
      borrowedArtifacts: frozenBorrowedArtifacts,
      ownedOutputs: frozenOwnedOutputs,
      artifactLibraryPaths: artifactLibraryPaths,
    );
  }

  /// Creates a fail-closed bundle that carries diagnostics but no artifacts.
  factory RestageSurfacePublicationBundle.invalid(Iterable<String> errors) {
    final normalized = errors
        .map((error) => error.trim())
        .where((error) => error.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (normalized.isEmpty) {
      normalized.add('Surface publication compilation failed.');
    }
    return RestageSurfacePublicationBundle._(
      valid: false,
      errors: normalized,
      manifest: null,
      artifacts: const {},
      borrowedArtifacts: const {},
      ownedOutputs: const {},
      artifactLibraryPaths: const {},
    );
  }

  /// Decodes and validates a bundle supplied by the compiler lane.
  factory RestageSurfacePublicationBundle.fromJson(Object? value) {
    final json = _requireObject(value, r'$');
    _exactKeys(
      json,
      const {
        'schemaVersion',
        'valid',
        'errors',
        'manifest',
        'artifacts',
        'borrowedArtifacts',
        'ownedOutputs',
        'artifactLibraryPaths',
      },
      r'$',
    );
    final schemaVersion = _requiredInt(json, 'schemaVersion', r'$');
    if (schemaVersion != 2) {
      throw FormatException(
        'Unsupported surface publication bundle schemaVersion '
        '$schemaVersion.',
      );
    }
    final valid = _requiredBool(json, 'valid', r'$');
    final errors = _requiredStringList(json, 'errors', r'$');
    final rawArtifacts = _requiredList(json, 'artifacts', r'$');
    final rawBorrowedArtifacts = _requiredList(
      json,
      'borrowedArtifacts',
      r'$',
    );
    final rawOwnedOutputs = _requiredList(json, 'ownedOutputs', r'$');
    final rawArtifactLibraryPaths = _requiredList(
      json,
      'artifactLibraryPaths',
      r'$',
    );

    if (!valid) {
      if (errors.isEmpty) {
        throw const FormatException(
          'An invalid surface publication bundle requires diagnostics.',
        );
      }
      if (json['manifest'] != null ||
          rawArtifacts.isNotEmpty ||
          rawBorrowedArtifacts.isNotEmpty ||
          rawOwnedOutputs.isNotEmpty ||
          rawArtifactLibraryPaths.isNotEmpty) {
        throw const FormatException(
          'An invalid surface publication bundle must not carry outputs.',
        );
      }
      return RestageSurfacePublicationBundle.invalid(errors);
    }

    if (errors.isNotEmpty) {
      throw const FormatException(
        'A valid surface publication bundle must not carry diagnostics.',
      );
    }
    final manifestValue = json['manifest'];
    if (manifestValue == null) {
      throw const FormatException(
        'A valid surface publication bundle requires a manifest.',
      );
    }
    final manifest = SurfacePublicationManifestV1Codec.decode(manifestValue);
    final artifacts = _decodeBundleOutputs(rawArtifacts, r'$.artifacts');
    final borrowedArtifacts = _decodeBundleOutputs(
      rawBorrowedArtifacts,
      r'$.borrowedArtifacts',
    );
    final ownedOutputs = _decodeBundleOutputs(
      rawOwnedOutputs,
      r'$.ownedOutputs',
    );
    final artifactLibraryPaths = _decodeArtifactLibraryPaths(
      rawArtifactLibraryPaths,
      r'$.artifactLibraryPaths',
    );
    return RestageSurfacePublicationBundle.valid(
      manifest: manifest,
      artifacts: artifacts,
      borrowedArtifacts: borrowedArtifacts,
      ownedOutputs: ownedOutputs,
      artifactLibraryPaths: artifactLibraryPaths,
    );
  }

  /// Whether this bundle is safe to materialize.
  final bool valid;

  /// Deterministic diagnostics for an invalid bundle.
  final List<String> errors;

  /// The complete strict manifest, present only for a valid bundle.
  final SurfacePublicationManifest? manifest;

  /// Exact package-relative artifact bytes keyed by their manifest paths.
  final Map<String, List<int>> artifacts;

  /// Exact manifest-closure bytes owned by conventional legacy builders.
  /// They are validated and serialized in the aggregate contract but are not
  /// written by the unified outputs builder as ancillary output.
  final Map<String, List<int>> borrowedArtifacts;

  /// Roster-owned outputs outside the delivery manifest closure.
  ///
  /// This carries generated Dart parts and inspectable RFW text without
  /// weakening the manifest's exact hash-bound artifact closure.
  final Map<String, List<int>> ownedOutputs;

  /// The authored Dart library path that produced each manifest artifact
  /// (the union of [artifacts] and [borrowedArtifacts]), keyed by logical
  /// artifact path. Every manifest artifact has exactly one entry.
  final Map<String, String> artifactLibraryPaths;

  /// Encodes the fixed aggregate handoff deterministically.
  String encodeCanonicalJson() {
    final value = <String, Object?>{
      'schemaVersion': 2,
      'valid': valid,
      'errors': errors,
      'manifest': manifest?.toJson(),
      'artifacts': _encodeOutputs(artifacts),
      'borrowedArtifacts': _encodeOutputs(borrowedArtifacts),
      'ownedOutputs': _encodeOutputs(ownedOutputs),
      'artifactLibraryPaths': [
        for (final entry
            in artifactLibraryPaths.entries.toList()
              ..sort((left, right) => left.key.compareTo(right.key)))
          <String, Object?>{
            'path': entry.key,
            'library': entry.value,
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(value);
  }
}

/// The canonical wire form of one output collection: path-sorted records
/// carrying unpadded base64url content. The three collections
/// [RestageSurfacePublicationBundle.encodeCanonicalJson] writes are encoded
/// identically, so they share this.
List<Map<String, Object?>> _encodeOutputs(Map<String, List<int>> outputs) => [
      for (final entry
          in outputs.entries.toList()
            ..sort((left, right) => left.key.compareTo(right.key)))
        <String, Object?>{
          'path': entry.key,
          'contentBase64': base64UrlEncode(entry.value).replaceAll('=', ''),
        },
    ];

SurfacePublicationManifest _canonicalizeManifest(
  SurfacePublicationManifest manifest,
) =>
    manifest.canonical();

Map<String, List<int>> _decodeBundleOutputs(
  List<Object?> values,
  String collectionPath,
) {
  final outputs = <String, List<int>>{};
  for (var index = 0; index < values.length; index += 1) {
    final path = '$collectionPath[$index]';
    final output = _requireObject(values[index], path);
    _exactKeys(output, const {'path', 'contentBase64'}, path);
    final outputPath = _requiredString(output, 'path', path);
    if (outputs.containsKey(outputPath)) {
      throw FormatException('Duplicate bundle output "$outputPath".');
    }
    final encoded = _requiredString(output, 'contentBase64', path);
    outputs[outputPath] = _decodeBase64Url(encoded, '$path.contentBase64');
  }
  return outputs;
}

Map<String, String> _decodeArtifactLibraryPaths(
  List<Object?> values,
  String collectionPath,
) {
  final result = <String, String>{};
  for (var index = 0; index < values.length; index += 1) {
    final path = '$collectionPath[$index]';
    final entry = _requireObject(values[index], path);
    _exactKeys(entry, const {'path', 'library'}, path);
    final artifactPath = _requiredString(entry, 'path', path);
    if (result.containsKey(artifactPath)) {
      throw FormatException(
        'Duplicate artifact library attribution for "$artifactPath".',
      );
    }
    result[artifactPath] = _requiredString(entry, 'library', path);
  }
  return result;
}

Map<String, Object?> _requireObject(Object? value, String path) {
  if (value is! Map) {
    throw FormatException('Expected "$path" to be an object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('Expected "$path" keys to be strings.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _exactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String path,
) {
  for (final key in value.keys) {
    if (!expected.contains(key)) {
      throw FormatException('Unsupported field "$path.$key".');
    }
  }
  for (final key in expected) {
    if (!value.containsKey(key)) {
      throw FormatException('Missing required field "$path.$key".');
    }
  }
}

Object? _requiredValue(
  Map<String, Object?> value,
  String key,
  String path,
) {
  if (!value.containsKey(key) || value[key] == null) {
    throw FormatException('Missing required field "$path.$key".');
  }
  return value[key];
}

String _requiredString(Map<String, Object?> value, String key, String path) {
  final result = _requiredValue(value, key, path);
  if (result is! String) {
    throw FormatException('Expected "$path.$key" to be a string.');
  }
  return result;
}

int _requiredInt(Map<String, Object?> value, String key, String path) {
  final result = _requiredValue(value, key, path);
  if (result is! int) {
    throw FormatException('Expected "$path.$key" to be an integer.');
  }
  return result;
}

bool _requiredBool(Map<String, Object?> value, String key, String path) {
  final result = _requiredValue(value, key, path);
  if (result is! bool) {
    throw FormatException('Expected "$path.$key" to be a boolean.');
  }
  return result;
}

List<Object?> _requiredList(
  Map<String, Object?> value,
  String key,
  String path,
) {
  final result = _requiredValue(value, key, path);
  if (result is! List) {
    throw FormatException('Expected "$path.$key" to be an array.');
  }
  return List<Object?>.of(result);
}

List<String> _requiredStringList(
  Map<String, Object?> value,
  String key,
  String path,
) {
  final values = _requiredList(value, key, path);
  return [
    for (var index = 0; index < values.length; index += 1)
      _requiredString(
        {'value': values[index]},
        'value',
        '$path.$key[$index]',
      ),
  ];
}

List<int> _decodeBase64Url(String value, String path) {
  if (value.isEmpty) {
    throw FormatException('Expected "$path" to be non-empty base64url.');
  }
  try {
    final decoded = base64Url.decode(base64Url.normalize(value));
    final canonical = base64UrlEncode(decoded).replaceAll('=', '');
    if (canonical != value) {
      throw FormatException('Expected "$path" to be canonical base64url.');
    }
    return decoded;
  } on FormatException {
    rethrow;
  } on Object {
    throw FormatException('Expected "$path" to be canonical base64url.');
  }
}

void _validateOutputPaths(Iterable<String> paths) {
  for (final path in paths) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains(r'\') ||
        path.split('/').any(
              (segment) => segment.isEmpty || segment == '.' || segment == '..',
            ) ||
        path == kRestageSurfacePublicationCompilerBundlePath) {
      throw FormatException(
        'Invalid surface publication output path "$path".',
      );
    }
  }
}
