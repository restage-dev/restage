import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:package_config/package_config.dart';

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
