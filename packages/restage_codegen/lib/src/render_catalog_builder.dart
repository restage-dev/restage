import 'package:build/build.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/user_factory_builder.dart'
    show dependsOnRestageSdk;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Where [RenderCatalogBuilder] writes the package's merged catalog.
const String kRenderCatalogPath = 'lib/src/widget_catalog/render_catalog.json';

/// Writes the catalog a render bundle of this package renders against: the
/// built-in catalogs and every custom catalog in its dependency graph. A
/// package that does not depend on the Restage SDK gets none.
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
    // A fixed stamp keeps identical inputs byte-identical.
    final catalog = Catalog(
      schemaVersion: merged.schemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: merged.libraries,
      widgets: merged.widgets,
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
