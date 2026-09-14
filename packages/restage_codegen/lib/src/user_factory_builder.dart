import 'dart:async';
import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/app_size_disclosure.dart';
import 'package:restage_codegen/src/app_widget_vocabulary.dart';
import 'package:restage_codegen/src/authored_library_predicate.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/custom_map_plan.dart';
import 'package:restage_codegen/src/custom_record_plan.dart';
import 'package:restage_codegen/src/custom_structured_reconstruction.dart';
import 'package:restage_codegen/src/installed_catalog_scope.dart';
import 'package:restage_codegen/src/restage_widget_walker.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_vocabulary.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Every authored Dart library in the consuming package.
const String _authoredDartGlob = 'lib/**.dart';

/// Aggregates `@RestageWidget`-annotated classes from the consuming
/// package — scanning every `lib/**.dart` and walking the files that spell a
/// Restage annotation (or an alias of one) — and emits a single
/// `lib/user_factories.g.dart` containing per-widget `LocalWidgetBuilder`
/// closures plus a one-call `registerRestageWidgets()` helper.
///
/// The app's `main()` calls the generated helper once at startup;
/// every widget annotated in the package becomes available to RFW blobs
/// without any hand-written factory plumbing.
///
/// The file is written for every package that runs the builder, because it
/// also carries the whole-app vocabulary — the built-in widgets and icons this
/// package's own `lib/` names, plus the catalog entries its compiled surfaces
/// render — which a package with no widget of its own still needs. If the
/// shared walker admits a widget that factory emission then rejects, the build
/// fails as an internal coherence error before any partial output is written.
final class UserFactoryBuilder implements Builder {
  /// Const constructor used by the `userFactoryBuilder` factory.
  const UserFactoryBuilder(this.options);

  /// `BuilderOptions` injected by build_runner. Carries the `catalog` option.
  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['user_factories.g.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Read before any other work so a bad option value fails the build loudly.
    final scope = readInstalledCatalogScope(options.config);
    // The aggregate names SDK types, so a package whose own pubspec does not
    // depend on the SDK never receives one — that is the catalog packages the
    // SDK itself depends on, not an app.
    if (!await _dependsOnRestageSdk(buildStep)) return;
    final installWholeCatalog = scope == InstalledCatalogScope.whole;
    final derivation = await derivePackageAppVocabulary(buildStep);
    final appVocabulary = derivation.references.union(
      await deriveCompiledSurfaceVocabulary(buildStep),
    );
    final collection = await collectRestageWidgetsForPackage(buildStep);

    // The admitted structured graph is threaded to the inline reconstructor:
    // a widget carrying a renderable structured
    // property is emitted to the catalog AND reconstructed here (admit + decode
    // together). An admitted widget the reconstructor can't handle is a
    // predicate gap (excluded upstream), never a factory skip.
    final source = collection == null
        ? emitEmptyUserFactoriesDart(
            appVocabulary: appVocabulary,
            installWholeCatalog: installWholeCatalog,
          )
        : emitAdmittedUserFactoriesDart(
            collection.widgets,
            structuredTypes: collection.structuredTypes,
            slotTargets: collection.slotTargets,
            nullableStructuredSlots: collection.nullableStructuredSlots,
            reconstructionPlans: collection.reconstructionPlans,
            mapPlans: collection.mapPlans,
            recordPlans: collection.recordPlans,
            stampedCapabilityVersions: collection.stampedCapabilityVersions,
            appVocabulary: appVocabulary,
            installWholeCatalog: installWholeCatalog,
          );

    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/user_factories.g.dart'),
      source,
    );

    // Every build shows the summary, so a developer reads what a delivered
    // surface can render without opening the generated file. The per-group
    // costs are longer, and ride the info log that --verbose shows.
    final position = switch (scope) {
      InstalledCatalogScope.whole => CatalogPosition.wholeCatalog,
      InstalledCatalogScope.derived when derivation.installsWholeCatalog =>
        CatalogPosition.appInstalled,
      InstalledCatalogScope.derived => CatalogPosition.derived,
    };
    // ignore: avoid_print
    print(
      summariseAppVocabulary(
        appVocabulary,
        position: position,
        builtInWidgetCount: derivation.builtInWidgetCount,
      ),
    );
    final groups = describeMissingWidgetGroups(
      appVocabulary,
      position: position,
    );
    if (groups.isNotEmpty) {
      log.info(groups.join('\n'));
    }
  }
}

