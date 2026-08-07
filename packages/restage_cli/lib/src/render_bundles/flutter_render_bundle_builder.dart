import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/render_bundle_archive.dart';
import 'package:restage_shared/restage_shared.dart';
// ignore: implementation_imports
import 'package:restage_shared/src/render_bundle/deployed_origin_authority.dart';
import 'package:yaml/yaml.dart';

const _requiredFlutterVersion = '3.44.8';
const _robotoFontSha256 =
    '79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95';
const _robotoLicenseSha256 =
    'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30';
const _robotoFontByteLength = 171676;
final _activeServiceWorkerPattern = RegExp(
  r'service[\s_-]*worker',
  caseSensitive: false,
);

typedef RenderBundleProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

typedef RenderBundleTempDirectoryCreator =
    Future<Directory> Function(String prefix);

typedef RenderBundleCatalogResolver =
    Future<String> Function(Directory projectRoot, String customerCatalogJson);

/// Generic build failure that deliberately omits process output and paths.
final class RenderBundleBuildException implements Exception {
  const RenderBundleBuildException(this.reason);

  final String reason;

  @override
  String toString() => 'RenderBundleBuildException($reason)';
}

/// Verified SDK-owned font inputs copied into each isolated output.
final class RenderBundleFontAuthority {
  const RenderBundleFontAuthority({
    required this.fontFile,
    required this.licenseFile,
    required this.fontSha256,
    required this.licenseSha256,
    this.fontByteLength,
  });

  factory RenderBundleFontAuthority.flutterSdk(Directory flutterRoot) {
    final materialFonts = Directory(
      p.join(flutterRoot.path, 'bin', 'cache', 'artifacts', 'material_fonts'),
    );
    return RenderBundleFontAuthority(
      fontFile: File(p.join(materialFonts.path, 'Roboto-Regular.ttf')),
      licenseFile: File(p.join(materialFonts.path, 'Roboto_LICENSE.txt')),
      fontSha256: _robotoFontSha256,
      licenseSha256: _robotoLicenseSha256,
      fontByteLength: _robotoFontByteLength,
    );
  }

  final File fontFile;
  final File licenseFile;
  final String fontSha256;
  final String licenseSha256;
  final int? fontByteLength;
}

/// Injectable producer contract used by `restage build push`.
abstract interface class RenderBundleArtifactBuilder {
  Future<Uint8List> build({
    required Directory projectRoot,
    required String catalogJson,
    required Uri parentOrigin,
  });
}

/// Runs two isolated Flutter builds and returns their verified canonical bytes.
final class FlutterRenderBundleBuilder implements RenderBundleArtifactBuilder {
  FlutterRenderBundleBuilder({
    RenderBundleProcessRunner? processRunner,
    RenderBundleTempDirectoryCreator? tempDirectoryCreator,
    RenderBundleCatalogResolver? catalogResolver,
    String? flutterExecutable,
    RenderBundleFontAuthority? fontAuthority,
  }) : _processRunner = processRunner ?? _runProcess,
       _tempDirectoryCreator =
           tempDirectoryCreator ?? Directory.systemTemp.createTemp,
       _catalogResolver =
           catalogResolver ?? createRenderBundleCapabilityCatalogUnion,
       _flutterExecutableOverride = flutterExecutable,
       _fontAuthorityOverride = fontAuthority;

  final RenderBundleProcessRunner _processRunner;
  final RenderBundleTempDirectoryCreator _tempDirectoryCreator;
  final RenderBundleCatalogResolver _catalogResolver;
  final String? _flutterExecutableOverride;
  final RenderBundleFontAuthority? _fontAuthorityOverride;

