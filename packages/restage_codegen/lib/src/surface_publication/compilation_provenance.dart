import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:crypto/crypto.dart';
import 'package:glob/glob.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/authored_library_predicate.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart';
import 'package:restage_codegen/src/surface_publication/output_location.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:yaml/yaml.dart';

const _toolchainPackages = {
  'restage',
  'restage_codegen',
  'restage_compiler_core',
  'restage_shared',
  'restage_core',
  'restage_material',
  'restage_cupertino',
  'restage_svg',
  'restage_measurement_schema',
  'rfw_catalog_schema',
  'rfw_catalog_compiler',
  'rfw',
  'flutter',
  'sky_engine',
};

/// Captures diagnostic inputs through BuildStep so edits invalidate the build.
Future<SurfaceCompilationProvenance?> collectCompilationProvenance(
  BuildStep step,
  Iterable<LibraryElement> roots, {
  Iterable<AssetId>? compilerAssets,
}) async {
  final app = SplayTreeMap<String, Object?>();
  final toolchain = SplayTreeMap<String, Object?>();
  final versions = SplayTreeMap<String, String>();
  final visited = <String>{};
  final assets = <AssetId>{};
  final packages = <String>{
    step.inputId.package,
    'restage_codegen',
    'restage_compiler_core',
    'rfw_catalog_compiler',
  };
  final pending = roots.toList();
  while (pending.isNotEmpty) {
    final library = pending.removeLast();
    if (!visited.add(library.identifier) || library.isInSdk) continue;
    for (final fragment in library.fragments) {
      final uri = fragment.source.uri;
      if (uri.scheme != 'package') return null;
      final asset = AssetId.resolve(uri);
      // Imported generated code is still an app input. Only Restage's own
      // neutral parts and reserved output directories are excluded here.
      if (asset.path.endsWith(kNeutralGeneratedPartSuffix) ||
          isReservedRestageGeneratedPath(asset.path)) {
        continue;
      }
      assets.add(asset);
      packages.add(asset.package);
    }
    for (final fragment in library.fragments) {
      for (final import in fragment.libraryImports) {
        if (import.importedLibrary case final library?) pending.add(library);
      }
      for (final export in fragment.libraryExports) {
        if (export.exportedLibrary case final library?) pending.add(library);
      }
    }
  }
  // Package-wide declarations can affect a screen through custom catalogs.
  await for (final asset in step.findAssets(Glob('lib/**.dart'))) {
    if (isAuthoredDartLibraryAsset(asset)) assets.add(asset);
  }
  for (final asset in assets) {
    if (!await step.canRead(asset)) return null;
    final inputs = _toolchainPackages.contains(asset.package) ? toolchain : app;
    inputs['${asset.package}/${asset.path}'] = (await step.digest(
      asset,
    )).toString();
  }
  final compilerPackages = <String>{};
  final pubspecs = <String, Map<Object?, Object?>>{};
  final pendingPackages = [
    'restage_codegen',
    'restage_compiler_core',
    'rfw_catalog_compiler',
  ];
  while (pendingPackages.isNotEmpty) {
    final package = pendingPackages.removeLast();
    if (!compilerPackages.add(package)) continue;
    final asset = AssetId(package, 'pubspec.yaml');
    if (!await step.canRead(asset)) return null;
    final document = loadYaml(await step.readAsString(asset));
    if (document is! Map<Object?, Object?>) return null;
    pubspecs[package] = document;
    if (document['dependencies']
        case final Map<Object?, Object?> dependencies) {
      pendingPackages.addAll(dependencies.keys.cast<String>());
    }
  }
  final resolvedCompilerAssets =
      compilerAssets ??
      await _compilerAssets({
        ...compilerPackages,
        ...packages.where(
          (package) =>
              _toolchainPackages.contains(package) &&
              package != 'flutter' &&
              package != 'sky_engine',
        ),
      });
  if (resolvedCompilerAssets == null) return null;
  for (final asset in resolvedCompilerAssets) {
    if (!await step.canRead(asset)) return null;
    toolchain['${asset.package}/${asset.path}'] = (await step.digest(
      asset,
    )).toString();
  }
  packages.addAll(compilerPackages);
  for (final package in packages) {
    final asset = AssetId(package, 'pubspec.yaml');
    if (!await step.canRead(asset)) return null;
    final pubspec =
        pubspecs[package] ?? loadYaml(await step.readAsString(asset));
    if (pubspec is! Map<Object?, Object?>) return null;
    if (_toolchainPackages.contains(package) ||
        compilerPackages.contains(package)) {
      final version = pubspec['version'];
      // Flutter itself has no package version; Dart identifies its SDK build.
      if (version is String && _toolchainPackages.contains(package)) {
        versions[package] = version;
      }
      toolchain['$package/pubspec.yaml'] = _canonical(pubspec);
    } else {
      app['$package/pubspec.yaml'] = _applicationPubspec(pubspec);
    }
  }
  final settings = AssetId(step.inputId.package, 'build.yaml');
  app['build.yaml'] = await step.canRead(settings)
      ? (await step.digest(settings)).toString()
      : null;
  versions['dart'] = Platform.version.split(' ').first;
  toolchain['dart'] = versions['dart'];
  return SurfaceCompilationProvenance(
    sourceHash: _hash(app),
    toolchainHash: _hash(toolchain),
    packageVersions: versions,
  );
}

// The build script is invalidated when its compiler dependencies change.
// Digest their assets through BuildStep too, retaining exact resolved inputs.
Future<List<AssetId>?> _compilerAssets(Set<String> packages) async {
  final configUri = await Isolate.packageConfig;
  if (configUri == null) return null;
  final config = await loadPackageConfigUri(configUri);
  final assets = <AssetId>[];
  for (final name in packages) {
    final package = config[name];
    if (package == null) return null;
    final directory = Directory.fromUri(package.packageUriRoot);
    if (!directory.existsSync()) continue;
    await for (final file in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (file is! File ||
          !(file.path.endsWith('.dart') ||
              file.path.endsWith('.json') ||
              file.path.endsWith('.yaml'))) {
        continue;
      }
      assets.add(
        AssetId(
          name,
          p.posix.joinAll(
            p.split(p.relative(file.path, from: package.root.toFilePath())),
          ),
        ),
      );
    }
  }
  return assets;
}

Object? _applicationPubspec(Map<Object?, Object?> pubspec) => _canonical({
  for (final entry in pubspec.entries)
    entry.key: switch (entry.key) {
      'dependencies' ||
      'dev_dependencies' ||
      'dependency_overrides' when entry.value is Map<Object?, Object?> => {
        for (final dependency
            in (entry.value! as Map<Object?, Object?>).entries)
          if (!_toolchainPackages.contains(dependency.key))
            dependency.key: dependency.value,
      },
      _ => entry.value,
    },
});

Object? _canonical(Object? value) => switch (value) {
  Map<Object?, Object?>() => SplayTreeMap<String, Object?>.from({
    for (final entry in value.entries)
      entry.key.toString(): _canonical(entry.value),
  }),
  List() => value.map(_canonical).toList(),
  _ => value,
};

String _hash(Object value) =>
    'sha256:${sha256.convert(utf8.encode(jsonEncode(value)))}';