/// The built-in widgets and icons the consuming package's own `lib/**.dart`
/// names, and whether that source installs the whole built-in catalog.
///
/// Every authored library is resolved, which is a wider walk than the
/// annotation prefilter the custom-widget collection uses: a widget an app
/// renders in ordinary Flutter code, on a screen nothing mounts yet, or in a
/// file carrying no Restage annotation at all still belongs in the app's
/// over-the-air headroom. Assets are visited in sorted order so the emitted
/// aggregate is byte-identical across runs.
Future<AppVocabularyDerivation> derivePackageAppVocabulary(
  BuildStep buildStep,
) async {
  final catalog = await loadMergedCatalog(buildStep);
  final assets = await buildStep.findAssets(Glob(_authoredDartGlob)).toList();
  assets.sort();
  final resolved = <ResolvedLibraryResult>[];
  for (final assetId in assets) {
    if (!isAuthoredDartLibraryAsset(assetId)) continue;
    final LibraryElement library;
    try {
      library = await buildStep.resolver.libraryFor(
        assetId,
        allowSyntaxErrors: true,
      );
    } on NonLibraryAssetException {
      // A `part` reaches the walk through the library that owns it.
      continue;
    }
    final result = await library.session.getResolvedLibraryByElement(library);
    if (result is ResolvedLibraryResult) resolved.add(result);
  }
  return deriveAppVocabulary(resolved, catalog);
}

/// The catalog entries this package's compiled surfaces render.
///
/// Read from the surface compiler's package-wide record rather than from the
/// Dart sources, so an entry the translation lowered to — an interpolated
/// `Text` becoming the rich-text entry, a `PageView` becoming the pager — is
/// in the app's over-the-air headroom too. Empty when the package compiles no
/// surface.
Future<SurfaceVocabularyReferences> deriveCompiledSurfaceVocabulary(
  BuildStep buildStep,
) async {
  final bundle = await readRestageCompilerHandoff(buildStep);
  if (bundle == null) return SurfaceVocabularyReferences.empty;
  return SurfaceVocabularyReferences(
    widgetNames: bundle.surfaceWidgetNames,
  );
}

/// Whether the consuming package's own pubspec depends on the Restage SDK.
///
/// An unreadable pubspec emits: that is a harness, not a catalog package.
Future<bool> _dependsOnRestageSdk(BuildStep buildStep) async {
  final pubspec = AssetId(buildStep.inputId.package, 'pubspec.yaml');
  try {
    if (!await buildStep.canRead(pubspec)) return true;
    return pubspecDependsOnRestageSdk(await buildStep.readAsString(pubspec));
  } on Object {
    return true;
  }
}

/// Whether [pubspec] names `restage` under `dependencies` or
/// `dev_dependencies`.
///
/// Read line by line rather than through a YAML parser so the toolchain keeps
/// its dependency surface; a pubspec dependency is always a direct child key
/// of one of those two top-level sections.
bool pubspecDependsOnRestageSdk(String pubspec) {
  const sections = {'dependencies', 'dev_dependencies'};
  final dependencyKey = RegExp(r'^\s+restage\s*:');
  var inSection = false;
  for (final raw in const LineSplitter().convert(pubspec)) {
    final line = raw.replaceAll('\t', '  ');
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(' ')) {
      inSection = sections.contains(line.split(':').first.trim());
      continue;
    }
    if (inSection && dependencyKey.hasMatch(line)) return true;
  }
  return false;
}

/// Emits factories for widgets already admitted by the production walker.
///
/// This is the only production emission seam. It always converts a lower-level
/// emitter skip into a hard coherence failure before the builder writes output.
/// [emitUserFactoriesDart] remains permissive only for lower-level tests and
/// tooling that inspect historical or manually assembled catalog shapes.
String emitAdmittedUserFactoriesDart(
  List<WidgetEntry> widgets, {
  List<StructuredEntry> structuredTypes = const [],
  Map<String, String> slotTargets = const {},
  Set<String> nullableStructuredSlots = const {},
  Map<String, ReconstructionPlan> reconstructionPlans = const {},
  Map<String, MapPlan> mapPlans = const {},
  Map<String, RecordPlan> recordPlans = const {},
  Map<String, int> stampedCapabilityVersions = const {},
  SurfaceVocabularyReferences appVocabulary = SurfaceVocabularyReferences.empty,
  bool installWholeCatalog = false,
}) {
  final source = emitUserFactoriesDart(
    widgets,
    structuredTypes: structuredTypes,
    slotTargets: slotTargets,
    nullableStructuredSlots: nullableStructuredSlots,
    reconstructionPlans: reconstructionPlans,
    mapPlans: mapPlans,
    recordPlans: recordPlans,
    stampedCapabilityVersions: stampedCapabilityVersions,
    appVocabulary: appVocabulary,
    installWholeCatalog: installWholeCatalog,
    onSkip: _throwAdmittedFactoryCoherenceFailure,
  );
  return source ??
      emitEmptyUserFactoriesDart(
        appVocabulary: appVocabulary,
        installWholeCatalog: installWholeCatalog,
      );
}

Never _throwAdmittedFactoryCoherenceFailure(WidgetEntry skipped) {
  throw StateError(
    'Internal Restage catalog/factory coherence failure: admitted '
    'catalog widget "${skipped.name}" (${skipped.flutterType}) was rejected '
    'by custom factory emission. Catalog names default to the Dart class '
    'and use an explicit override only when supplied. The shared admission '
    'predicate and factory emitter are out of sync; report this as a '
    'restage_codegen bug. No generated output was written.',
  );
}