  @override
  Future<Uint8List> build({
    required Directory projectRoot,
    required String catalogJson,
    required Uri parentOrigin,
  }) async {
    final entrypoint = File(
      p.join(projectRoot.path, 'lib', 'main_render_bundle.dart'),
    );
    if (!entrypoint.existsSync()) {
      throw const RenderBundleBuildException('entrypoint_missing');
    }
    _validateParentOrigin(parentOrigin);
    // Resolve the exact built-in + customer capability union, then recursively
    // audit it before any private temp directory or dart-define file exists.
    final String capabilityCatalogJson;
    final Uint8List capabilityManifest;
    try {
      capabilityCatalogJson = await _catalogResolver(projectRoot, catalogJson);
      capabilityManifest = createRenderBundleCapabilityManifest(
        capabilityCatalogJson,
      );
    } on Object {
      throw const RenderBundleBuildException('catalog_contract');
    }
    final scratch = await _tempDirectoryCreator('restage_render_bundle_');
    try {
      await _tightenPermissions(scratch.path, directory: true);
      final flutterExecutable =
          _flutterExecutableOverride ?? _findFlutterExecutable();
      final flutterRoot = File(flutterExecutable).parent.parent;
      final fontAuthority =
          _fontAuthorityOverride ??
          RenderBundleFontAuthority.flutterSdk(flutterRoot);
      final fontBytes = await _readVerified(
        fontAuthority.fontFile,
        expectedHash: fontAuthority.fontSha256,
        expectedLength: fontAuthority.fontByteLength,
        reason: 'font_authority',
      );
      final licenseBytes = await _readVerified(
        fontAuthority.licenseFile,
        expectedHash: fontAuthority.licenseSha256,
        reason: 'font_license_authority',
      );
      await _verifyFlutterVersion(flutterExecutable);

      final archives = <Uint8List>[];
      for (var pass = 1; pass <= 2; pass++) {
        final output = Directory(p.join(scratch.path, 'output_$pass'));
        final defineFile = File(
          p.join(scratch.path, 'private_build_config_$pass.json'),
        );
        await defineFile.writeAsString(
          jsonEncode(<String, String>{
            'RESTAGE_RENDER_BUNDLE_PARENT_ORIGIN': parentOrigin.toString(),
          }),
          flush: true,
        );
        await _tightenPermissions(defineFile.path, directory: false);
        final result = await _processRunner(flutterExecutable, <String>[
          'build',
          'web',
          '--release',
          '--wasm',
          '--csp',
          '--no-web-resources-cdn',
          '--pwa-strategy=none',
          '--no-tree-shake-icons',
          '--target',
          'lib/main_render_bundle.dart',
          '--output',
          output.path,
          '--dart-define-from-file=${defineFile.path}',
        ], workingDirectory: projectRoot.path);
        if (result.exitCode != 0) {
          throw const RenderBundleBuildException('flutter_build_failed');
        }
        await _prepareOutput(
          output,
          capabilityManifest: capabilityManifest,
          fontBytes: fontBytes,
          licenseBytes: licenseBytes,
        );
        archives.add(await encodeRenderBundleDirectory(output));
      }
      if (!_sameBytes(archives.first, archives.last)) {
        throw const RenderBundleBuildException('non_deterministic_output');
      }
      return archives.first;
    } on RenderBundleBuildException {
      rethrow;
    } on Object {
      throw const RenderBundleBuildException('build_failed');
    } finally {
      try {
        if (scratch.existsSync()) await scratch.delete(recursive: true);
      } on Object {
        throw const RenderBundleBuildException('cleanup_failed');
      }
    }
  }

  Future<void> _verifyFlutterVersion(String executable) async {
    final result = await _processRunner(executable, <String>[
      '--version',
      '--machine',
    ]);
    if (result.exitCode != 0) {
      throw const RenderBundleBuildException('flutter_version_unavailable');
    }
    final Object? document;
    try {
      document = jsonDecode(result.stdout as String);
    } on Object {
      throw const RenderBundleBuildException('flutter_version_unavailable');
    }
    if (document is! Map<String, dynamic> ||
        document['frameworkVersion'] != _requiredFlutterVersion) {
      throw const RenderBundleBuildException('flutter_version_mismatch');
    }
  }

  Future<void> _prepareOutput(
    Directory output, {
    required Uint8List capabilityManifest,
    required Uint8List fontBytes,
    required Uint8List licenseBytes,
  }) async {
    final index = File(p.join(output.path, 'index.html'));
    final loader = File(p.join(output.path, 'flutter_bootstrap.js'));
    if (!index.existsSync() || !loader.existsSync()) {
      throw const RenderBundleBuildException('web_output_missing');
    }
    final indexSource = await index.readAsString();
    final loaderSource = await loader.readAsString();
    if (!RegExp(r'''renderer\s*:\s*['"]skwasm['"]''').hasMatch(loaderSource) ||
        !RegExp(
          r'''fontFallbackBaseUrl\s*:\s*['"]assets/fonts/fallback/['"]''',
        ).hasMatch(loaderSource)) {
      throw const RenderBundleBuildException('loader_contract');
    }
    await _omitExpectedCompatibilityServiceWorker(
      output,
      indexSource: indexSource,
      loaderSource: loaderSource,
    );
    await _omitExpectedLastBuildId(output);
    final fonts = Directory(p.join(output.path, 'assets', 'fonts', 'fallback'));
    await fonts.create(recursive: true);
    await File(
      p.join(fonts.path, 'Roboto-Regular.ttf'),
    ).writeAsBytes(fontBytes, flush: true);
    await File(
      p.join(fonts.path, 'Roboto_LICENSE.txt'),
    ).writeAsBytes(licenseBytes, flush: true);
    await File(
      p.join(output.path, renderBundleCapabilityManifestPath),
    ).writeAsBytes(capabilityManifest, flush: true);
  }

