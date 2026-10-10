import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:package_config/package_config.dart';
import 'package:yaml/yaml.dart';

/// Resolves the package directory from the active package configuration.
Future<Uri?> restagePackageRoot(String package) async {
  final configUri = await Isolate.packageConfig;
  if (configUri == null) {
    return null;
  }
  final config = await loadPackageConfigUri(configUri);
  final root = config[package]?.root;
  return root != null && root.isScheme('file') ? root : null;
}

/// Reads tracked state when admitted by the target, otherwise reads it on disk.
Future<List<int>?> readDurableRestageState(
  BuildStep buildStep, {
  required String path,
  required String legacyPath,
}) async {
  final package = buildStep.inputId.package;
  final root = await restagePackageRoot(package);
  Future<List<int>?> read(String relative) async {
    final asset = AssetId(package, relative);
    if (await buildStep.canRead(asset)) {
      return buildStep.readAsBytes(asset);
    }
    if (root == null) {
      return null;
    }
    final file = File.fromUri(root.resolve(relative));
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  final current = await read(path);
  final legacy = await read(legacyPath);
  _requireAgreement(current, legacy, path: path, legacyPath: legacyPath);
  return current ?? legacy;
}

/// Moves legacy state only after validation, preserving its exact bytes.
File migrateDurableRestageState({
  required Directory root,
  required String path,
  required String legacyPath,
}) {
  final current = File.fromUri(root.uri.resolve(path));
  final legacy = File.fromUri(root.uri.resolve(legacyPath));
  final currentBytes = current.existsSync() ? current.readAsBytesSync() : null;
  final legacyBytes = legacy.existsSync() ? legacy.readAsBytesSync() : null;
  _requireAgreement(
    currentBytes,
    legacyBytes,
    path: path,
    legacyPath: legacyPath,
  );
  if (legacyBytes != null) {
    if (currentBytes == null) {
      current.parent.createSync(recursive: true);
      legacy.renameSync(current.path);
    } else {
      legacy.deleteSync();
    }
  }
  return current;
}

void _requireAgreement(
  List<int>? current,
  List<int>? legacy, {
  required String path,
  required String legacyPath,
}) {
  if (current == null || legacy == null) {
    return;
  }
  if (current.length == legacy.length &&
      current.indexed.every((entry) => legacy[entry.$1] == entry.$2)) {
    return;
  }
  throw StateError(
    'Conflicting Restage identity state at $path and $legacyPath. '
    'Reconcile these files to the same state, then rerun generation. '
    'Neither file was overwritten.',
  );
}

/// The build.yaml line that makes edits to the durable state trigger a rebuild.
const String kUntrackedDurableStateAdvice =
    'Add `additional_public_assets: [.restage/measurement-state.json, '
    '.restage/wire-ids.events.jsonl]` to build.yaml so edits to these files '
    'trigger a rebuild.';

/// The [paths] that exist on disk under [packageRoot] but are not build
/// inputs, so an edit to them does not invalidate a cached build.
Future<List<String>> untrackedDurableRestageState({
  required String package,
  required Future<bool> Function(AssetId asset) canRead,
  required Uri? packageRoot,
  required Iterable<String> paths,
}) async {
  if (packageRoot == null) return const [];
  final admitted = _buildYamlSourceGlobs(packageRoot);
  return [
    for (final path in paths)
      // A file this build wrote is not an input yet; build.yaml decides.
      if (File.fromUri(packageRoot.resolve(path)).existsSync() &&
          !admitted.any((glob) => glob.matches(path)) &&
          !await canRead(AssetId(package, path)))
        path,
  ];
}

// The paths the package's build.yaml admits as build inputs.
List<Glob> _buildYamlSourceGlobs(Uri packageRoot) {
  final file = File.fromUri(packageRoot.resolve('build.yaml'));
  if (!file.existsSync()) return const [];
  final Object? document;
  try {
    document = loadYaml(file.readAsStringSync());
  } on YamlException {
    return const [];
  }
  if (document is! YamlMap) return const [];
  final patterns = <Object?>[
    ...?(document['additional_public_assets'] as YamlList?),
  ];
  final targets = document['targets'];
  if (targets is YamlMap) {
    for (final target in targets.values) {
      if (target is! YamlMap) continue;
      final sources = target['sources'];
      patterns.addAll(switch (sources) {
        YamlList() => sources,
        YamlMap() => (sources['include'] as YamlList?) ?? const <Object?>[],
        _ => const <Object?>[],
      });
    }
  }
  return [
    for (final pattern in patterns)
      if (pattern is String) Glob(pattern),
  ];
}

/// [message] with the build.yaml advice appended when the state it asks the
/// author to edit is untracked.
String withUntrackedStateAdvice(String message, {required bool untracked}) =>
    untracked && message.endsWith('Then rebuild.')
        ? '$message $kUntrackedDurableStateAdvice'
        : message;
