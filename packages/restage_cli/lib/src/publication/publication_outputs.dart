import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_shared/restage_shared.dart';
import 'package:yaml/yaml.dart';

import 'publication_errors.dart';

/// The package-wide generated physical-output index filename.
const String restageOutputsFileName = 'restage.outputs.json';

/// The package-wide generated publication manifest filename.
const String restagePublicationFileName = 'restage.publication.json';

/// The default package-relative directory for generated portable metadata.
const String defaultRestagePortableOutputRoot = 'lib/generated';

/// The directory segment holding portable metadata under a configured
/// output root.
const String restageOutputRootMetadataSegment = 'metadata';

/// The build-tool builder key whose options select portable placement.
const String restageOutputsBuilderKey = 'restage_codegen:outputs';

/// The package-root sentinel recorded by an index with no configured root.
const String restagePackageRootSentinel = '.';

const int _schemaVersion = 1;
const int _defaultMaximumDiscoveryDepth = 12;
const int _maximumDiscoveryEntities = 10000;
final RegExp _sha256Pattern = RegExp(r'^sha256:[0-9a-f]{64}$');

/// One physical bundle locator for one logical publication artifact.
final class RestageOutputIndexEntry {
  /// Construct one validated locator entry.
  factory RestageOutputIndexEntry({
    required String bundle,
    required String entry,
    required String path,
    required String sha256,
  }) {
    _requirePackagePath(bundle, 'entry.bundle');
    if (!bundle.endsWith('.rsbundle')) {
      throw const FormatException('A bundle locator must end in .rsbundle.');
    }
    _requirePackagePath(entry, 'entry.entry');
    _requirePackagePath(path, 'entry.path');
    _requireSha256(sha256, 'entry.sha256');
    return RestageOutputIndexEntry._(
      bundle: bundle,
      entry: entry,
      path: path,
      sha256: sha256,
    );
  }

  /// Decode and validate one locator entry.
  factory RestageOutputIndexEntry.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = _requireObject(value, path);
    _exactKeys(json, const {'bundle', 'entry', 'path', 'sha256'}, path);
    final bundle = _requirePackagePath(
      _requireString(json, 'bundle', path),
      '$path.bundle',
    );
    if (!bundle.endsWith('.rsbundle')) {
      throw FormatException(
        'Expected "$path.bundle" to reference a .rsbundle file.',
      );
    }
    final entry = _requirePackagePath(
      _requireString(json, 'entry', path),
      '$path.entry',
    );
    final logicalPath = _requirePackagePath(
      _requireString(json, 'path', path),
      '$path.path',
    );
    final sha256 = _requireSha256(
      _requireString(json, 'sha256', path),
      '$path.sha256',
    );
    return RestageOutputIndexEntry._(
      bundle: bundle,
      entry: entry,
      path: logicalPath,
      sha256: sha256,
    );
  }

  const RestageOutputIndexEntry._({
    required this.bundle,
    required this.entry,
    required this.path,
    required this.sha256,
  });

  /// Exact package-relative bundle path.
  final String bundle;

  /// Exact path inside the bundle.
  final String entry;

  /// Canonical logical publication path.
  final String path;

  /// SHA-256 of the exact entry bytes.
  final String sha256;

  /// Encode the strict generated locator shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'bundle': bundle,
    'entry': entry,
    'sha256': sha256,
  };
}

/// Strict generated physical-output index for one package.
///
/// The index is written by the build-time toolchain and read here. It is the
/// only place the physical location of a logical artifact is resolved: this
/// class validates the recorded locators and never recomputes them from
/// placement options.
final class RestageOutputIndex {
  /// Construct a generated index from already ordered locator entries.
  factory RestageOutputIndex({
    required String packageName,
    required String physicalRoot,
    required String generationFingerprint,
    required String publicationManifestPath,
    required List<RestageOutputIndexEntry> entries,
  }) {
    final safeManifestPath = _requirePackagePath(
      publicationManifestPath,
      'publicationManifestPath',
    );
    if (p.posix.basename(safeManifestPath) != restagePublicationFileName) {
      throw const FormatException(
        'A generated output index publicationManifestPath must name '
        'restage.publication.json.',
      );
    }
    return RestageOutputIndex._(
      packageName: _requireIdentity(packageName, 'package'),
      physicalRoot: _requirePhysicalRoot(physicalRoot),
      generationFingerprint: _requireSha256(
        generationFingerprint,
        'generationFingerprint',
      ),
      publicationManifestPath: safeManifestPath,
      entries: _requireOrderedEntries(entries),
    );
  }

