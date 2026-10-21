import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/loader_engine_base.dart';
import 'package:restage_cli/src/render_bundles/package_resolution.dart';
import 'package:restage_cli/src/render_bundles/render_bundle_archive.dart';
import 'package:restage_cli/src/render_bundles/render_bundle_project.dart';
import 'package:restage_shared/restage_shared.dart';

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

/// Why a render bundle build stopped. [code] is the stable name a message prints.
enum RenderBundleBuildFailure {
  projectIdentity('project_identity'),
  factoriesMissing('factories_missing'),
  outputRoot('output_root'),
  dependenciesUnresolved('dependencies_unresolved'),
  renderHostMissing('render_host_missing'),
  dependenciesFailed('dependencies_failed'),
  catalogContract('catalog_contract'),
  flutterNotFound('flutter_not_found'),
  flutterVersionUnavailable('flutter_version_unavailable'),
  fontAuthority('font_authority'),
  fontLicenseAuthority('font_license_authority'),
  privateTempPermissions('private_temp_permissions'),
  flutterBuildFailed('flutter_build_failed'),
  webOutputMissing('web_output_missing'),
  loaderContract('loader_contract'),
  serviceWorkerContract('service_worker_contract'),
  debugSymbolContract('debug_symbol_contract'),
  buildMetadataContract('build_metadata_contract'),
  engineMissing('engine_missing'),
  engineShape('engine_shape'),
  engineToolchain('engine_toolchain'),
  engineIncomplete('engine_incomplete'),
  nonDeterministicOutput('non_deterministic_output'),
  emptyOutput('empty_output'),
  fileAccess('file_access'),
  buildFailed('build_failed'),
  cleanupFailed('cleanup_failed');

  const RenderBundleBuildFailure(this.code);

  final String code;
}

/// Build failure that omits process output; [detail] names at most a path.
final class RenderBundleBuildException implements Exception {
  const RenderBundleBuildException(
    this.reason, {
    this.detail,
    this.buildDirectory,
  });

  final RenderBundleBuildFailure reason;

  /// What the reason is about, such as the engine path that did not match.
  final String? detail;

  /// The generated build project, relative to the app, once it was written.
  final String? buildDirectory;

  @override
  String toString() => detail == null
      ? 'RenderBundleBuildException(${reason.code})'
      : 'RenderBundleBuildException(${reason.code}, $detail)';
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

/// Where the engine files of [engineSetId] serve from.
Uri renderBundleEngineBase({
  required Uri controlOrigin,
  required String engineSetId,
}) => controlOrigin.resolve('/render-bundles/v1/engine/$engineSetId/');

/// One built bundle: the app's own files and the engine set it loads.
final class RenderBundleArtifact {
  const RenderBundleArtifact({required this.appFiles, required this.engineSet});

  /// The app's own files, by bundle-relative path.
  final Map<String, Uint8List> appFiles;

  /// The engine set the build's Flutter SDK produced.
  final RenderBundleEngineSet engineSet;

  /// The identifier the engine files serve under.
  String get engineSetId => engineSet.id;

  /// The Flutter version the bundle was built with.
  String get flutterVersion => engineSet.flutterVersion;
}

/// Injectable producer contract used by `restage build push`.
abstract interface class RenderBundleArtifactBuilder {
  Future<RenderBundleArtifact> build({
    required Directory projectRoot,
    required String catalogJson,
    required Uri parentOrigin,
    required Uri controlOrigin,
    String? flutterExecutable,
  });
}

/// Runs two isolated Flutter builds and returns their verified canonical bytes.
final class FlutterRenderBundleBuilder implements RenderBundleArtifactBuilder {
  FlutterRenderBundleBuilder({
    RenderBundleProcessRunner? processRunner,
    RenderBundleTempDirectoryCreator? tempDirectoryCreator,
    String? flutterExecutable,
    RenderBundleFontAuthority? fontAuthority,
    RenderBundleProjectWriter? projectWriter,
  }) : _processRunner = processRunner ?? runRenderBundleProcess,
       _tempDirectoryCreator =
           tempDirectoryCreator ?? Directory.systemTemp.createTemp,
       _flutterExecutableOverride = flutterExecutable,
       _fontAuthorityOverride = fontAuthority,
       _projectWriter = projectWriter ?? writeRenderBundleProject;

  final RenderBundleProcessRunner _processRunner;
  final RenderBundleTempDirectoryCreator _tempDirectoryCreator;
  final String? _flutterExecutableOverride;
  final RenderBundleFontAuthority? _fontAuthorityOverride;
  final RenderBundleProjectWriter _projectWriter;

