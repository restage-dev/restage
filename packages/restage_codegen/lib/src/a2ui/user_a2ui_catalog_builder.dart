import 'dart:async';
import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_seam_assembly.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/syntax_diagnostics.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The generated A2UI catalog file. Declares
/// `List<CatalogItem> buildRestageCatalogItems()` — the function the consumer
/// passes to genui's `Catalog(...)`.
const _catalogAssetName = 'restage_a2ui_catalog.g.dart';

/// The companion capability-stamp document — the
/// `{restageCapability, a2uiCatalog}` JSON the app-side check reads.
const _stampAssetName = 'restage_a2ui_catalog.a2ui.json';

/// Placeholder pub version for a customer library's catalog envelope. The A2UI
/// stamp reads only `capabilityVersion`; the pub `version` is not part of the
/// A2UI capability axis, so a deterministic placeholder keeps the emit
/// byte-stable (matching the customer-catalog emitter's convention).
const _customerLibraryVersion = '0.0.0';

/// Aggregates the consuming package's `@RestageWidget` source into a genui
/// **A2UI** catalog (the autonomous-codegen emit target), emitting
/// `lib/restage_a2ui_catalog.g.dart` (`buildRestageCatalogItems()`) plus the
/// companion `lib/restage_a2ui_catalog.a2ui.json` capability stamp.
///
/// The customer widgets are read from the consuming package's own source — the
/// same public walk the customer-catalog emitter uses (`@RestageWidget`
/// projection via the supported property vocabulary) — so the chain is fully
/// reproducible by any consumer of the public toolchain. For each customer
/// widget the build-phase auto-wiring assembles the three analyzer-fed A2UI
/// read legs (rich data shapes, event surfaces, and the
/// `@RestageProperty(writeBackValue:)` value pairing) via [assembleA2uiSeams],
/// threaded into the unchanged A2UI emitter.
///
/// The emitted catalog is the **merged** set — the built-ins (read from the
/// committed built-in catalogs) plus the customer widgets — so the consumer
/// registers a single genui `Catalog`.
///
/// Each contributing customer library must declare
/// `@RestageLibrary(capabilityVersion:)`; the version is read off the barrel
/// and carried into the stamp's custom-library capability axis (the A2UI
/// emitter fails loud if a contributing custom library declares none).
///
/// Skips emit when the package contributes no customer widgets — a package
/// without custom widgets does not acquire an A2UI catalog file. This builder
/// is **opt-in** (it is not applied to dependents): the emitted code imports
/// the genui runtime, so a consumer enables it explicitly only when they want
/// an A2UI catalog.
///
/// The toolchain stays runtime-free: the emit is string emission, so this
/// builder never imports the genui runtime — only the *generated* code does,
/// and that compiles in the consumer's package (which declares the genui
/// dependency).
final class UserA2uiCatalogBuilder implements Builder {
  /// Const constructor used by the `userA2uiCatalogBuilder` factory.
  const UserA2uiCatalogBuilder(this.options);

  /// `BuilderOptions` injected by the build system; currently unused.
  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': [_catalogAssetName, _stampAssetName],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final walk = await _walkCustomerWidgets(buildStep);
    if (walk.widgets.isEmpty) return;

    final catalog = await _mergedCatalog(buildStep, walk);
    final seams = assembleA2uiSeams(walk.widgets);

    // A structured property the A2UI emitter cannot represent (a data class
    // with an unrepresentable field) surfaces as a seam issue — fail it loud,
    // never let the widget silently drop from the catalog. Mirrors the
    // walk-issue surfacing in [_walkCustomerWidgets].
    if (seams.issues.isNotEmpty) {
      for (final issue in seams.issues) {
        log.severe(issue.toString());
      }
      throw StateError(
        '${seams.issues.length} customer widget A2UI seam issue(s) detected; '
        'see log above.',
      );
    }