  /// Decode and validate the generated index envelope.
  factory RestageOutputIndex.fromJson(Object? value) {
    final json = _requireObject(value, r'$');
    _exactKeys(json, const {
      'schemaVersion',
      'package',
      'physicalRoot',
      'publicationManifestPath',
      'generationFingerprint',
      'entries',
    }, r'$');
    final schemaVersion = _requireInt(json, 'schemaVersion', r'$');
    if (schemaVersion != _schemaVersion) {
      throw FormatException(
        'Unsupported generated output index schemaVersion $schemaVersion.',
      );
    }
    final rawEntries = _requireList(
      _requireValue(json, 'entries', r'$'),
      r'$.entries',
    );
    final entries = <RestageOutputIndexEntry>[
      for (var index = 0; index < rawEntries.length; index += 1)
        RestageOutputIndexEntry.fromJson(
          rawEntries[index],
          path: '\$.entries[$index]',
        ),
    ];
    return RestageOutputIndex(
      packageName: _requireString(json, 'package', r'$'),
      physicalRoot: _requireString(json, 'physicalRoot', r'$'),
      generationFingerprint: _requireString(
        json,
        'generationFingerprint',
        r'$',
      ),
      publicationManifestPath: _requireString(
        json,
        'publicationManifestPath',
        r'$',
      ),
      entries: entries,
    );
  }

  RestageOutputIndex._({
    required this.packageName,
    required this.physicalRoot,
    required this.generationFingerprint,
    required this.publicationManifestPath,
    required List<RestageOutputIndexEntry> entries,
  }) : entries = List.unmodifiable(entries);

  /// Decode a generated index document.
  static RestageOutputIndex decodeJson(String source) {
    final Object? value;
    try {
      value = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException(
        'The generated output index is not valid JSON: ${error.message}',
      );
    }
    return RestageOutputIndex.fromJson(value);
  }

  /// Package name recorded by the generator.
  final String packageName;

  /// Resolved package-relative physical root, or `.` for the package root.
  final String physicalRoot;

  /// The generator's fingerprint over the canonical publication-manifest
  /// bytes this index was written against.
  final String generationFingerprint;

  /// Package-relative path to the paired publication manifest.
  final String publicationManifestPath;

  /// Locators sorted by logical path.
  final List<RestageOutputIndexEntry> entries;

  /// Encode the generated index in the exact shape the generator writes.
  String encodeJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Encode the strict generated index shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': _schemaVersion,
    'package': packageName,
    'physicalRoot': physicalRoot,
    'publicationManifestPath': publicationManifestPath,
    'generationFingerprint': generationFingerprint,
    'entries': <Object?>[for (final entry in entries) entry.toJson()],
  };

  /// Find the exact locator for [logicalPath].
  RestageOutputIndexEntry locatorFor(String logicalPath) {
    for (final entry in entries) {
      if (entry.path == logicalPath) return entry;
    }
    throw PublicationAssemblyException(
      'Generated publication artifact "$logicalPath" has no physical '
      'bundle locator. Re-run `dart run build_runner build` and retry.',
    );
  }

  /// Verify the locator set preserves the canonical publication manifest.
  void validateAgainstManifest(SurfacePublicationManifest manifest) {
    final artifactsByPath = <String, SurfacePublicationArtifact>{};
    for (final publication in manifest.publications) {
      for (final artifact in publication.artifacts) {
        final previous = artifactsByPath[artifact.path];
        if (previous != null &&
            (previous.contentHash != artifact.contentHash ||
                previous.role != artifact.role ||
                previous.id != artifact.id)) {
          throw const FormatException(
            'The generated publication manifest has conflicting artifact '
            'identity for one logical path.',
          );
        }
        artifactsByPath[artifact.path] = artifact;
      }
    }
    if (artifactsByPath.length != entries.length) {
      throw const FormatException(
        'The generated output index does not cover exactly the publication '
        'manifest artifact set.',
      );
    }
    for (final locator in entries) {
      final artifact = artifactsByPath[locator.path];
      if (artifact == null) {
        throw FormatException(
          'The generated output index contains undeclared artifact '
          '"${locator.path}".',
        );
      }
      if (locator.entry != artifact.path) {
        throw FormatException(
          'The bundle entry for "${artifact.path}" does not preserve its '
          'canonical logical path.',
        );
      }
      if (locator.sha256 != artifact.contentHash) {
        throw FormatException(
          'The bundle locator hash for "${artifact.path}" does not match '
          'the publication manifest.',
        );
      }
    }
  }
}

