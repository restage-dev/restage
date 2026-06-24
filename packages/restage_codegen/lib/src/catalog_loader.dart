import 'package:build/build.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Asset paths that [loadMergedCatalog] reads, paired with the library
/// each file owns. Listed in built-in priority order so the merged
/// catalog's iteration order is deterministic across runs.
///
/// Builders that cache the merged result across BuildSteps in a single
/// build pass must `await buildStep.canRead(id)` for every entry on
/// each cache hit so `build_runner` records the read as an input of
/// every dependent BuildStep — without it, only the first BuildStep to
/// populate the cache registers the dep, and subsequent paywalls go
/// stale when `catalog.json` changes in `--watch`.
// Not `const` because AssetId has no const constructor and WidgetLibrary
// overrides equality (so it can't key a const map). Still a top-level
// shared list — every BuildStep reads the same `final`.
final Map<WidgetLibrary, AssetId> builtInCatalogAssetIds = Map.unmodifiable({
  WidgetLibrary.core: AssetId(
    'restage_core',
    'lib/src/widget_catalog/catalog.json',
  ),
  WidgetLibrary.material: AssetId(
    'restage_material',
    'lib/src/widget_catalog/catalog.json',
  ),
  WidgetLibrary.cupertino: AssetId(
    'restage_cupertino',
    'lib/src/widget_catalog/catalog.json',
  ),
});

/// Loads each built-in library's per-package
/// `lib/src/widget_catalog/catalog.json` via cross-package asset reads,
/// decodes each as a canonical catalog, and merges them into a single
/// [Catalog] keyed by `(library, name)`.
///
/// Tolerates a missing per-package `catalog.json` — a built-in library
/// that has no generated widgets yet
/// simply contributes nothing to the merged catalog.
///
/// Per-package files only ever contain widgets for the file's owning
/// library; the `library`-matches-owner filter on the merge is purely
/// defensive against schema drift or hand-edits.
Future<Catalog> loadMergedCatalog(BuildStep buildStep) async {
  final results = await Future.wait(
    builtInCatalogAssetIds.entries.map((entry) async {
      try {
        return MapEntry(entry.key, await buildStep.readAsString(entry.value));
      } on AssetNotFoundException {
        // Library exists in the asset graph but hasn't shipped its
        // catalog.json yet.
        return null;
      } on PackageNotFoundException {
        // Library package isn't in the build's asset graph at all —
        // happens in unit tests that bootstrap a fixture package without
        // workspace package_config. The loader treats it the same as
        // an empty-catalog library and lets downstream validation
        // diagnose any missing-widget references.
        return null;
      }
    }),
  );

  final widgets = <WidgetEntry>[];
  final structuredTypes = <StructuredEntry>[];
  final unions = <UnionEntry>[];
  final designTokens = <DesignTokenEntry>[];
  final compatRules = <CompatRule>[];
  final libraries = <WidgetLibrary, LibraryInfo>{};
  String? generatedAt;
  String? flutterVersion;

  for (final entry in results.whereType<MapEntry<WidgetLibrary, String>>()) {
    final lib = entry.key;
    final cat = requireNativeCatalog(decodeCatalog(entry.value));
    widgets.addAll(cat.widgets.where((w) => w.library == lib));
    structuredTypes.addAll(cat.structuredTypes.where((s) => s.library == lib));
    unions.addAll(cat.unions.where((u) => u.library == lib));
    designTokens.addAll(cat.designTokens.where((t) => t.library == lib));
    compatRules.addAll(
      cat.compatRules?.where((r) => r.affectedRef.library == lib.namespace) ??
          const [],
    );
    final info = cat.libraries[lib];
    if (info != null) libraries[lib] = info;
    generatedAt ??= cat.generatedAt;
    flutterVersion ??= cat.flutterVersion;
  }

  // Stable cross-run order: by built-in priority (core < material <
  // cupertino), then by name within library. The catalog generator
  // already emits this order per file; the merge preserves it.
  const builtIns = WidgetLibrary.builtInLibraries;
  widgets.sort((a, b) {
    final byLib =
        builtIns.indexOf(a.library).compareTo(builtIns.indexOf(b.library));
    if (byLib != 0) return byLib;
    return a.name.compareTo(b.name);
  });
  structuredTypes.sort((a, b) {
    final byLib =
        builtIns.indexOf(a.library).compareTo(builtIns.indexOf(b.library));
    if (byLib != 0) return byLib;
    return a.name.compareTo(b.name);
  });
  unions.sort((a, b) {
    final byLib =
        builtIns.indexOf(a.library).compareTo(builtIns.indexOf(b.library));
    if (byLib != 0) return byLib;
    return a.name.compareTo(b.name);
  });
  designTokens.sort((a, b) {
    final byLib =
        builtIns.indexOf(a.library).compareTo(builtIns.indexOf(b.library));
    if (byLib != 0) return byLib;
    return a.name.compareTo(b.name);
  });

  await _mergeCustomerCatalog(
    buildStep,
    widgets: widgets,
    structuredTypes: structuredTypes,
    unions: unions,
    designTokens: designTokens,
    compatRules: compatRules,
    libraries: libraries,
  );

  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: generatedAt ?? '1970-01-01T00:00:00Z',
    libraries: Map.unmodifiable(libraries),
    widgets: List.unmodifiable(widgets),
    structuredTypes: List.unmodifiable(structuredTypes),
    unions: List.unmodifiable(unions),
    designTokens: List.unmodifiable(designTokens),
    flutterVersion: flutterVersion,
    compatRules: compatRules.isEmpty ? null : List.unmodifiable(compatRules),
  );
}

