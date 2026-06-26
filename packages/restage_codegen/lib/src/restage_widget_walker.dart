import 'dart:async';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/syntax_diagnostics.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Walks every `lib/**.dart` asset in [buildStep]'s package for
/// `@RestageWidget`-annotated classes, aggregates the resulting
/// `WidgetEntry`s, detects cross-file `(library, name)` duplicates, and
/// returns the deduplicated list in `(library namespace, name)` order
/// for byte-deterministic emit.
///
/// Returns `null` when no `@RestageWidget`-annotated classes are present
/// so the caller can short-circuit emission.
///
/// Throws [StateError] after `log.severe`-ing each [Issue] when any
/// issues surface during the walk (annotation field gaps, unsupported
/// property types, duplicate widget names across files). The thrown
/// error surfaces as a failed build via `testBuilder`'s `result.errors`.
///
/// Both the customer-catalog and customer-factory builders consume this
/// helper so the per-package walk runs once worth of structural work per
/// builder rather than two near-identical implementations drifting in
/// step with each other.
Future<List<WidgetEntry>?> collectRestageWidgetsForPackage(
  BuildStep buildStep,
) async {
  final widgets = <WidgetEntry>[];
  final issues = <Issue>[];

  await for (final assetId in buildStep.findAssets(Glob('lib/**.dart'))) {
    // Do not pre-filter with `resolver.isLibrary` — its implementation
    // calls `libraryFor` internally, so a guard would double the resolver
    // cost on every Dart asset. Catch `NonLibraryAssetException` instead.
    final LibraryElement library;
    try {
      library = await buildStep.resolver.libraryFor(
        assetId,
        allowSyntaxErrors: true,
      );
    } on NonLibraryAssetException {
      continue;
    }
    final result = visitRestageWidgets(library, assetId);
    widgets.addAll(result.widgets);
    issues.addAll(result.issues);

    // The asset resolved with `allowSyntaxErrors: true`, so a malformed token
    // whose parser error-recovery yields a structurally-valid declaration
    // could otherwise be walked into a clean catalog with the bad token
    // silently dropped. Surface genuine syntactic errors so a malformed
    // customer-widget source fails the build rather than emitting a degraded
    // entry.
    final resolved = await library.session.getResolvedLibraryByElement(library);
    if (resolved is ResolvedLibraryResult && resolved.units.isNotEmpty) {
      issues.addAll(syntacticErrorIssues(resolved, sourcePath: assetId.path));
    }
  }

  // A customer structured (data-class) property cannot yet render on the RFW
  // path: the customer-factory emitter has no runtime reconstructor for a
  // customer type (the structured-ref decoder table is built-in only). A
  // widget carrying one is therefore EXCLUDED from the RFW catalog/factory —
  // it still renders in the A2UI catalog (which reconstructs the value shape
  // directly). This is a NON-FATAL exclusion (logged, not an issue), distinct
  // from the unsupported-type / duplicate-name issues below which fail the
  // build. RFW rendering of customer structured types is a future capability.
  widgets.removeWhere((w) {
    if (!_hasUnrenderableCustomerStructured(w)) return false;
    log.info(
      'Customer widget ${w.library.namespace}#${w.name} carries a structured '
      'property and is excluded from the RFW catalog/factory; it renders in '
      'the A2UI catalog. RFW rendering of customer structured types is a '
      'future capability.',
    );
    return true;
  });

  // The visitor catches duplicate (library, name) pairs within a single
  // file. Cross-file collisions only surface here, after aggregation.
  final byKey = <String, List<WidgetEntry>>{};
  for (final w in widgets) {
    byKey.putIfAbsent('${w.library.namespace}#${w.name}', () => []).add(w);
  }
  for (final entry in byKey.entries.where((e) => e.value.length > 1)) {
    final declarations = entry.value.map((w) => w.flutterType).join(', ');
    issues.add(
      Issue(
        code: IssueCode.duplicateWidgetName,
        message: 'Multiple @RestageWidget classes across this package '
            'share name in ${entry.key}: $declarations.',
        location: 'lib/',
      ),
    );
  }

  if (issues.isNotEmpty) {
    for (final issue in issues) {
      log.severe(issue.toString());
    }
    throw StateError(
      '${issues.length} customer widget issue(s) detected; see log above.',
    );
  }

  if (widgets.isEmpty) return null;

  final ordered = widgets.toList()
    ..sort((a, b) {
      final byLib = a.library.namespace.compareTo(b.library.namespace);
      if (byLib != 0) return byLib;
      return a.name.compareTo(b.name);
    });
  return ordered;
}

/// Whether [w] carries a property that lowers to a CUSTOMER structured value
/// (`PropertyType.structured` with a structured reference into a non-built-in
/// library). Such a widget cannot render on the RFW path yet — the
/// customer-factory emitter has no runtime reconstructor for a customer type —
/// so it is excluded from the RFW catalog/factory (see
/// [collectRestageWidgetsForPackage]). A built-in structured type (e.g.
/// `TextStyle`) has a registered decoder and is NOT excluded.
bool _hasUnrenderableCustomerStructured(WidgetEntry w) {
  for (final property in w.properties) {
    if (property.type != PropertyType.structured) continue;
    final ref = property.structuredRef;
    if (ref == null) continue;
    if (WidgetLibrary.builtInByNamespace(ref.library) == null) return true;
  }
  return false;
}