/// One located generated output index together with the exact publication
/// manifest bytes it was generated against.
final class LoadedRestagePublicationOutputs {
  /// Construct located generated outputs.
  const LoadedRestagePublicationOutputs({
    required this.projectRoot,
    required this.outputsFile,
    required this.publicationFile,
    required this.publicationManifestSource,
    required this.index,
  });

  /// Package root used to resolve all recorded physical paths.
  final Directory projectRoot;

  /// The selected physical-output index file.
  final File outputsFile;

  /// The publication manifest file the index points at.
  final File publicationFile;

  /// The exact publication manifest text the fingerprint was verified over.
  final String publicationManifestSource;

  /// The decoded strict output index.
  final RestageOutputIndex index;
}

/// Resolves generated publication metadata using the package's configured
/// placement first, then a bounded package-local search that exists only to
/// find a transient build-tool override.
final class RestagePublicationOutputsLoader {
  /// Construct an output loader with an optional discovery depth bound.
  const RestagePublicationOutputsLoader({
    int maximumDiscoveryDepth = _defaultMaximumDiscoveryDepth,
  }) : assert(maximumDiscoveryDepth >= 0),
       _maximumDiscoveryDepth = maximumDiscoveryDepth;

  final int _maximumDiscoveryDepth;

  /// Locate and decode exactly one generated output index, then read and
  /// verify the publication manifest it names.
  Future<LoadedRestagePublicationOutputs> load({
    required Directory projectRoot,
  }) async {
    final root = projectRoot.absolute;
    final outputsFile = await _locateIndexFile(root);

    final source = await _readText(outputsFile, 'generated output index');
    final RestageOutputIndex index;
    try {
      index = RestageOutputIndex.decodeJson(source);
    } on FormatException catch (error) {
      throw PublicationManifestException(
        'The generated output index at ${_relativePath(root, outputsFile)} is '
        'malformed: ${error.message} Re-run `dart run build_runner build` and '
        'retry.',
      );
    }

    final packageName = await _readPackageName(root);
    if (packageName != null && packageName != index.packageName) {
      throw PublicationManifestException(
        'The generated output index belongs to package '
        '"${index.packageName}", not "$packageName". Re-run '
        '`dart run build_runner build` and retry.',
      );
    }

    final publicationFile = _resolvePackageFile(
      root,
      index.publicationManifestPath,
      'publication manifest',
    );
    if (!publicationFile.existsSync()) {
      throw PublicationManifestException(
        'The generated output index points to a missing '
        '${index.publicationManifestPath}. Re-run '
        '`dart run build_runner build` and retry.',
      );
    }
    final publicationSource = await _readText(
      publicationFile,
      'generated publication manifest',
    );
    final fingerprint = CapabilitySidecar.hashBlob(
      utf8.encode(publicationSource),
    );
    if (fingerprint != index.generationFingerprint) {
      throw PublicationManifestException(
        'The generated output index is stale: its generation fingerprint does '
        'not match ${index.publicationManifestPath}. Re-run '
        '`dart run build_runner build` and retry.',
      );
    }

    return LoadedRestagePublicationOutputs(
      projectRoot: root,
      outputsFile: outputsFile,
      publicationFile: publicationFile,
      publicationManifestSource: publicationSource,
      index: index,
    );
  }

  /// Select the one current index file: the configured placement when it
  /// exists, otherwise the single transient-override candidate.
  Future<File> _locateIndexFile(Directory root) async {
    final configured = await _configuredIndexFile(root);
    final configuredPath = _relativePath(root, configured);
    final discovered = await _discoverIndexFiles(root);
    final strays = discovered
        .where((file) => _relativePath(root, file) != configuredPath)
        .toList(growable: false);

    if (configured.existsSync()) {
      if (strays.isNotEmpty) {
        throw PublicationManifestException(
          'Ambiguous generated output: $restageOutputsFileName exists at the '
          'configured $configuredPath and also at '
          '${_displayPaths(root, strays)}. Remove the stale output or re-run '
          '`dart run build_runner build`, then retry.',
        );
      }
      return configured;
    }
    if (strays.isEmpty) {
      throw PublicationGenerationRequiredException(
        'No generated publication output index was found. Expected '
        '$configuredPath. Run `dart run build_runner build` and retry.',
      );
    }
    if (strays.length > 1) {
      throw PublicationManifestException(
        'Ambiguous generated output: found more than one '
        '$restageOutputsFileName under the package root '
        '(${_displayPaths(root, strays)}). Remove the stale output or re-run '
        '`dart run build_runner build`, then retry.',
      );
    }
    return strays.single;
  }