  @override
  Future<RenderBundleArtifact> build({
    required Directory projectRoot,
    required String catalogJson,
    required Uri parentOrigin,
    required Uri controlOrigin,
    String? flutterExecutable,
  }) async {
    // Audit the merged catalog and the app's resolution before any private
    // temp directory or dart-define file exists.
    final Uint8List capabilityManifest;
    final appVersion = readProjectAppVersion(projectRoot);
    try {
      await PackageResolution.read(projectRoot);
      capabilityManifest = createRenderBundleCapabilityManifest(
        catalogJson,
        appVersion: appVersion.name,
        appBuild: appVersion.build,
      );
    } on Object {
      throw const RenderBundleBuildException(
        RenderBundleBuildFailure.catalogContract,
      );
    }
    final scratch = await _tempDirectoryCreator('restage_render_bundle_');
    String? projectPath;
    try {
      await _tightenPermissions(scratch.path, directory: true);
      final flutter =
          flutterExecutable ??
          _flutterExecutableOverride ??
          findFlutterExecutable();
      final flutterRoot = File(flutter).parent.parent;
      final fontAuthority =
          _fontAuthorityOverride ??
          RenderBundleFontAuthority.flutterSdk(flutterRoot);
      final fontBytes = await _readVerified(
        fontAuthority.fontFile,
        expectedHash: fontAuthority.fontSha256,
        expectedLength: fontAuthority.fontByteLength,
        reason: RenderBundleBuildFailure.fontAuthority,
      );
      final licenseBytes = await _readVerified(
        fontAuthority.licenseFile,
        expectedHash: fontAuthority.licenseSha256,
        reason: RenderBundleBuildFailure.fontLicenseAuthority,
      );
      final (:flutterVersion, :engineRevision) = await _readFlutterVersion(
        flutter,
      );
      final project = await _projectWriter(
        projectRoot: projectRoot,
        flutterVersion: flutterVersion,
        fontBytes: fontBytes,
        licenseBytes: licenseBytes,
      );
      projectPath = p.relative(project.path, from: projectRoot.path);
      if (!isRenderBundleProjectResolved(project, flutterRoot: flutterRoot)) {
        final resolved = await _processRunner(flutter, <String>[
          'pub',
          'get',
        ], workingDirectory: project.path);
        if (resolved.exitCode != 0) {
          throw const RenderBundleBuildException(
            RenderBundleBuildFailure.dependenciesFailed,
          );
        }
        await markRenderBundleProjectResolved(
          project,
          flutterRoot: flutterRoot,
        );
      }
      final artifacts = <RenderBundleArtifact>[];
      for (var pass = 1; pass <= 2; pass++) {
        final output = Directory(p.join(scratch.path, 'output_$pass'));
        final defineFile = File(
          p.join(scratch.path, 'private_build_config_$pass.json'),
        );
        await defineFile.writeAsString(
          jsonEncode(<String, String>{
            renderBundleParentOriginDefine: parentOrigin.toString(),
          }),
          flush: true,
        );
        await _tightenPermissions(defineFile.path, directory: false);
        final result = await _processRunner(flutter, <String>[
          'build',
          'web',
          '--release',
          '--wasm',
          '--csp',
          '--no-web-resources-cdn',
          '--pwa-strategy=none',
          '--no-tree-shake-icons',
          '--no-pub',
          '--target',
          renderBundleEntrypoint,
          '--output',
          output.path,
          '--dart-define-from-file=${defineFile.path}',
        ], workingDirectory: project.path);
        if (result.exitCode != 0) {
          throw const RenderBundleBuildException(
            RenderBundleBuildFailure.flutterBuildFailed,
          );
        }
        final engineSet = deriveRenderBundleEngineSet(
          await _collectEngineFiles(output),
          flutterVersion: flutterVersion,
          engineRevision: engineRevision,
        );
        await _prepareOutput(
          output,
          capabilityManifest: capabilityManifest,
          fontBytes: fontBytes,
          licenseBytes: licenseBytes,
          engineBase: renderBundleEngineBase(
            controlOrigin: controlOrigin,
            engineSetId: engineSet.id,
          ),
        );
        artifacts.add(
          splitRenderBundleEngineFiles(
            await collectRenderBundleDirectory(output),
            engineSet,
          ),
        );
      }
      if (!_sameArtifact(artifacts.first, artifacts.last)) {
        throw const RenderBundleBuildException(
          RenderBundleBuildFailure.nonDeterministicOutput,
        );
      }
      return artifacts.first;
    } on RenderBundleBuildException catch (error) {
      throw RenderBundleBuildException(
        error.reason,
        detail: error.detail,
        buildDirectory: projectPath,
      );
    } on FileSystemException catch (error) {
      throw RenderBundleBuildException(
        RenderBundleBuildFailure.fileAccess,
        detail: error.path,
        buildDirectory: projectPath,
      );
    } on Object catch (error) {
      throw RenderBundleBuildException(
        RenderBundleBuildFailure.buildFailed,
        detail: error.runtimeType.toString(),
        buildDirectory: projectPath,
      );
    } finally {
      try {
        if (scratch.existsSync()) await scratch.delete(recursive: true);
      } on Object {
        throw RenderBundleBuildException(
          RenderBundleBuildFailure.cleanupFailed,
          detail: scratch.path,
        );
      }
    }
  }

