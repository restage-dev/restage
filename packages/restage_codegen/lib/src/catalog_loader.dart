import 'package:build/build.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:yaml/yaml.dart';

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

/// Loads built-in catalogs and custom catalogs in the declared package graph.
/// Built-ins keep their priority; custom packages follow in name order.
/// Packages without a generated catalog contribute nothing.
Future<Catalog> loadMergedCatalog(BuildStep buildStep) async =>
    await (await buildStep.fetchResource(_catalogResource))
        .getOrLoad(buildStep);

Future<Catalog> _loadMergedCatalog(
  BuildStep buildStep,
  List<String> packages,
) async {
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

  final owners = <WidgetLibrary, String>{};
  for (final package in packages) {
    await _mergeCustomCatalog(
      buildStep,
      package: package,
      owners: owners,
      widgets: widgets,
      structuredTypes: structuredTypes,
      unions: unions,
      designTokens: designTokens,
      compatRules: compatRules,
      libraries: libraries,
    );
  }

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

/// Merges one package's custom entries after the built-ins.
Future<void> _mergeCustomCatalog(
  BuildStep buildStep, {
  required String package,
  required Map<WidgetLibrary, String> owners,
  required List<WidgetEntry> widgets,
  required List<StructuredEntry> structuredTypes,
  required List<UnionEntry> unions,
  required List<DesignTokenEntry> designTokens,
  required List<CompatRule> compatRules,
  required Map<WidgetLibrary, LibraryInfo> libraries,
}) async {
  final customId = AssetId(package, 'lib/src/widget_catalog/catalog.json');
  // Register the read even on a cache miss so build_runner re-runs every
  // dependent paywall when the custom catalog changes under `--watch`.
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
  for (final library in cat.libraries.keys.where(isCustom)) {
    if (owners[library] case final owner?) {
      throw StateError(
        'Custom widget library ${library.namespace} is declared by both '
        '$owner and $package. Each library must have one owner.',
      );
    }
  }
  for (final library in cat.libraries.keys.where(isCustom)) {
    owners[library] = package;
  }
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

/// Custom catalog owners in the declared dependency graph, cached per build.
/// Every caller records the pubspec probes that determined this graph.
Future<List<String>> customCatalogPackages(BuildStep buildStep) async =>
    await (await buildStep.fetchResource(_catalogResource))
        .packagesFor(buildStep);

final _catalogResource =
    Resource<CatalogPerBuildCache>(CatalogPerBuildCache.new);

/// Shares dependency discovery and merged catalogs within one build pass.
class CatalogPerBuildCache {
  /// Creates a cache, optionally substituting the catalog loader.
  CatalogPerBuildCache({Future<Catalog> Function(BuildStep)? load})
      : _load = load;

  final Future<Catalog> Function(BuildStep)? _load;
  final _dependencies = <String, Future<List<String>>>{};
  final _graphs =
      <String, Future<({List<String> inputs, List<String> packages})>>{};
  final _catalogs = <String, Future<Catalog>>{};

  /// Discovers each package graph once and replays its input edges per caller.
  Future<List<String>> packagesFor(BuildStep buildStep) async {
    final graph =
        await (_graphs[buildStep.inputId.package] ??= _discover(buildStep));
    for (final package in graph.inputs) {
      await buildStep.canRead(AssetId(package, 'pubspec.yaml'));
    }
    return graph.packages;
  }

  /// Loads one catalog per package, recording every catalog edge per consumer.
  Future<Catalog> getOrLoad(BuildStep buildStep) async {
    final packages = await packagesFor(buildStep);
    for (final id in builtInCatalogAssetIds.values) {
      await buildStep.canRead(id);
    }
    for (final package in packages) {
      await buildStep.canRead(
        AssetId(package, 'lib/src/widget_catalog/catalog.json'),
      );
    }
    return await (_catalogs[buildStep.inputId.package] ??=
        _load?.call(buildStep) ?? _loadMergedCatalog(buildStep, packages));
  }

  Future<({List<String> inputs, List<String> packages})> _discover(
    BuildStep buildStep,
  ) async {
    final pending = [buildStep.inputId.package];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final package = pending.removeLast();
      if (!visited.add(package)) continue;
      final dependencies = await (_dependencies[package] ??=
          _readDependencies(buildStep, package));
      pending.addAll(dependencies);
    }
    final inputs = visited.toList()..sort();
    final builtIns =
        builtInCatalogAssetIds.values.map((id) => id.package).toSet();
    return (
      inputs: List<String>.unmodifiable(inputs),
      packages: List<String>.unmodifiable(
        inputs.where((package) => !builtIns.contains(package)),
      ),
    );
  }

  Future<List<String>> _readDependencies(
    BuildStep buildStep,
    String package,
  ) async {
    final pubspec = AssetId(package, 'pubspec.yaml');
    try {
      if (!await buildStep.canRead(pubspec)) return const [];
      final document = loadYaml(await buildStep.readAsString(pubspec));
      if (document is YamlMap) {
        final dependencies = document['dependencies'];
        if (dependencies is YamlMap) {
          return dependencies.keys.whereType<String>().toList();
        }
      }
    } on PackageNotFoundException {
      // An optional package is not installed.
    }
    return const [];
  }
}

/// Returns every [WidgetEntry] in [catalog] whose `name` matches [name],
/// across all libraries.
///
/// The translator only sees unqualified Dart class names in source; this
/// helper lets the caller distinguish "no match" from "ambiguous match
/// across libraries" and emit the right diagnostic. A single match means
/// the translation is unambiguous; multiple matches mean the same widget
/// name is registered in two or more libraries (e.g. a custom library
/// that shadows a built-in name).
List<WidgetEntry> findWidgetsByName(Catalog catalog, String name) => [
      for (final w in catalog.widgets)
        if (w.name == name) w,
    ];
