import 'package:meta/meta.dart';
import 'package:restage_codegen/src/catalog_loader.dart' show findWidgetsByName;
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart'
    show CapabilityManifest, deriveSurfaceCapability;
import 'package:restage_shared/rfw_formats.dart' show RemoteWidgetLibrary;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The outcome of deriving a surface's [CapabilityManifest] from the catalog.
///
/// On success [manifest] is non-null and [issues] is empty. On failure
/// [manifest] is `null` and [issues] carries the fatal diagnostic(s) — the
/// only fatal case is a surface that references a widget from a custom library
/// whose catalog metadata declares no capability version (fail-when-referenced;
/// the library must declare `@RestageLibrary(capabilityVersion: …)`).
@immutable
final class CapabilityDerivationResult {
  /// Creates a result. A non-null [manifest] always pairs with empty [issues].
  const CapabilityDerivationResult({
    this.manifest,
    this.issues = const [],
    this.referencedWidgets = const [],
  });

  /// The derived manifest, or `null` when derivation failed (see [issues]).
  final CapabilityManifest? manifest;

  /// Diagnostics raised during derivation; empty on success.
  final List<Issue> issues;

  /// The catalog widgets the surface references, deduplicated and ordered by
  /// `'<library namespace>:<name>'` ascending. Empty on failure — a result
  /// that could not be stamped names nothing.
  final List<WidgetEntry> referencedWidgets;
}

/// Derives the [CapabilityManifest] a parsed [surface] requires, from the
/// source-derived [catalog].
///
/// The manifest has two independent axes:
///  * `builtInFloor` — the maximum `sinceVersion` over the **built-in**
///    widgets the surface references (the single built-in content-version
///    line), floored at [kBaselineCatalogVersion] when it uses no built-ins.
///  * `requiredLibraries` — one entry per **custom** library the surface
///    references, each carrying that library's declared capability version.
///
/// The walk mirrors the build-time catalog gate
/// (`validateModelAgainstCatalog`):
/// a `ConstructorCall` naming a library-local `widget` definition resolves
/// within the surface and is skipped (its body is still walked as its own
/// library widget); every other call is resolved by name against [catalog]
/// using the same priority-ordered first-hit the translator uses. A name with
/// no catalog match contributes nothing here — the gate already fails the build
/// for an unknown widget, so derivation does not re-diagnose it.
///
/// Fail-when-referenced: if the surface references a widget whose resolved
/// library is **custom** and that library's [Catalog.libraries] metadata has
/// no declared `capabilityVersion`, derivation fails with a fatal [Issue] and
/// returns a `null` manifest — a custom library must declare an explicit
/// monotonic capability version before a surface may depend on it.
CapabilityDerivationResult deriveCapabilityManifest(
  RemoteWidgetLibrary surface,
  Catalog catalog, {
  bool requiresSurfaceFeatureFloor = false,
}) {
  final derivation = deriveSurfaceCapability(
    surface,
    catalog,
    requiresSurfaceFeatureFloor: requiresSurfaceFeatureFloor,
  );

  // Fail closed on a name that resolves across more than one library (a custom
  // library shadowing a built-in, or two customs colliding). The runtime
  // resolves the bare name by import order; the derivation resolves by catalog
  // priority, so the two can disagree and a wrong-library stamp could fail open
  // (under-stamp the floor or drop a required library). Refuse to stamp rather
  // than guess — the author must rename so the name resolves to one library.
  if (derivation.ambiguousNames.isNotEmpty) {
    return CapabilityDerivationResult(
      issues: <Issue>[
        for (final name in derivation.ambiguousNames)
          Issue(
            code: IssueCode.ambiguousWidgetName,
            message: "The widget name '$name' resolves to more than one "
                'library (${_librariesForName(catalog, name).join(', ')}), so '
                'its capability floor cannot be derived. Rename the custom '
                'widget so it does not shadow a built-in (or another library).',
            location: name,
          ),
      ],
    );
  }

  if (derivation.unversionedLibraries.isNotEmpty) {
    return CapabilityDerivationResult(
      issues: <Issue>[
        for (final library in derivation.unversionedLibraries)
          Issue(
            code: IssueCode.customLibraryMissingCapabilityVersion,
            message: 'The surface references a widget from custom library '
                "'${library.namespace}', but that library declares no "
                'capability version. Add `capabilityVersion:` to its '
                '@RestageLibrary so the delivery-time capability floor can be '
                'derived (a monotonic integer, not your pub package version).',
            location: library.namespace,
          ),
      ],
    );
  }

  return CapabilityDerivationResult(
    manifest: CapabilityManifest(
      builtInFloor: derivation.builtInFloor,
      requiredLibraries: derivation.requiredLibraries,
    ),
    referencedWidgets: derivation.referencedWidgets,
  );
}

/// The sorted, de-duplicated namespaces a widget [name] resolves to in
/// [catalog] — used to name the colliding libraries in an ambiguity diagnostic.
List<String> _librariesForName(Catalog catalog, String name) =>
    findWidgetsByName(catalog, name)
        .map((w) => w.library.namespace)
        .toSet()
        .toList()
      ..sort();