  Future<void> _omitExpectedCompatibilityServiceWorker(
    Directory output, {
    required String indexSource,
    required String loaderSource,
  }) async {
    final worker = File(p.join(output.path, 'flutter_service_worker.js'));
    final type = await FileSystemEntity.type(worker.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.file) {
      throw const RenderBundleBuildException('service_worker_contract');
    }
    final bytes = await worker.readAsBytes();
    if (bytes.isNotEmpty) {
      throw const RenderBundleBuildException('service_worker_contract');
    }

    const buildConfigMarker = '_flutter.buildConfig = ';
    final configStart = loaderSource.lastIndexOf(buildConfigMarker);
    final configEnd = configStart < 0
        ? -1
        : loaderSource.indexOf(';\n', configStart + buildConfigMarker.length);
    if (configEnd < 0 ||
        _activeServiceWorkerPattern.hasMatch(
          loaderSource.substring(configEnd + 2),
        ) ||
        _activeServiceWorkerPattern.hasMatch(indexSource)) {
      throw const RenderBundleBuildException('service_worker_contract');
    }
    await worker.delete();
  }

  Future<void> _omitExpectedLastBuildId(Directory output) async {
    File? metadata;
    await for (final entity in output.list(
      recursive: true,
      followLinks: false,
    )) {
      if (p.basename(entity.path).toLowerCase() != '.last_build_id') continue;
      final relative = p.relative(entity.path, from: output.path);
      if (relative != '.last_build_id' || metadata != null) {
        throw const RenderBundleBuildException('build_metadata_contract');
      }
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file) {
        throw const RenderBundleBuildException('build_metadata_contract');
      }
      metadata = File(entity.path);
    }
    if (metadata == null) return;

    final bytes = await metadata.readAsBytes();
    if (bytes.length != 32 ||
        bytes.any(
          (byte) =>
              (byte < 0x30 || byte > 0x39) && (byte < 0x61 || byte > 0x66),
        )) {
      throw const RenderBundleBuildException('build_metadata_contract');
    }
    await metadata.delete();
  }

  Future<void> _tightenPermissions(
    String path, {
    required bool directory,
  }) async {
    if (Platform.isWindows) return;
    final executable = File('/bin/chmod').existsSync()
        ? '/bin/chmod'
        : '/usr/bin/chmod';
    final result = await _processRunner(executable, <String>[
      directory ? '700' : '600',
      path,
    ]);
    if (result.exitCode != 0) {
      throw const RenderBundleBuildException('private_temp_permissions');
    }
  }
}

/// Builds the canonical bundle-level capability union.
///
/// The three runtime built-in catalogs are resolved from the customer's exact
/// package configuration. Their complete graph is merged with the generated
/// customer catalog so ready-manifest admission proves the same constructors
/// the built bundle can actually render.
Future<String> createRenderBundleCapabilityCatalogUnion(
  Directory projectRoot,
  String customerCatalogJson,
) async {
  final packageConfig = await _loadProjectPackageConfig(projectRoot);
  final catalogs = <Catalog>[];
  for (final package in const <String>[
    'restage_core',
    'restage_material',
    'restage_cupertino',
  ]) {
    final uri = packageConfig.resolve(
      Uri.parse('package:$package/src/widget_catalog/catalog.json'),
    );
    if (uri == null || !uri.isScheme('file')) {
      throw StateError('built-in catalog unavailable');
    }
    final file = File.fromUri(uri);
    if (!file.existsSync()) {
      throw StateError('built-in catalog unavailable');
    }
    catalogs.add(decodeCatalog(await file.readAsString()));
  }
  catalogs.add(decodeCatalog(customerCatalogJson));
  return encodeCatalog(_mergeCapabilityCatalogs(catalogs));
}

