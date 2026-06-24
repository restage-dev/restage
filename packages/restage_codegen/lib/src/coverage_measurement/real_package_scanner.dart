// A standalone coverage-measurement scanner that points the inlinability
// classifier and the strict inline-emit translator at a real on-disk Flutter
// package, then reports how much of its custom-widget surface inlines today.
//
// This file is `src`-internal tooling: it is intentionally NOT exported from
// the package barrel. Its only consumer is the `bin/` measurement entrypoint.
// It depends on `package:analyzer` (a regular dependency) but never on the
// build-runner test harness, so it can resolve any pub-fetched package on disk
// via its own package config — not just sources mounted into an in-memory
// reader.

import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/coverage_measurement/coverage_report.dart';
import 'package:restage_codegen/src/coverage_measurement/emit_outcomes.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/production_helpers.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Thrown by [scanPackage] when the target package cannot be resolved because
/// it has not been fetched — there is no discoverable `package_config.json` for
/// it (neither in the package nor in an enclosing pub workspace). The
/// [message] tells the user how to fix it; this is the first failure mode a
/// real-package scan hits, so it is surfaced as an actionable diagnostic rather
/// than a raw analyzer error.
class PackageNotResolvedException implements Exception {
  /// Creates the exception for [packagePath] with an actionable [message].
  PackageNotResolvedException(this.packagePath, this.message);

  /// The package path the scan was pointed at (as supplied by the caller).
  final String packagePath;

  /// A human-actionable explanation of what to do.
  final String message;

  @override
  String toString() => 'PackageNotResolvedException: $message';
}

/// Selects which classes in a scanned package are measured as candidate
/// custom widgets.
///
/// The default ([restageAnnotatedWidgets]) matches the production
/// custom-widget surface — exactly the classes a build would transpile.
/// [allFlutterWidgets] widens selection to every `StatelessWidget` /
/// `StatefulWidget` subclass, so a published package whose classes carry no
/// custom-widget annotation can still be measured for its widget idioms.
typedef WidgetSelector = bool Function(ClassElement cls);

/// The default selector — a class is measured iff it carries a `@RestageWidget`
/// annotation. Preserves the scanner's original behavior.
bool restageAnnotatedWidgets(ClassElement cls) =>
    firstAnnotation(cls, 'RestageWidget') != null;

/// Selects every `StatelessWidget` / `StatefulWidget` subclass — public OR
/// private. For measuring the widget idioms of a real published package whose
/// classes are not annotated. Scanner-local: it widens which classes the scan
/// hands to the classifier; it does not alter the classifier's own recognition
/// (in particular, the classifier still recurses only into `@RestageWidget`
/// widgets, so a non-instrumented package's internal compositions surface as
/// `unrecognisedComposedWidget` — an under-statement in the safe direction).
bool allFlutterWidgets(ClassElement cls) {
  var supertype = cls.supertype;
  while (supertype != null) {
    final name = supertype.element.name;
    if (name == 'StatelessWidget' || name == 'StatefulWidget') return true;
    supertype = supertype.element.supertype;
  }
  return false;
}

/// Whether [path] is a code-generator output file rather than an authored
/// widget surface. Covers the common Dart generators so the scan never measures
/// or resolves generated code; extend the suffix set as new generators appear.
/// Cosmetic to the metric (generated files declare no `@RestageWidget`) — it
/// only keeps `filesResolved` and the skip ledger honest.
bool _isGeneratedDartFile(String path) {
  const suffixes = <String>[
    '.g.dart', // build_runner / source_gen (incl. the SDK's *.rsflow.g.dart)
    '.freezed.dart', // freezed
    '.mocks.dart', // mockito
    '.config.dart', // injectable
    '.gr.dart', // auto_route
    '.gen.dart', // flutter_gen and similar
  ];
  return suffixes.any(path.endsWith);
}

/// Whether the resolved `package_config.json` at [configPath] references the
/// package rooted at [absPackagePath] — i.e. some entry's resolved root is that
/// directory. A config that exists but omits the target (a stale or partial
/// workspace config that resolved against an enclosing root not including this
/// package) would otherwise yield a silently-empty scan; this turns that into
/// the actionable not-resolved diagnostic instead. Best-effort: an unreadable
/// or unparseable config is treated as not covering the package.
bool _configCoversPackage(String configPath, String absPackagePath) {
  final configFile = File(configPath);
  final PackageConfig config;
  try {
    // `onError` makes parsing best-effort (a malformed entry is dropped rather
    // than thrown), matching the not-covering-on-error posture; the try/catch
    // still guards a non-JSON / unreadable file.
    config = PackageConfig.parseString(
      configFile.readAsStringSync(),
      configFile.uri,
      onError: (_) {},
    );
  } on Object {
    return false;
  }
  final target = p.normalize(absPackagePath);
  for (final package in config.packages) {
    final root = package.root;
    if (root.scheme != 'file') continue;
    if (p.equals(p.normalize(root.toFilePath()), target)) return true;
  }
  return false;
}