  Future<File> _configuredIndexFile(Directory root) async {
    final outputRoot = await _configuredOutputRoot(root);
    final metadataRoot = outputRoot == null
        ? defaultRestagePortableOutputRoot
        : p.posix.join(outputRoot, restageOutputRootMetadataSegment);
    return _resolvePackageFile(
      root,
      p.posix.join(metadataRoot, restageOutputsFileName),
      'configured output index',
    );
  }

  Future<String?> _configuredOutputRoot(Directory root) async {
    final buildFile = File(p.join(root.path, 'build.yaml'));
    if (!buildFile.existsSync()) return null;
    final source = await _readText(buildFile, 'build.yaml');
    final Object? document;
    try {
      document = loadYaml(source);
    } on Object catch (error) {
      throw PublicationManifestException(
        'Could not parse build.yaml while locating generated publication '
        'metadata: $error.',
      );
    }
    if (document is! Map) return null;
    final globalOptions = _builderOptions(
      _mapValue(
        _mapValue(document, 'global_options'),
        restageOutputsBuilderKey,
      ),
    );
    final targets = _mapValue(document, 'targets');
    final defaultTarget = _mapValue(targets, r'$default');
    final targetOptions = _builderOptions(
      _mapValue(_mapValue(defaultTarget, 'builders'), restageOutputsBuilderKey),
    );
    final raw =
        _mapValue(globalOptions, 'output_root') ??
        _mapValue(targetOptions, 'output_root');
    if (raw == null) return null;
    if (raw is! String) {
      throw const PublicationManifestException(
        'The generated output_root in build.yaml must be a string.',
      );
    }
    try {
      return _requireOutputRoot(raw);
    } on FormatException catch (error) {
      throw PublicationManifestException(
        'Invalid generated output_root in build.yaml: ${error.message}',
      );
    }
  }

  Future<List<File>> _discoverIndexFiles(Directory root) async {
    final found = <File>[];
    final pending = <({Directory directory, int depth})>[
      (directory: root, depth: 0),
    ];
    var seenEntities = 0;
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      final directory = current.directory;
      final depth = current.depth;
      try {
        await for (final entity in directory.list(followLinks: false)) {
          seenEntities += 1;
          if (seenEntities > _maximumDiscoveryEntities) {
            throw const PublicationManifestException(
              'Generated publication metadata discovery exceeded its safety '
              'bound. Pass the package root containing the build output and '
              'retry.',
            );
          }
          if (entity is Directory) {
            if (depth < _maximumDiscoveryDepth &&
                !_isExcludedDirectory(p.basename(entity.path))) {
              pending.add((directory: entity, depth: depth + 1));
            }
          } else if (entity is File &&
              p.basename(entity.path) == restageOutputsFileName) {
            found.add(entity);
          }
        }
      } on PublicationException {
        rethrow;
      } on FileSystemException catch (error) {
        throw PublicationManifestException(
          'Could not inspect generated publication metadata under '
          '"${directory.path}": ${error.message}. Re-run '
          '`dart run build_runner build` and retry.',
        );
      }
    }
    found.sort((left, right) => left.path.compareTo(right.path));
    return found;
  }
}

Map<Object?, Object?>? _builderOptions(Object? value) {
  final map = _asMap(value);
  if (map == null) return null;
  final options = _asMap(map['options']);
  return options ?? map;
}

Map<Object?, Object?>? _asMap(Object? value) =>
    value is Map ? Map<Object?, Object?>.from(value) : null;

Object? _mapValue(Object? value, Object key) =>
    value is Map ? value[key] : null;

String _requireOutputRoot(String value) {
  final root = _requirePackagePath(value, 'build.yaml output_root');
  if (root.split('/').contains('.dart_tool')) {
    throw const FormatException(
      'Expected "build.yaml output_root" to stay outside .dart_tool.',
    );
  }
  return root;
}

String _requirePhysicalRoot(String value) => value == restagePackageRootSentinel
    ? value
    : _requirePackagePath(value, 'physicalRoot');

String _requirePackagePath(String value, String path) {
  _requireIdentity(value, path);
  if (value.startsWith('/') || value.contains('\\')) {
    throw FormatException('Expected "$path" to be package-relative.');
  }
  final segments = value.split('/');
  if (segments.first.contains(':')) {
    throw FormatException('Expected "$path" to be package-relative.');
  }
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      throw FormatException(
        'Expected "$path" to have canonical path segments.',
      );
    }
  }
  return value;
}

