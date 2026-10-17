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

/// What to do when the app's generator writes no merged catalog.
const renderCatalogMissingMessage =
    "This app's restage_codegen predates the render catalog a build push "
    'needs. Upgrade restage_codegen to the latest version.';

/// One app's generated widget catalogs.
final class GeneratedWidgetCatalog {
  const GeneratedWidgetCatalog({
    required this.json,
    required this.renderJson,
    required this.registersWidgets,
  });

  /// The custom widget libraries of the app and its dependencies.
  final String json;

  /// The catalog the bundle is built against: the built-ins and every custom
  /// catalog in the app's dependency graph, as the generator merged them.
  /// Null when the app's generator does not write it.
  final String? renderJson;

  /// Whether the app or its dependencies register any widget.
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
    _generatedCatalogPath(projectRoot, packageName, 'catalog.json');

/// Where the generator writes the merged catalog [packageName]'s render
/// bundle is built against.
String generatedRenderCatalogPath(Directory projectRoot, String packageName) =>
    _generatedCatalogPath(projectRoot, packageName, 'render_catalog.json');

String _generatedCatalogPath(
  Directory projectRoot,
  String packageName,
  String file,
) => p.join(
  projectRoot.path,
  '.dart_tool',
  'build',
  'generated',
  packageName,
  'lib',
  'src',
  'widget_catalog',
  file,
);

/// Runs the generator, then reads what it wrote.
///
/// With [generate] false a catalog a previous run produced is required.
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
  final render = File(generatedRenderCatalogPath(projectRoot, packageName));
  if (generate) {
    await _generate(
      projectRoot: projectRoot,
      processRunner: processRunner ?? runRenderBundleProcess,
      dartExecutable: dartExecutable ?? _dartBesideFlutter(flutterExecutable),
    );
  }
  final ownJson = catalog.existsSync() ? await catalog.readAsString() : null;
  final renderJson = render.existsSync() ? await render.readAsString() : null;
  if (!generate && ownJson == null && renderJson == null) {
    throw const GeneratedCatalogException('catalog_missing');
  }
  final custom = renderJson == null
      ? ownJson ?? _emptyCustomCatalog()
      : _customLibraries(renderJson);
  return GeneratedWidgetCatalog(
    json: custom,
    renderJson: renderJson,
    registersWidgets: decodeCatalog(custom).widgets.isNotEmpty,
  );
}

/// The custom libraries of the merged [renderJson], without the built-ins.
String _customLibraries(String renderJson) {
  final merged = decodeCatalog(renderJson);
  bool custom(WidgetLibrary library) =>
      WidgetLibrary.builtInByNamespace(library.namespace) == null;
  return encodeCatalog(
    Catalog(
      schemaVersion: merged.schemaVersion,
      generatedAt: _generatedAt,
      libraries: {
        for (final entry in merged.libraries.entries)
          if (custom(entry.key)) entry.key: entry.value,
      },
      widgets: [
        for (final widget in merged.widgets)
          if (custom(widget.library)) widget,
      ],
      structuredTypes: [
        for (final entry in merged.structuredTypes)
          if (custom(entry.library)) entry,
      ],
      unions: [
        for (final entry in merged.unions)
          if (custom(entry.library)) entry,
      ],
      designTokens: [
        for (final entry in merged.designTokens)
          if (custom(entry.library)) entry,
      ],
      flutterVersion: merged.flutterVersion,
      compatRules: switch ([
        for (final rule in merged.compatRules ?? const <CompatRule>[])
          if (WidgetLibrary.builtInByNamespace(rule.affectedRef.library) ==
              null)
            rule,
      ]) {
        final List<CompatRule> rules when rules.isNotEmpty => rules,
        _ => null,
      },
    ),
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