    final dart = formatGeneratedDart(
      emitA2uiCatalogDart(
        catalog,
        richShapes: seams.richShapes,
        eventSeam: seams.eventSeam,
        pairingSeam: seams.pairingSeam,
      ),
    );
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/$_catalogAssetName'),
      dart,
    );

    final stamp = emitA2uiCatalog(
      catalog,
      richShapes: seams.richShapes,
      eventSeam: seams.eventSeam,
      pairingSeam: seams.pairingSeam,
    ).toJson();
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/$_stampAssetName'),
      const JsonEncoder.withIndent('  ').convert(stamp),
    );
  }

  /// Walks every `lib/**.dart` asset for the consumer's `@RestageWidget`
  /// classes — projecting each to a [WidgetEntry] via the public
  /// [visitRestageWidgets] vocabulary while capturing its resolved
  /// [ClassElement] (the seam-assembly's analyzer input) in the same pass — and
  /// reads each contributing library's `@RestageLibrary(capabilityVersion:)`.
  /// Surfaces any walk issue (an unsupported property type, a duplicate name)
  /// loud as a failed build, mirroring the customer-catalog walk.
  Future<_CustomerWalk> _walkCustomerWidgets(BuildStep buildStep) async {
    final widgets = <A2uiWidgetElement>[];
    final capabilityVersions = <WidgetLibrary, int?>{};
    final issues = <Issue>[];

    await for (final assetId in buildStep.findAssets(Glob('lib/**.dart'))) {
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
      issues.addAll(result.issues);
      for (final entry in result.widgets) {
        // A customer `@RestageWidget` must not claim a built-in namespace — it
        // would bypass the custom-library capability axis and overwrite the
        // built-in catalog's library metadata in the merge. Reject it loud.
        if (WidgetLibrary.builtInByNamespace(entry.library.namespace) != null) {
          issues.add(
            Issue(
              code: IssueCode.invalidWidgetClass,
              message: "@RestageWidget '${entry.name}' declares the built-in "
                  'namespace "${entry.library.namespace}", which is reserved.',
              location: '${assetId.path}#${entry.name}',
            ),
          );
          continue;
        }
        final className = entry.flutterType.split('#').last;
        final element =
            library.classes.where((c) => c.name == className).firstOrNull;
        if (element == null) {
          // The projection came from this library's classes, so a missing class
          // is an internal inconsistency — fail loud, never silently drop.
          issues.add(
            Issue(
              code: IssueCode.analyzerResolutionFailed,
              message: "could not resolve the class '$className' for "
                  "@RestageWidget '${entry.name}'.",
              location: '${assetId.path}#${entry.name}',
            ),
          );
          continue;
        }
        widgets.add((entry: entry, element: element));
      }

      // Surface genuine syntactic errors: the asset resolved with
      // `allowSyntaxErrors: true`, so a malformed token whose parser recovery
      // yields a structurally-valid declaration would otherwise be walked into
      // a clean catalog with the bad token silently dropped.
      final resolved = await library.session.getResolvedLibraryByElement(
        library,
      );
      if (resolved is ResolvedLibraryResult && resolved.units.isNotEmpty) {
        issues.addAll(syntacticErrorIssues(resolved, sourcePath: assetId.path));
      }

      // Read the `@RestageLibrary` capability version, surfacing the walk's own
      // diagnostics (malformed / reserved namespace) and failing on a
      // conflicting redeclaration rather than nondeterministic last-wins.
      final walk = walkRestageLibrary(barrel: library, barrelAssetId: assetId);
      for (final diagnostic in walk.diagnostics) {
        // Only ERROR-severity diagnostics fail the build; a walk WARNING (e.g.
        // `restageLibraryForeignWidget` — a re-exported `@RestageWidget` this
        // per-file catalog walk never picks up anyway) is surfaced non-fatally,
        // so a legitimate multi-package barrel is not over-rejected.
        if (diagnostic.severity == DiagnosticSeverity.error) {
          issues.add(
            Issue(
              code: IssueCode.missingAnnotationField,
              message: diagnostic.message,
              location: diagnostic.location,
            ),
          );
        } else {
          log.warning(diagnostic.message);
        }
      }
      final declaration = walk.declaration;
      if (declaration != null) {
        if (capabilityVersions.containsKey(declaration.library) &&
            capabilityVersions[declaration.library] !=
                declaration.capabilityVersion) {
          issues.add(
            Issue(
              code: IssueCode.duplicateId,
              message: 'conflicting @RestageLibrary capabilityVersion for '
                  '"${declaration.library.namespace}": '
                  '${capabilityVersions[declaration.library]} vs '
                  '${declaration.capabilityVersion}.',
              location: assetId.path,
            ),
          );
        }
        capabilityVersions[declaration.library] = declaration.capabilityVersion;
      }
    }

    // Cross-file `(library, name)` duplicate detection — `visitRestageWidgets`
    // only catches within-file duplicates.
    final byKey = <String, List<A2uiWidgetElement>>{};
    for (final w in widgets) {
      byKey
          .putIfAbsent('${w.entry.library.namespace}#${w.entry.name}', () => [])
          .add(w);
    }
    for (final dup in byKey.entries.where((e) => e.value.length > 1)) {
      issues.add(
        Issue(
          code: IssueCode.duplicateWidgetName,
          message: 'Multiple @RestageWidget classes share name in ${dup.key}: '
              '${dup.value.map((w) => w.entry.flutterType).join(', ')}.',
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

    // Deterministic emit order — by (library namespace, name) — so the
    // generated catalog is byte-stable regardless of asset discovery order.
    widgets.sort((a, b) {
      final byLib =
          a.entry.library.namespace.compareTo(b.entry.library.namespace);
      return byLib != 0 ? byLib : a.entry.name.compareTo(b.entry.name);
    });

    return (widgets: widgets, capabilityVersions: capabilityVersions);
  }

  /// Builds the merged A2UI catalog: the BUILT-IN slice of [loadMergedCatalog]
  /// (the committed built-in catalogs — never the customer's `catalog.json`, so
  /// the walk is the single authoritative customer source) plus the customer
  /// widgets from [walk], with each customer library carrying its declared
  /// `capabilityVersion`.
  Future<Catalog> _mergedCatalog(
    BuildStep buildStep,
    _CustomerWalk walk,
  ) async {
    final loaded = await loadMergedCatalog(buildStep);
    bool isBuiltIn(WidgetLibrary library) =>
        WidgetLibrary.builtInByNamespace(library.namespace) != null;

    final customerLibraries = <WidgetLibrary>{
      for (final w in walk.widgets) w.entry.library,
    };

    return Catalog(
      schemaVersion: loaded.schemaVersion,
      generatedAt: loaded.generatedAt,
      flutterVersion: loaded.flutterVersion,
      libraries: {
        for (final entry in loaded.libraries.entries)
          if (isBuiltIn(entry.key)) entry.key: entry.value,
        for (final library in customerLibraries)
          library: LibraryInfo(
            version: _customerLibraryVersion,
            capabilityVersion: walk.capabilityVersions[library],
          ),
      },
      widgets: [
        ...loaded.widgets.where((w) => isBuiltIn(w.library)),
        for (final w in walk.widgets) w.entry,
      ],
      structuredTypes:
          loaded.structuredTypes.where((s) => isBuiltIn(s.library)).toList(),
      unions: loaded.unions.where((u) => isBuiltIn(u.library)).toList(),
      designTokens:
          loaded.designTokens.where((t) => isBuiltIn(t.library)).toList(),
      // Built-in compat rules only — symmetric with the widget filter, so a
      // customer catalog.json (read by loadMergedCatalog) cannot leak compat
      // rules referencing customer widgets the walk re-sources here.
      compatRules: loaded.compatRules
          ?.where(
            (r) =>
                WidgetLibrary.builtInByNamespace(r.affectedRef.library) != null,
          )
          .toList(),
    );
  }
}

/// The customer-widget walk result: the `(WidgetEntry, ClassElement)` pairs the
/// seam-assembly + emitter consume, and each contributing library's declared
/// `@RestageLibrary(capabilityVersion:)` (`null` when undeclared — the emitter
/// fails loud if such a library contributes components).
typedef _CustomerWalk = ({
  List<A2uiWidgetElement> widgets,
  Map<WidgetLibrary, int?> capabilityVersions,
});