/// One widget or file the scan deliberately did not measure, recorded with a
/// reason so the report never silently caps its coverage. Surfaced (not
/// swallowed) per the measurement-honesty contract.
class WidgetSkip {
  /// Records that [identifier] was skipped for [reason].
  WidgetSkip({required this.identifier, required this.reason});

  /// What was skipped — a file path or a widget class key.
  final String identifier;

  /// Why it was skipped (e.g. `generated file`, `unresolved fragment`).
  final String reason;

  @override
  String toString() => '$identifier — $reason';
}

/// The outcome of measuring one real package's `@RestageWidget` surface.
///
/// Holds the raw per-widget classifier verdicts and strict-emit outcomes; the
/// two coverage reports are derived from them so the classifier-recognised
/// upper bound and the emit-confirmed metric are always computed from the same
/// source and never conflated.
class ScanResult {
  /// Creates a scan result from the raw per-widget verdicts and scan counts.
  ScanResult({
    required this.packagePath,
    required this.classifications,
    required this.emitOutcomes,
    required this.skips,
    required this.filesScanned,
    required this.filesResolved,
  });

  /// The package path the scan was pointed at.
  final String packagePath;

  /// `classKey → WidgetClassification` for every `@RestageWidget` measured.
  final Map<String, WidgetClassification> classifications;

  /// `classKey → EmitOutcome` — the strict inline-emit verdict per widget.
  final Map<String, EmitOutcome> emitOutcomes;

  /// Files/widgets the scan did not measure, each with a reason.
  final List<WidgetSkip> skips;

  /// How many `.dart` files under `lib/` the scan considered.
  final int filesScanned;

  /// How many of those resolved to a library and were searched for widgets.
  final int filesResolved;

  /// Number of `@RestageWidget` widgets measured.
  int get widgetCount => classifications.length;

  /// The **classifier-recognised** bucketing — the upper bound on what could
  /// inline. Distinct from [emitConfirmedReport]; never conflate the two.
  /// Computed once from the immutable verdicts.
  late final CoverageReport classifierReport =
      CoverageReport.from(classifications);

  /// The **emit-confirmed** bucketing — widgets the classifier recognised but
  /// whose strict emit failed are demoted out of the inlinable buckets. This
  /// is the honest "inlines today" metric. Computed once.
  late final CoverageReport emitConfirmedReport =
      CoverageReport.from(classifications, emitOutcomes: emitOutcomes);
}

/// The built-in libraries whose committed `catalog.json` files merge into the
/// reference catalog, in built-in priority order (core < material < cupertino)
/// — matching the production build-step loader's iteration order so the merged
/// result is byte-for-byte equivalent.
///
/// Not `const`: [WidgetLibrary] overrides equality, so it cannot key a const
/// map (the same constraint the production loader's asset-id map carries).
final Map<WidgetLibrary, String> _builtInCatalogPackageUris = Map.unmodifiable({
  WidgetLibrary.core: 'package:restage_core/src/widget_catalog/catalog.json',
  WidgetLibrary.material:
      'package:restage_material/src/widget_catalog/catalog.json',
  WidgetLibrary.cupertino:
      'package:restage_cupertino/src/widget_catalog/catalog.json',
});

