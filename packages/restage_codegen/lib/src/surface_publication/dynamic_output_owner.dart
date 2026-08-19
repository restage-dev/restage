import 'dart:convert';

import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

/// The one fixed normal-builder output consumed by the dynamic owner.
const String kRestageSurfacePublicationBundlePath =
    'assets/restage/surface-publication.bundle.json';

/// The authoritative generated publication metadata output.
const String kRestageSurfacePublicationManifestPath =
    'assets/restage/surface-publication-manifest.json';

/// The fail-closed diagnostic output written when a bundle is invalid.
const String kRestageSurfacePublicationInvalidPath =
    'assets/restage/surface-publication.invalid';

/// The compiler-to-owner handoff asset.
///
/// The compiler lane may produce this package-local, fixed bundle under its
/// `lib/src/surface_publication` seam.  The owner consumes only this normalized
/// asset; it does not rediscover declarations or infer sibling artifact paths.
const String kRestageSurfacePublicationCompilerBundlePath =
    'lib/src/surface_publication/surface_publication.compiler.json';

/// A strict, deterministic handoff between aggregate compilation and the
/// post-process output owner.
@immutable
final class RestageSurfacePublicationBundle {
  RestageSurfacePublicationBundle._({
    required this.valid,
    required List<String> errors,
    required this.manifest,
    required Map<String, List<int>> artifacts,
    required Map<String, List<int>> borrowedArtifacts,
    required Map<String, List<int>> ownedOutputs,
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
        });

  /// Creates and validates a complete delivery bundle.
  factory RestageSurfacePublicationBundle.valid({
    required SurfacePublicationManifestV1 manifest,
    required Map<String, List<int>> artifacts,
    Map<String, List<int>> borrowedArtifacts = const {},
    Map<String, List<int>> ownedOutputs = const {},
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
    return RestageSurfacePublicationBundle._(
      valid: true,
      errors: const [],
      manifest: canonicalManifest,
      artifacts: frozenArtifacts,
      borrowedArtifacts: frozenBorrowedArtifacts,
      ownedOutputs: frozenOwnedOutputs,
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
      },
      r'$',
    );
    final schemaVersion = _requiredInt(json, 'schemaVersion', r'$');
    if (schemaVersion != 1) {
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

    if (!valid) {
      if (errors.isEmpty) {
        throw const FormatException(
          'An invalid surface publication bundle requires diagnostics.',
        );
      }
      if (json['manifest'] != null ||
          rawArtifacts.isNotEmpty ||
          rawBorrowedArtifacts.isNotEmpty ||
          rawOwnedOutputs.isNotEmpty) {
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
    return RestageSurfacePublicationBundle.valid(
      manifest: manifest,
      artifacts: artifacts,
      borrowedArtifacts: borrowedArtifacts,
      ownedOutputs: ownedOutputs,
    );
  }

  /// Whether this bundle is safe to materialize.
  final bool valid;

  /// Deterministic diagnostics for an invalid bundle.
  final List<String> errors;

  /// The complete strict manifest, present only for a valid bundle.
  final SurfacePublicationManifestV1? manifest;

  /// Exact package-relative artifact bytes keyed by their manifest paths.
  final Map<String, List<int>> artifacts;

  /// Exact manifest-closure bytes owned by conventional legacy builders.
  /// They are validated and serialized in the aggregate contract but are not
  /// written by the dynamic owner.
  final Map<String, List<int>> borrowedArtifacts;

  /// Roster-owned outputs outside the delivery manifest closure.
  ///
  /// This carries generated Dart parts and inspectable RFW text without
  /// weakening the manifest's exact hash-bound artifact closure.
  final Map<String, List<int>> ownedOutputs;

  /// Encodes the fixed aggregate handoff deterministically.
  String encodeCanonicalJson() {
    final value = <String, Object?>{
      'schemaVersion': 1,
      'valid': valid,
      'errors': errors,
      'manifest': manifest?.toJson(),
      'artifacts': [
        for (final entry
            in artifacts.entries.toList()
              ..sort((left, right) => left.key.compareTo(right.key)))
          <String, Object?>{
            'path': entry.key,
            'contentBase64': base64UrlEncode(entry.value).replaceAll('=', ''),
          },
      ],
      'borrowedArtifacts': [
        for (final entry
            in borrowedArtifacts.entries.toList()
              ..sort((left, right) => left.key.compareTo(right.key)))
          <String, Object?>{
            'path': entry.key,
            'contentBase64': base64UrlEncode(entry.value).replaceAll('=', ''),
          },
      ],
      'ownedOutputs': [
        for (final entry
            in ownedOutputs.entries.toList()
              ..sort((left, right) => left.key.compareTo(right.key)))
          <String, Object?>{
            'path': entry.key,
            'contentBase64': base64UrlEncode(entry.value).replaceAll('=', ''),
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(value);
  }
}

/// Produces the one fixed aggregate bundle consumed by the post-process owner.
///
/// Packages with no canonical declarations receive a valid empty manifest.
/// Canonical declarations fail closed when the compiler handoff is missing,
/// invalid, or unexpectedly empty rather than producing a partial family.
@internal
final class RestageSurfacePublicationBundleBuilder implements Builder {
  /// Creates the aggregate bundle builder.
  const RestageSurfacePublicationBundleBuilder(this.options);

  /// Reserved for compiler-lane options.
  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$package$': [kRestageSurfacePublicationBundlePath],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final bundle = await _readCompilerBundle(buildStep);
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, kRestageSurfacePublicationBundlePath),
      bundle.encodeCanonicalJson(),
    );
  }

  Future<RestageSurfacePublicationBundle> _readCompilerBundle(
    BuildStep buildStep,
  ) async {
    var hasCanonicalSource = false;
    final sourceIndex = AssetId(
      buildStep.inputId.package,
      'assets/restage/source-index.json',
    );
    if (await buildStep.canRead(sourceIndex)) {
      try {
        hasCanonicalSource = _containsCanonicalSource(
          jsonDecode(await buildStep.readAsString(sourceIndex)),
        );
      } on Object catch (error) {
        return RestageSurfacePublicationBundle.invalid(<String>[
          'Restage source index is invalid: $error',
        ]);
      }
    }

    final compilerInput = AssetId(
      buildStep.inputId.package,
      kRestageSurfacePublicationCompilerBundlePath,
    );
    if (await buildStep.canRead(compilerInput)) {
      try {
        final bundle = RestageSurfacePublicationBundle.fromJson(
          jsonDecode(await buildStep.readAsString(compilerInput)),
        );
        if (hasCanonicalSource &&
            bundle.valid &&
            bundle.manifest!.publications.isEmpty) {
          const message =
              'Canonical Restage sources were admitted, but package '
              'compilation produced an empty publication manifest.';
          return RestageSurfacePublicationBundle.invalid(const [message]);
        }
        return bundle;
      } on Object catch (error) {
        return RestageSurfacePublicationBundle.invalid(<String>[
          'Compiler publication bundle is invalid: $error',
        ]);
      }
    }

    if (hasCanonicalSource) {
      const message =
          'Canonical Restage sources were admitted, but the compiler '
          'publication bundle is missing.';
      return RestageSurfacePublicationBundle.invalid(const [message]);
    }

    return RestageSurfacePublicationBundle.valid(
      manifest: SurfacePublicationManifestV1(publications: const []),
      artifacts: const {},
    );
  }
}

/// Owns all dynamic publication outputs from one fixed bundle input.
///
/// Validation is complete before the first delivery artifact is written. The
/// build runner therefore sees one authoritative output family per successful
/// bundle, and its post-process output bookkeeping removes paths that were
/// owned by the preceding bundle but are absent from the current one.
@internal
final class RestageSurfacePublicationOutputOwner implements PostProcessBuilder {
  /// Creates the post-process owner.
  const RestageSurfacePublicationOutputOwner(this.options);

  /// Reserved for future output-policy options.
  final BuilderOptions options;

  @override
  Iterable<String> get inputExtensions => const ['.bundle.json'];

  @override
  Future<void> build(PostProcessBuildStep buildStep) async {
    final RestageSurfacePublicationBundle bundle;
    try {
      bundle = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(await buildStep.readInputAsString()),
      );
    } on Object catch (error) {
      await _fail(buildStep, 'Surface publication bundle is invalid: $error');
      return;
    }

    if (!bundle.valid) {
      await _fail(
        buildStep,
        'Surface publication compilation failed: ${bundle.errors.join('; ')}',
      );
      return;
    }

    final manifest = bundle.manifest!;
    try {
      final outputs = <String, List<int>>{
        ...bundle.artifacts,
        ...bundle.ownedOutputs,
      };
      for (final entry in outputs.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key))) {
        await buildStep.writeAsBytes(
          AssetId(buildStep.inputId.package, entry.key),
          entry.value,
        );
      }
      await buildStep.writeAsString(
        AssetId(
          buildStep.inputId.package,
          kRestageSurfacePublicationManifestPath,
        ),
        SurfacePublicationManifestV1Codec.encodeCanonicalJson(manifest),
      );
    } on Object catch (error) {
      await _fail(
        buildStep,
        'Surface publication output materialization failed: $error',
      );
    }
  }