  /// The files the build wrote under the engine directory, by bundle path.
  Future<Map<String, Uint8List>> _collectEngineFiles(Directory output) async {
    final engine = Directory(p.join(output.path, renderBundleEnginePathPrefix));
    if (!engine.existsSync()) return const <String, Uint8List>{};
    return {
      for (final entry in (await collectRenderBundleDirectory(engine)).entries)
        '$renderBundleEnginePathPrefix${entry.key}': entry.value,
    };
  }

  Future<({String flutterVersion, String engineRevision})> _readFlutterVersion(
    String executable,
  ) async {
    final result = await _processRunner(executable, <String>[
      '--version',
      '--machine',
    ]);
    if (result.exitCode != 0) {
      throw const RenderBundleBuildException(
        RenderBundleBuildFailure.flutterVersionUnavailable,
      );
    }
    final Object? document;
    try {
      final output = result.stdout as String;
      document = jsonDecode(output.substring(output.indexOf('{')));
    } on Object {
      throw const RenderBundleBuildException(
        RenderBundleBuildFailure.flutterVersionUnavailable,
      );
    }
    if (document is! Map<String, dynamic> ||
        document['frameworkVersion'] is! String ||
        document['engineRevision'] is! String) {
      throw const RenderBundleBuildException(
        RenderBundleBuildFailure.flutterVersionUnavailable,
      );
    }
    return (
      flutterVersion: document['frameworkVersion'] as String,
      engineRevision: document['engineRevision'] as String,
    );
  }

  Future<void> _prepareOutput(
    Directory output, {
    required Uint8List capabilityManifest,
    required Uint8List fontBytes,
    required Uint8List licenseBytes,
    required Uri engineBase,
  }) async {
    final index = File(p.join(output.path, 'index.html'));
    final loader = File(p.join(output.path, 'flutter_bootstrap.js'));
    if (!index.existsSync() || !loader.existsSync()) {
      throw const RenderBundleBuildException(
        RenderBundleBuildFailure.webOutputMissing,
      );
    }
    final indexSource = await index.readAsString();
    final loaderSource = await loader.readAsString();
    // The build configuration names a skwasm build; the loader may still pick
    // the CanvasKit fallback on a browser without it.
    if (!RegExp(
          r'''['"]?renderer['"]?\s*:\s*['"]skwasm['"]''',
        ).hasMatch(loaderSource) ||
        !RegExp(
          r'''fontFallbackBaseUrl\s*:\s*['"]assets/fonts/fallback/['"]''',
        ).hasMatch(loaderSource)) {
      throw const RenderBundleBuildException(
        RenderBundleBuildFailure.loaderContract,
      );
    }
    await _omitExpectedCompatibilityServiceWorker(
      output,
      indexSource: indexSource,
      loaderSource: loaderSource,
    );
    // The engine files serve from their own origin, so the loader is pointed
    // there before anything reads the built output.
    await loader.writeAsString(
      withLoaderEngineBase(loaderSource, engineBase: engineBase),
      flush: true,
    );
    await _omitExpectedLastBuildId(output);
    await _omitExpectedDebugSymbols(output);
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
      throw const RenderBundleBuildException(
        RenderBundleBuildFailure.serviceWorkerContract,
      );
    }
    final bytes = await worker.readAsBytes();
    if (bytes.isNotEmpty) {
      throw const RenderBundleBuildException(
        RenderBundleBuildFailure.serviceWorkerContract,
      );
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
      throw const RenderBundleBuildException(
        RenderBundleBuildFailure.serviceWorkerContract,
      );
    }
    await worker.delete();
  }