/// Loads the three committed built-in library catalogs from disk and merges
/// them into a single reference [Catalog], replicating the production
/// `loadMergedCatalog` merge (same per-library widget filter, same stable
/// sort, same construction) without needing a `build_runner` `BuildStep`.
///
/// The committed `catalog.json` files are located through the running
/// isolate's package config (so the loader is independent of the current
/// working directory). A built-in library whose catalog file is absent simply
/// contributes nothing — the same tolerance the build-step loader applies.
///
/// [catalogJsonByLibrary] overrides the on-disk lookup with in-memory JSON
/// strings; tests use it to feed known catalogs. When null the three committed
/// workspace catalogs are read from disk.
///
/// A drift guard (`real_package_scanner_test.dart`) asserts this result equals
/// the build-step `loadMergedCatalog` output, so the duplicated merge cannot
/// silently diverge from the production loader.
Future<Catalog> loadMergedCatalogFromDisk({
  Map<WidgetLibrary, String>? catalogJsonByLibrary,
}) async {
  final jsonByLibrary = catalogJsonByLibrary ?? await _readCommittedCatalogs();

  final widgets = <WidgetEntry>[];
  final structuredTypes = <StructuredEntry>[];
  final unions = <UnionEntry>[];
  final designTokens = <DesignTokenEntry>[];
  final compatRules = <CompatRule>[];
  final libraries = <WidgetLibrary, LibraryInfo>{};
  String? generatedAt;
  String? flutterVersion;

  for (final lib in _builtInCatalogPackageUris.keys) {
    final json = jsonByLibrary[lib];
    if (json == null) continue;
    final cat = requireNativeCatalog(decodeCatalog(json));
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

  const builtIns = WidgetLibrary.builtInLibraries;
  int byLibThenName(
    WidgetLibrary aLib,
    String aName,
    WidgetLibrary bLib,
    String bName,
  ) {
    final byLib = builtIns.indexOf(aLib).compareTo(builtIns.indexOf(bLib));
    if (byLib != 0) return byLib;
    return aName.compareTo(bName);
  }

  widgets.sort((a, b) => byLibThenName(a.library, a.name, b.library, b.name));
  structuredTypes
      .sort((a, b) => byLibThenName(a.library, a.name, b.library, b.name));
  unions.sort((a, b) => byLibThenName(a.library, a.name, b.library, b.name));
  designTokens
      .sort((a, b) => byLibThenName(a.library, a.name, b.library, b.name));

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

/// Measures the `@RestageWidget` custom-widget surface of the real Flutter
/// package at [packagePath] against [catalog], returning a [ScanResult] with
/// the classifier-recognised and emit-confirmed coverage reports.
///
/// Resolves the package's sources through the analyzer's
/// `AnalysisContextCollection`, which uses the package's own (or an enclosing
/// pub workspace's) `package_config.json`. If no package config is discoverable
/// the package has not been fetched, so this throws a
/// [PackageNotResolvedException] with an actionable message rather than letting
/// resolution fail opaquely.
///
/// [helpers] defaults to the same paywall-helper registry the production build
/// step registers (`paywallHelpers`), so the meter mirrors the build: a
/// `paywallPurchase(...)` / `paywallEvent(...)` / `paywallPriceFor(...)` call —
/// composition the build lowers — is measured as composition, not as an
/// unrecognised `dartCall`. The (name, libraryOrigin) match gates recognition
/// to the SDK's helpers, so a scanned package's own same-named function is not
/// mistaken for one. A caller may pass an explicit registry to override.
Future<ScanResult> scanPackage({
  required String packagePath,
  required Catalog catalog,
  HelperRegistry? helpers,
  WidgetSelector widgetSelector = restageAnnotatedWidgets,
}) async {
  final effectiveHelpers = helpers ?? productionPaywallHelperRegistry();
  // The analyzer requires an absolute, normalized path; a relative or
  // `..`-containing path from a CLI invocation must be normalized first.
  final absPath = p.normalize(p.absolute(packagePath));
  final collection = AnalysisContextCollection(includedPaths: [absPath]);
  try {
    final context = collection.contextFor(absPath);
    final packagesFile = context.contextRoot.packagesFile;
    if (packagesFile == null ||
        !_configCoversPackage(packagesFile.path, absPath)) {
      throw PackageNotResolvedException(
        packagePath,
        'No resolved package config covers "$packagePath". Run `dart pub get` '
        '(or `melos bootstrap` in a workspace) for the target package first, '
        'then re-run the scan.',
      );
    }

    final session = context.currentSession;
    final skips = <WidgetSkip>[];
    final libDir = Directory('$absPath/lib');
    if (!libDir.existsSync()) {
      return ScanResult(
        packagePath: packagePath,
        classifications: const {},
        emitOutcomes: const {},
        skips: [
          WidgetSkip(
            identifier: 'lib/',
            reason: 'package has no lib/ directory',
          ),
        ],
        filesScanned: 0,
        filesResolved: 0,
      );
    }

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('.dart'))
        .toList()
      ..sort();

    // Resolves a fragment to its AST node via the analyzer session, caching the
    // resolved library per element. This is the classifier's `astNodeFor`. The
    // classifier passes fragments for build/createState/event methods and
    // foldable field initialisers, all from the widgets being classified.
    final resolvedLibCache = <LibraryElement, ResolvedLibraryResult>{};
    Future<AstNode?> astNodeFor(Fragment fragment) async {
      final library = fragment.element.library;
      if (library == null) {
        skips.add(
          WidgetSkip(
            identifier: fragment.element.name ?? '<fragment>',
            reason: 'fragment has no enclosing library; cannot resolve its AST',
          ),
        );
        return null;
      }
      var resolved = resolvedLibCache[library];
      if (resolved == null) {
        final res = await session.getResolvedLibraryByElement(library);
        if (res is! ResolvedLibraryResult) {
          skips.add(
            WidgetSkip(
              identifier: library.identifier,
              reason: 'library did not resolve (${res.runtimeType})',
            ),
          );
          return null;
        }
        resolved = res;
        resolvedLibCache[library] = resolved;
      }
      return resolved.getFragmentDeclaration(fragment)?.node;
    }

    final classifier = WidgetClassifier(
      catalog: catalog,
      helpers: effectiveHelpers,
      astNodeFor: astNodeFor,
    );

    var filesScanned = 0;
    var filesResolved = 0;
    for (final path in dartFiles) {
      filesScanned++;
      final relative = p.relative(path, from: absPath);
      // Generated files are codegen output, not the authored custom-widget
      // surface — skip them, but record the skip so the metric never silently
      // caps. (`firstAnnotation` would ignore them anyway; the explicit skip
      // keeps the count honest.)
      if (_isGeneratedDartFile(path)) {
        skips.add(
          WidgetSkip(
            identifier: relative,
            reason: 'generated file (not an authored widget)',
          ),
        );
        continue;
      }
      final resolved = await session.getResolvedLibrary(path);
      if (resolved is! ResolvedLibraryResult) {
        // The only non-library result for an enumerated on-disk `.dart` file is
        // a part file — its declarations are reached when its owning library
        // resolves (`element.classes` includes part-declared classes), so this
        // is not a measurement gap. (A library with analysis errors still
        // resolves to a `ResolvedLibraryResult` and is searched below.)
        continue;
      }
      filesResolved++;
      // Seed the astNodeFor cache so classifying this library's members does
      // not re-resolve a library we just resolved.
      resolvedLibCache[resolved.element] = resolved;
      for (final cls in resolved.element.classes) {
        if (!widgetSelector(cls)) continue;
        await classifier.classify(cls);
      }
    }

    final classifications =
        Map<String, WidgetClassification>.unmodifiable(classifier.results);
    final emitOutcomes = computeEmitOutcomes(
      classifications,
      classifier.blueprints,
      catalog: catalog,
      helpers: effectiveHelpers,
    );

    return ScanResult(
      packagePath: packagePath,
      classifications: classifications,
      emitOutcomes: emitOutcomes,
      skips: List.unmodifiable(skips),
      filesScanned: filesScanned,
      filesResolved: filesResolved,
    );
  } finally {
    await collection.dispose();
  }
}

/// Renders a [ScanResult] as a human-readable report. Shows the
/// classifier-recognised upper bound and the emit-confirmed metric as distinct
/// totals (never conflated), a per-bucket `recognised -> emit-confirmed`
/// breakdown that makes the demotion visible, and the full skip list so the
/// metric's coverage is never silently capped.
String renderScanReport(ScanResult result) {
  final classifier = result.classifierReport;
  final emit = result.emitConfirmedReport;
  final n = result.widgetCount;
  final buf = StringBuffer()
    ..writeln('Coverage measurement: ${result.packagePath}')
    ..writeln('@RestageWidget widgets measured: $n')
    ..writeln()
    ..writeln(
      'Classifier-recognised inlinable: ${classifier.inlinableTotal}/$n'
      '  (upper bound)',
    )
    ..writeln(
      'Emit-confirmed inlinable:         ${emit.inlinableTotal}/$n'
      '  (inlines today)',
    )
    ..writeln()
    ..writeln('Per-bucket [classifier-recognised -> emit-confirmed]:');
  for (final bucket in CoverageBucket.values) {
    buf.writeln(
      '  ${bucket.snapshotKey.padRight(32)} '
      '${classifier.countOf(bucket)} -> ${emit.countOf(bucket)}',
    );
  }
  buf.writeln(
    '\nFiles scanned: ${result.filesScanned} '
    '(resolved: ${result.filesResolved})',
  );
  if (result.skips.isEmpty) {
    buf.writeln('Skipped: none');
  } else {
    buf.writeln('Skipped (${result.skips.length}):');
    for (final skip in result.skips) {
      buf.writeln('  $skip');
    }
  }
  return buf.toString();
}

/// Reads the committed built-in `catalog.json` files via the running isolate's
/// package config. A library whose file cannot be resolved or read is omitted
/// (it contributes nothing to the merge).
Future<Map<WidgetLibrary, String>> _readCommittedCatalogs() async {
  final result = <WidgetLibrary, String>{};
  for (final entry in _builtInCatalogPackageUris.entries) {
    final resolved = await Isolate.resolvePackageUri(Uri.parse(entry.value));
    if (resolved == null) continue;
    final file = File.fromUri(resolved);
    if (!file.existsSync()) continue;
    result[entry.key] = await file.readAsString();
  }
  return result;
}