String _requireIdentity(String value, String path) {
  if (value.isEmpty || value.trim() != value || value.contains('\u0000')) {
    throw FormatException(
      'Expected "$path" to be nonempty, trimmed, and NUL-free.',
    );
  }
  return value;
}

String _requireSha256(String value, String path) {
  if (!_sha256Pattern.hasMatch(value)) {
    throw FormatException('Expected "$path" to be sha256:<64 lowercase hex>.');
  }
  return value;
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

List<Object?> _requireList(Object? value, String path) {
  if (value is! List) {
    throw FormatException('Expected "$path" to be an array.');
  }
  return List<Object?>.of(value);
}

Object? _requireValue(Map<String, Object?> json, String key, String path) {
  if (!json.containsKey(key) || json[key] == null) {
    throw FormatException('Missing required field "$path.$key".');
  }
  return json[key];
}

String _requireString(Map<String, Object?> json, String key, String path) {
  final value = _requireValue(json, key, path);
  if (value is! String) {
    throw FormatException('Expected "$path.$key" to be a string.');
  }
  return value;
}

int _requireInt(Map<String, Object?> json, String key, String path) {
  final value = _requireValue(json, key, path);
  if (value is! int) {
    throw FormatException('Expected "$path.$key" to be an integer.');
  }
  return value;
}

void _exactKeys(Map<String, Object?> json, Set<String> expected, String path) {
  for (final key in json.keys) {
    if (!expected.contains(key)) {
      throw FormatException('Unsupported field "$path.$key".');
    }
  }
  for (final key in expected) {
    if (!json.containsKey(key)) {
      throw FormatException('Missing required field "$path.$key".');
    }
  }
}

File _resolvePackageFile(Directory root, String relative, String label) {
  final safe = _requirePackagePath(relative, label);
  final file = File(p.join(root.path, safe));
  if (_relativePath(root, file) != safe) {
    throw FormatException('The generated $label escaped the package root.');
  }
  return file;
}

String _relativePath(Directory root, FileSystemEntity entity) {
  final relative = p.relative(
    p.normalize(entity.absolute.path),
    from: p.normalize(root.absolute.path),
  );
  return relative.split(p.separator).join('/');
}

Future<String> _readText(File file, String label) async {
  try {
    return await file.readAsString();
  } on FileSystemException catch (error) {
    throw PublicationManifestException(
      'The $label could not be read: ${error.message}. Re-run '
      '`dart run build_runner build` and retry.',
    );
  }
}

Future<String?> _readPackageName(Directory root) async {
  final pubspec = File(p.join(root.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  final source = await _readText(pubspec, 'pubspec.yaml');
  final Object? document;
  try {
    document = loadYaml(source);
  } on Object catch (error) {
    throw PublicationManifestException(
      'Could not parse pubspec.yaml while validating generated publication '
      'identity: $error.',
    );
  }
  final value = _mapValue(document, 'name');
  if (value == null) return null;
  if (value is! String) {
    throw const PublicationManifestException(
      'pubspec.yaml package name must be a string.',
    );
  }
  return _requireIdentity(value, 'pubspec.yaml.name');
}

bool _isExcludedDirectory(String name) => const {
  '.dart_tool',
  '.git',
  '.hg',
  '.svn',
  '.pub-cache',
  'build',
  'build-export',
  'build_export',
  'build-exports',
  'build_exports',
  'dependency',
  'dependencies',
  'node_modules',
  'vendor',
}.contains(name);

String _displayPaths(Directory root, List<FileSystemEntity> files) =>
    files.map((file) => _relativePath(root, file)).join(', ');

List<RestageOutputIndexEntry> _requireOrderedEntries(
  List<RestageOutputIndexEntry> entries,
) {
  String? previousPath;
  for (final entry in entries) {
    // Ascending UTF-8 path-byte order — the one ordering every artifact in
    // this family uses, so an index and the bundles it locates agree. A
    // repeated logical path is duplicate ownership and fails here too.
    if (previousPath != null &&
        compareGeneratedOutputPaths(previousPath, entry.path) >= 0) {
      throw const FormatException(
        'Generated output index entries must be sorted by logical path with '
        'no duplicate ownership.',
      );
    }
    previousPath = entry.path;
  }
  return List.unmodifiable(entries);
}