/// Merges the customer's own generated catalog — the custom `@RestageLibrary`
/// widgets at `lib/src/widget_catalog/catalog.json` in the package being built
/// — into the [widgets]/[structuredTypes]/[unions]/[designTokens]/[compatRules]
/// /[libraries] accumulators already populated with the built-ins.
///
/// Custom entries are **appended after** the sorted built-ins (not re-sorted
/// into them), so the built-in resolution order is preserved — a built-in
/// widget name always resolves to its built-in, never a custom shadow — and the
/// built-in byte order is unchanged. Only custom-library entries are taken
/// (defensive against a customer catalog that somehow carries a built-in).
///
/// The built-in catalog packages are already merged via their fixed asset ids,
/// so the customer read is **skipped when the input package is itself a
/// built-in catalog package** — its catalog must never be re-merged as if it
/// were custom. A package that ships no custom catalog (the common case)
/// contributes nothing.
Future<void> _mergeCustomerCatalog(
  BuildStep buildStep, {
  required List<WidgetEntry> widgets,
  required List<StructuredEntry> structuredTypes,
  required List<UnionEntry> unions,
  required List<DesignTokenEntry> designTokens,
  required List<CompatRule> compatRules,
  required Map<WidgetLibrary, LibraryInfo> libraries,
}) async {
  final inputPackage = buildStep.inputId.package;
  final builtInPackages =
      builtInCatalogAssetIds.values.map((id) => id.package).toSet();
  if (builtInPackages.contains(inputPackage)) return;

  final customId = AssetId(inputPackage, 'lib/src/widget_catalog/catalog.json');
  // Register the read even on a cache miss so build_runner re-runs every
  // dependent paywall when the customer catalog changes under `--watch`.
  await buildStep.canRead(customId);

  String? customJson;
  try {
    customJson = await buildStep.readAsString(customId);
  } on AssetNotFoundException {
    return; // the package ships no custom catalog — nothing to merge
  } on PackageNotFoundException {
    return; // not in the asset graph (unit-test bootstrap) — nothing to merge
  }

  final cat = requireNativeCatalog(decodeCatalog(customJson));
  bool isCustom(WidgetLibrary library) =>
      WidgetLibrary.builtInByNamespace(library.namespace) == null;

  final customWidgets = cat.widgets.where((w) => isCustom(w.library)).toList()
    ..sort((a, b) {
      final byLib = a.library.namespace.compareTo(b.library.namespace);
      return byLib != 0 ? byLib : a.name.compareTo(b.name);
    });
  widgets.addAll(customWidgets);
  structuredTypes.addAll(cat.structuredTypes.where((s) => isCustom(s.library)));
  unions.addAll(cat.unions.where((u) => isCustom(u.library)));
  designTokens.addAll(cat.designTokens.where((t) => isCustom(t.library)));
  compatRules.addAll(
    cat.compatRules?.where(
          (r) =>
              WidgetLibrary.builtInByNamespace(r.affectedRef.library) == null,
        ) ??
        const [],
  );
  for (final entry in cat.libraries.entries) {
    if (isCustom(entry.key)) libraries[entry.key] = entry.value;
  }
}

/// Returns every [WidgetEntry] in [catalog] whose `name` matches [name],
/// across all libraries.
///
/// The translator only sees unqualified Dart class names in source; this
/// helper lets the caller distinguish "no match" from "ambiguous match
/// across libraries" and emit the right diagnostic. A single match means
/// the translation is unambiguous; multiple matches mean the same widget
/// name is registered in two or more libraries (e.g. a customer library
/// that shadows a built-in name).
List<WidgetEntry> findWidgetsByName(Catalog catalog, String name) => [
      for (final w in catalog.widgets)
        if (w.name == name) w,
    ];