  Future<void> _fail(PostProcessBuildStep buildStep, String message) async {
    log.severe(message);
    await buildStep.writeAsString(
      AssetId(
        buildStep.inputId.package,
        kRestageSurfacePublicationInvalidPath,
      ),
      message,
    );
    throw StateError(message);
  }
}

SurfacePublicationManifestV1 _canonicalizeManifest(
  SurfacePublicationManifestV1 manifest,
) {
  final entries = [
    for (final entry in manifest.publications)
      SurfacePublicationManifestEntryV1(
        publication: entry.publication,
        artifacts: [...entry.artifacts]..sort((left, right) {
            final path = left.path.compareTo(right.path);
            if (path != 0) return path;
            final role = left.role.wireName.compareTo(right.role.wireName);
            if (role != 0) return role;
            return (left.id ?? '').compareTo(right.id ?? '');
          }),
      ),
  ]..sort((left, right) {
      final surface = left.publication.surface.wireName.compareTo(
        right.publication.surface.wireName,
      );
      if (surface != 0) return surface;
      return left.publication.slug.compareTo(right.publication.slug);
    });
  return SurfacePublicationManifestV1(publications: entries);
}

bool _containsCanonicalSource(Object? value) {
  final json = _requireObject(value, r'$');
  final sources = _requiredList(json, 'sources', r'$');
  for (var index = 0; index < sources.length; index += 1) {
    final source = _requireObject(sources[index], '\$.sources[$index]');
    if (_requiredString(source, 'authoring', '\$.sources[$index]') ==
        'canonical') {
      return true;
    }
  }
  return false;
}

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
        path == kRestageSurfacePublicationCompilerBundlePath ||
        path == kRestageSurfacePublicationBundlePath ||
        path == kRestageSurfacePublicationManifestPath ||
        path == kRestageSurfacePublicationInvalidPath) {
      throw FormatException(
        'Invalid surface publication output path "$path".',
      );
    }
  }
}