  /// Removes the build's own symbol maps, which nothing fetches at runtime.
  ///
  /// Only these exact root outputs are dropped, so a bundled asset that
  /// happens to end in the same suffix still ships.
  Future<void> _omitExpectedDebugSymbols(Directory output) async {
    const names = <String>{'main.dart.js.symbols', 'main.dart.wasm.symbols'};
    for (final name in names) {
      final symbols = File(p.join(output.path, name));
      final type = await FileSystemEntity.type(
        symbols.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.file) {
        throw const RenderBundleBuildException(
          RenderBundleBuildFailure.debugSymbolContract,
        );
      }
      await symbols.delete();
    }
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
        throw const RenderBundleBuildException(
          RenderBundleBuildFailure.buildMetadataContract,
        );
      }
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file) {
        throw const RenderBundleBuildException(
          RenderBundleBuildFailure.buildMetadataContract,
        );
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
      throw const RenderBundleBuildException(
        RenderBundleBuildFailure.buildMetadataContract,
      );
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
      throw RenderBundleBuildException(
        RenderBundleBuildFailure.privateTempPermissions,
        detail: path,
      );
    }
  }
}

/// Runs one build-toolchain process without a shell.
Future<ProcessResult> runRenderBundleProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  runInShell: false,
);

/// Resolves the `flutter` executable from `PATH`.
String findFlutterExecutable() {
  final path = Platform.environment['PATH'];
  if (path != null) {
    for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
      if (directory.isEmpty) continue;
      final candidate = File(p.join(directory, 'flutter'));
      if (candidate.existsSync()) return candidate.resolveSymbolicLinksSync();
    }
  }
  throw const RenderBundleBuildException(
    RenderBundleBuildFailure.flutterNotFound,
  );
}

Future<Uint8List> _readVerified(
  File file, {
  required String expectedHash,
  required RenderBundleBuildFailure reason,
  int? expectedLength,
}) async {
  if (!file.existsSync()) {
    throw RenderBundleBuildException(reason, detail: file.path);
  }
  final bytes = await file.readAsBytes();
  if ((expectedLength != null && bytes.length != expectedLength) ||
      crypto.sha256.convert(bytes).toString() != expectedHash) {
    throw RenderBundleBuildException(reason, detail: file.path);
  }
  return bytes;
}

/// The engine set a build output holds, as the SDK at [flutterVersion] made it.
///
/// The set is every file under the engine directory except its symbol maps.
RenderBundleEngineSet deriveRenderBundleEngineSet(
  Map<String, Uint8List> files, {
  required String flutterVersion,
  required String engineRevision,
}) {
  final engineFiles = <String, Uint8List>{
    for (final entry in files.entries)
      if (entry.key.startsWith(renderBundleEnginePathPrefix) &&
          !entry.key.endsWith('.symbols'))
        entry.key.substring(renderBundleEnginePathPrefix.length): entry.value,
  };
  if (engineFiles.isEmpty) {
    throw const RenderBundleBuildException(
      RenderBundleBuildFailure.engineMissing,
    );
  }
  try {
    return RenderBundleEngineSet.fromFiles(
      flutterVersion: flutterVersion,
      engineRevision: engineRevision,
      files: engineFiles,
    );
  } on FormatException {
    throw const RenderBundleBuildException(
      RenderBundleBuildFailure.engineShape,
    );
  }
}

/// Takes the engine out of the app's files and checks it against the set.
///
/// The engine serves from its own origin, so its files leave the bundle and
/// the symbol maps beside them are dropped. The set is exact in both
/// directions.
RenderBundleArtifact splitRenderBundleEngineFiles(
  Map<String, Uint8List> files,
  RenderBundleEngineSet engineSet,
) {
  final appFiles = <String, Uint8List>{};
  final engineFiles = <String, Uint8List>{};
  for (final entry in files.entries) {
    if (!entry.key.startsWith(renderBundleEnginePathPrefix)) {
      appFiles[entry.key] = entry.value;
      continue;
    }
    final path = entry.key.substring(renderBundleEnginePathPrefix.length);
    if (path.endsWith('.symbols')) continue;
    final hash = 'sha256:${crypto.sha256.convert(entry.value)}';
    if (!engineSet.holds(path: path, contentHash: hash)) {
      throw RenderBundleBuildException(
        RenderBundleBuildFailure.engineToolchain,
        detail: path,
      );
    }
    engineFiles[path] = entry.value;
  }
  for (final file in engineSet.files) {
    if (!engineFiles.containsKey(file.path)) {
      throw RenderBundleBuildException(
        RenderBundleBuildFailure.engineIncomplete,
        detail: file.path,
      );
    }
  }
  return RenderBundleArtifact(appFiles: appFiles, engineSet: engineSet);
}

bool _sameArtifact(RenderBundleArtifact left, RenderBundleArtifact right) =>
    left.engineSetId == right.engineSetId &&
    _sameFiles(left.appFiles, right.appFiles);

bool _sameFiles(Map<String, Uint8List> left, Map<String, Uint8List> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    final other = right[entry.key];
    if (other == null || !_sameBytes(entry.value, other)) return false;
  }
  return true;
}

bool _sameBytes(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
