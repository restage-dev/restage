import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/analytics_id_control.dart';
import 'package:restage_codegen/src/durable_state.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/legacy_output_validation.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_shared/restage_shared.dart';

/// Removes recognized obsolete artifacts after their replacement is emitted.
Future<void> cleanLegacyRestageOutputs(
  String package,
  RestageOutputPlacementPlan plan,
) async {
  final root = await restagePackageRoot(package);
  if (root == null) {
    return;
  }
  cleanLegacyRestageOutputsInDirectory(Directory.fromUri(root), package, plan);
}

/// Removes only validated generated files; authored files and directories stay.
void cleanLegacyRestageOutputsInDirectory(
  Directory root,
  String package,
  RestageOutputPlacementPlan plan,
) {
  const indexPath = 'lib/generated/restage.outputs.json';
  const manifestPath = 'lib/generated/restage.publication.json';
  final indexFile = _regularFile(root, indexPath);
  final manifestFile = _regularFile(root, manifestPath);
  if (indexFile != null &&
      manifestFile != null &&
      plan.outputIndexPath != indexPath &&
      plan.publicationManifestPath != manifestPath) {
    try {
      final index =
          jsonDecode(indexFile.readAsStringSync()) as Map<String, Object?>;
      final manifestBytes = manifestFile.readAsBytesSync();
      if (isRecognizedLegacyOutputIndex(index, package) &&
          index['publicationManifestPath'] == manifestPath &&
          index['generationFingerprint'] ==
              'sha256:${crypto.sha256.convert(manifestBytes)}') {
        SurfacePublicationManifestV1Codec.decodeJson(
          utf8.decode(manifestBytes),
        );
        for (final entry in index['entries']! as List<Object?>) {
          final path = (entry! as Map<String, Object?>)['bundle'];
          if (path is! String ||
              !path.startsWith('lib/') ||
              !path.endsWith('.rsbundle')) {
            continue;
          }
          final file = _regularFile(root, path);
          if (file == null) {
            continue;
          }
          try {
            final bundle = RestageBundleCodec.decode(file.readAsBytesSync());
            if (bundle.packageName == package &&
                plan.forLibrary(bundle.authoredLibraryPath).bundlePath !=
                    path) {
              file.deleteSync();
            }
          } on Object {
            // An unrecognized file is not ours to remove.
          }
        }
        indexFile.deleteSync();
        manifestFile.deleteSync();
      }
    } on Object {
      // Keep unrecognized or edited output for the author to reconcile.
    }
  }

  for (final path in [
    'assets/restage/source-index.json',
    'assets/restage/output-roster.json',
    'lib/generated/restage.measurement.index.json',
    'lib/generated/restage.analytics-id.metadata.json',
    kRestageAnalyticsIdControlOutputPath,
  ]) {
    final file = _regularFile(root, path);
    if (file == null) {
      continue;
    }
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      if (isRecognizedLegacyMetadata(path, json, package)) {
        file.deleteSync();
      }
    } on Object {
      // Preserve authored files that share a former generated filename.
    }
  }
  final compiler =
      _regularFile(root, kRestageSurfacePublicationCompilerBundlePath);
  if (compiler != null) {
    try {
      RestageSurfacePublicationBundle.fromJson(
        jsonDecode(compiler.readAsStringSync()),
      );
      compiler.deleteSync();
    } on Object {
      // Preserve unrecognized content.
    }
  }
  final measurement = _regularFile(root, kRestageMeasurementCompilerOutputPath);
  if (measurement != null) {
    try {
      RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        measurement.readAsBytesSync(),
      );
      measurement.deleteSync();
    } on Object {
      // Preserve unrecognized content.
    }
  }
}

final _generatedCustomCatalogs = Resource<Map<String, List<int>>>(
  () => <String, List<int>>{},
);

/// Records the catalog emitted by its annotation-based owner in this build.
Future<void> recordGeneratedCustomCatalog(
  BuildStep buildStep,
  List<int> bytes,
) async {
  final generated = await buildStep.fetchResource(_generatedCustomCatalogs);
  generated[buildStep.inputId.package] = bytes;
}

/// Retires a previous generated catalog or report only if its bytes match.
Future<void> removeIdenticalLegacyOutput(
  BuildStep buildStep,
  String path,
  List<int> replacement,
) async {
  final package = buildStep.inputId.package;
  final generated = await buildStep.fetchResource(_generatedCustomCatalogs);
  final emitted = generated[package];
  if (emitted == null ||
      emitted.length != replacement.length ||
      !emitted.indexed.every((entry) => replacement[entry.$1] == entry.$2)) {
    return;
  }
  final uri = await restagePackageRoot(package);
  if (uri == null) {
    return;
  }
  final file = _regularFile(Directory.fromUri(uri), path);
  if (file == null) {
    return;
  }
  final existing = file.readAsBytesSync();
  if (existing.length == replacement.length &&
      existing.indexed.every((entry) => replacement[entry.$1] == entry.$2)) {
    file.deleteSync();
  }
}

File? _regularFile(Directory root, String relative) {
  final parts = p.posix.split(relative);
  if (p.posix.isAbsolute(relative) ||
      parts.any((part) => part == '..' || part == '.')) {
    return null;
  }
  var current = root.path;
  for (final part in parts) {
    current = p.join(current, part);
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.link ||
        type == FileSystemEntityType.notFound) {
      return null;
    }
  }
  final file = File(current);
  return file.existsSync() ? file : null;
}
