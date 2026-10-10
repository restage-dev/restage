import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/package_resolution.dart';
import 'package:restage_shared/restage_shared.dart';

/// The fixed stamp every generated catalog carries, so identical sources
/// encode to identical bytes.
const _generatedAt = '1970-01-01T00:00:00Z';

/// The generator's command, as an app author would run it.
const generatedWidgetCatalogCommand = <String>['run', 'build_runner', 'build'];

/// A generated-catalog step that could not complete.
final class GeneratedCatalogException implements Exception {
  const GeneratedCatalogException(this.reason);

  final String reason;

  @override
  String toString() => 'GeneratedCatalogException($reason)';
}

/// One app's generated widget catalog.
final class GeneratedWidgetCatalog {
  const GeneratedWidgetCatalog({
    required this.json,
    required this.registersWidgets,
  });

  /// The catalog the bundle is built against.
  final String json;

  /// Whether the app registers any widget of its own.
  final bool registersWidgets;
}

/// Produces or reads one app's generated widget catalog.
typedef RenderBundleCatalogProducer =
    Future<GeneratedWidgetCatalog> Function({
      required Directory projectRoot,
      required bool generate,
      String? flutterExecutable,
    });

/// Where the generator writes [packageName]'s catalog.
String generatedWidgetCatalogPath(Directory projectRoot, String packageName) =>
    p.join(
      projectRoot.path,
      '.dart_tool',
      'build',
      'generated',
      packageName,
      'lib',
      'src',
      'widget_catalog',
      'catalog.json',
    );

/// Runs the generator, then reads what it wrote.
///
/// An app that registers no widget of its own has no generated catalog and
/// builds against an empty custom library. With [generate] false the catalog a
/// previous run produced is required.
Future<GeneratedWidgetCatalog> readGeneratedWidgetCatalog({
  required Directory projectRoot,
  required bool generate,
  String? flutterExecutable,
  RenderBundleProcessRunner? processRunner,
  String? dartExecutable,
}) async {
  final String packageName;
  try {
    packageName = readProjectPackageName(projectRoot);
  } on Object {
    throw const GeneratedCatalogException('project_identity');
  }
  final catalog = File(generatedWidgetCatalogPath(projectRoot, packageName));
  if (generate) {
    await _generate(
      projectRoot: projectRoot,
      processRunner: processRunner ?? runRenderBundleProcess,
      dartExecutable: dartExecutable ?? _dartBesideFlutter(flutterExecutable),
    );
  } else if (!catalog.existsSync()) {
    throw const GeneratedCatalogException('catalog_missing');
  }
  if (!catalog.existsSync()) {
    return GeneratedWidgetCatalog(
      json: _emptyCustomCatalog(),
      registersWidgets: false,
    );
  }
  return GeneratedWidgetCatalog(
    json: await catalog.readAsString(),
    registersWidgets: true,
  );
}

Future<void> _generate({
  required Directory projectRoot,
  required RenderBundleProcessRunner processRunner,
  required String dartExecutable,
}) async {
  final ProcessResult result;
  try {
    result = await processRunner(
      dartExecutable,
      generatedWidgetCatalogCommand,
      workingDirectory: projectRoot.path,
    );
  } on Object {
    throw const GeneratedCatalogException('generate_failed');
  }
  if (result.exitCode != 0) {
    throw const GeneratedCatalogException('generate_failed');
  }
}

/// The Dart binary beside the resolved Flutter one, so the generator runs on
/// the same toolchain the bundle is built with.
String _dartBesideFlutter(String? flutterExecutable) {
  try {
    return p.join(
      File(flutterExecutable ?? findFlutterExecutable()).parent.path,
      'dart',
    );
  } on Object {
    throw const GeneratedCatalogException('toolchain');
  }
}

String _emptyCustomCatalog() => encodeCatalog(
  const Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: _generatedAt,
    libraries: <WidgetLibrary, LibraryInfo>{},
    widgets: <WidgetEntry>[],
  ),
);
