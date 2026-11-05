import 'package:build/build.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/user_factory_builder.dart'
    show dependsOnRestageSdk;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Where [RenderCatalogBuilder] writes the package's merged catalog.
const String kRenderCatalogPath = 'lib/src/widget_catalog/render_catalog.json';

/// Writes the catalog a render bundle of this package renders against: the
/// built-in catalogs, every custom catalog in its dependency graph, and the
/// package's islands. A package that does not depend on the Restage SDK gets
/// none.
final class RenderCatalogBuilder implements Builder {
  /// Creates the builder.
  const RenderCatalogBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$package$': [kRenderCatalogPath],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    if (!await dependsOnRestageSdk(buildStep)) return;
    final merged = await loadMergedCatalog(buildStep);
    final islands = <String, WidgetEntry>{};
    final islandLibraries = <WidgetLibrary, LibraryInfo>{};
    final manifest = (await readRestageCompilerHandoff(buildStep))?.manifest;
    for (final entry in [...?manifest?.publications]) {
      for (final contract in entry.publication.compiledScreenContracts.values) {
        for (final widget in contract.catalog.widgets) {
          final library = contract.catalog.libraries[widget.library];
          if (library == null || !library.islands) continue;
          islands[widget.name] = widget;
          islandLibraries[widget.library] = library;
        }
      }
    }
    // A fixed stamp keeps identical inputs byte-identical.
    final catalog = Catalog(
      schemaVersion: merged.schemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {...merged.libraries, ...islandLibraries},
      widgets: [
        ...merged.widgets,
        for (final name in islands.keys.toList()..sort()) islands[name]!,
      ],
      structuredTypes: merged.structuredTypes,
      unions: merged.unions,
      designTokens: merged.designTokens,
      flutterVersion: merged.flutterVersion,
      compatRules: merged.compatRules,
    );
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, kRenderCatalogPath),
      encodeCatalog(catalog),
    );
  }
}