Future<PackageConfig> _loadProjectPackageConfig(Directory projectRoot) async {
  final canonicalProjectPath = _resolveDirectory(projectRoot);
  final canonicalProject = Directory(canonicalProjectPath);
  final localConfig = File(
    p.join(canonicalProjectPath, '.dart_tool', 'package_config.json'),
  );
  final localType = FileSystemEntity.typeSync(
    localConfig.path,
    followLinks: false,
  );
  if (localType == FileSystemEntityType.file) {
    final canonicalConfigPath = localConfig.resolveSymbolicLinksSync();
    if (!p.equals(
      canonicalConfigPath,
      p.normalize(localConfig.absolute.path),
    )) {
      throw StateError('package configuration identity mismatch');
    }
    final packageConfig = await findPackageConfig(
      canonicalProject,
      recurse: false,
      minVersion: 2,
    );
    if (packageConfig == null) {
      throw StateError('package configuration unavailable');
    }
    return packageConfig;
  }
  if (localType != FileSystemEntityType.notFound) {
    throw StateError('package configuration unavailable');
  }

  final packageConfig = await findPackageConfig(
    canonicalProject,
    minVersion: 2,
  );
  if (packageConfig == null) {
    throw StateError('package configuration unavailable');
  }
  final projectName = _readProjectPackageName(canonicalProject);
  final projectPackage = packageConfig[projectName];
  if (projectPackage == null ||
      !projectPackage.root.isScheme('file') ||
      !p.equals(
        _resolveDirectory(Directory.fromUri(projectPackage.root)),
        canonicalProjectPath,
      )) {
    throw StateError('package configuration identity mismatch');
  }
  return packageConfig;
}

String _resolveDirectory(Directory directory) {
  try {
    return p.normalize(directory.resolveSymbolicLinksSync());
  } on FileSystemException {
    throw StateError('package configuration identity unavailable');
  }
}

String _readProjectPackageName(Directory projectRoot) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  if (FileSystemEntity.typeSync(pubspec.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError('project package identity unavailable');
  }
  final Object? document;
  try {
    document = loadYaml(pubspec.readAsStringSync());
  } on Object {
    throw StateError('project package identity unavailable');
  }
  if (document is! YamlMap ||
      document['name'] is! String ||
      !RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(document['name']! as String)) {
    throw StateError('project package identity unavailable');
  }
  return document['name']! as String;
}

Catalog _mergeCapabilityCatalogs(List<Catalog> catalogs) {
  if (catalogs.isEmpty) {
    throw StateError('capability catalog union is empty');
  }
  final libraries = <WidgetLibrary, LibraryInfo>{};
  final widgetIdentities = <String>{};
  final widgets = <WidgetEntry>[];
  final compatRules = <CompatRule>[];
  var sawCompatRules = false;
  String? flutterVersion;
  for (final catalog in catalogs) {
    if (catalog.schemaVersion != kSupportedSchemaVersion) {
      throw StateError('capability catalog schema mismatch');
    }
    final sourceFlutterVersion = catalog.flutterVersion;
    if (sourceFlutterVersion != null) {
      if (flutterVersion != null && flutterVersion != sourceFlutterVersion) {
        throw StateError('capability catalog Flutter version mismatch');
      }
      flutterVersion = sourceFlutterVersion;
    }
    for (final entry in catalog.libraries.entries) {
      if (libraries.containsKey(entry.key)) {
        throw StateError('duplicate capability library');
      }
      libraries[entry.key] = entry.value;
    }
    for (final widget in catalog.widgets) {
      final identity = '${widget.library.namespace}\u0000${widget.name}';
      if (!widgetIdentities.add(identity)) {
        throw StateError('duplicate capability widget');
      }
      widgets.add(widget);
    }
    final rules = catalog.compatRules;
    if (rules != null) {
      sawCompatRules = true;
      compatRules.addAll(rules);
    }
  }
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: catalogs.last.generatedAt,
    libraries: libraries,
    widgets: widgets,
    structuredTypes: <StructuredEntry>[
      for (final catalog in catalogs) ...catalog.structuredTypes,
    ],
    unions: <UnionEntry>[for (final catalog in catalogs) ...catalog.unions],
    designTokens: <DesignTokenEntry>[
      for (final catalog in catalogs) ...catalog.designTokens,
    ],
    flutterVersion: flutterVersion,
    compatRules: sawCompatRules ? compatRules : null,
  );
}

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  runInShell: false,
);

String _findFlutterExecutable() {
  final path = Platform.environment['PATH'];
  if (path != null) {
    for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
      if (directory.isEmpty) continue;
      final candidate = File(p.join(directory, 'flutter'));
      if (candidate.existsSync()) return candidate.resolveSymbolicLinksSync();
    }
  }
  throw const RenderBundleBuildException('flutter_not_found');
}

Future<Uint8List> _readVerified(
  File file, {
  required String expectedHash,
  required String reason,
  int? expectedLength,
}) async {
  if (!file.existsSync()) throw RenderBundleBuildException(reason);
  final bytes = await file.readAsBytes();
  if ((expectedLength != null && bytes.length != expectedLength) ||
      crypto.sha256.convert(bytes).toString() != expectedHash) {
    throw RenderBundleBuildException(reason);
  }
  return bytes;
}

void _validateParentOrigin(Uri origin) {
  if (!isApprovedRenderBundleParentOrigin(origin)) {
    throw const RenderBundleBuildException('parent_origin');
  }
}

bool _sameBytes(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
