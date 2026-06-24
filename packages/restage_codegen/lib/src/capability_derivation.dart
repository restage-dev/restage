import 'package:meta/meta.dart';
import 'package:restage_codegen/src/catalog_loader.dart' show findWidgetsByName;
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart'
    show CapabilityManifest, LibraryRequirement;
// Only the parsed-model node types are needed here; `WidgetLibrary` is the
// catalog namespace type from `rfw_catalog_schema`, not RFW's runtime
// widget-library type that this sublibrary also exports.
import 'package:restage_shared/rfw_formats.dart'
    show
        ConstructorCall,
        Loop,
        RemoteWidgetLibrary,
        Switch,
        WidgetBuilderDeclaration;
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
  const CapabilityDerivationResult({this.manifest, this.issues = const []});

  /// The derived manifest, or `null` when derivation failed (see [issues]).
  final CapabilityManifest? manifest;

  /// Diagnostics raised during derivation; empty on success.
  final List<Issue> issues;
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
  Catalog catalog,
) {
  final referenced = <WidgetEntry>[];
  final ambiguous = <String>{};
  final localNames = {for (final widget in surface.widgets) widget.name};
  for (final widget in surface.widgets) {
    _collectReferences(widget.root, catalog, localNames, referenced, ambiguous);
  }

  // Fail closed on a name that resolves across more than one library (a custom
  // library shadowing a built-in, or two customs colliding). The runtime
  // resolves the bare name by import order; the derivation resolves by catalog
  // priority, so the two can disagree and a wrong-library stamp could fail open
  // (under-stamp the floor or drop a required library). Refuse to stamp rather
  // than guess — the author must rename so the name resolves to one library.
  if (ambiguous.isNotEmpty) {
    final issues = <Issue>[
      for (final name in ambiguous.toList()..sort())
        Issue(
          code: IssueCode.ambiguousWidgetName,
          message: "The widget name '$name' resolves to more than one "
              'library (${_librariesForName(catalog, name).join(', ')}), so '
              'its capability floor cannot be derived. Rename the custom '
              'widget so it does not shadow a built-in (or another library).',
          location: name,
        ),
    ];
    return CapabilityDerivationResult(issues: issues);
  }

  var builtInFloor = kBaselineCatalogVersion;
  final customLibraries = <WidgetLibrary>{};
  for (final entry in referenced) {
    if (_isBuiltIn(entry.library)) {
      if (entry.sinceVersion > builtInFloor) builtInFloor = entry.sinceVersion;
    } else {
      customLibraries.add(entry.library);
    }
  }
  // Canonicalize by namespace so BOTH the requirements and the fail-when-
  // referenced diagnostics are deterministic — independent of the order the
  // surface happened to reference the libraries in. (`CapabilityManifest`
  // re-sorts the requirements too; this also pins the issue order.)
  final sortedCustomLibraries = customLibraries.toList()
    ..sort((a, b) => a.namespace.compareTo(b.namespace));

  final issues = <Issue>[];
  final requiredLibraries = <LibraryRequirement>[];
  for (final library in sortedCustomLibraries) {
    final capabilityVersion = catalog.libraries[library]?.capabilityVersion;
    if (capabilityVersion == null) {
      issues.add(
        Issue(
          code: IssueCode.customLibraryMissingCapabilityVersion,
          message: 'The surface references a widget from custom library '
              "'${library.namespace}', but that library declares no capability "
              'version. Add `capabilityVersion:` to its @RestageLibrary so the '
              'delivery-time capability floor can be derived (a monotonic '
              'integer, not your pub package version).',
          location: library.namespace,
        ),
      );
      continue;
    }
    requiredLibraries.add(
      LibraryRequirement(
        namespace: library.namespace,
        minVersion: capabilityVersion,
      ),
    );
  }

  if (issues.isNotEmpty) {
    return CapabilityDerivationResult(issues: issues);
  }

  return CapabilityDerivationResult(
    manifest: CapabilityManifest(
      builtInFloor: builtInFloor,
      requiredLibraries: requiredLibraries,
    ),
  );
}

bool _isBuiltIn(WidgetLibrary library) =>
    WidgetLibrary.builtInByNamespace(library.namespace) != null;

/// The sorted, de-duplicated namespaces a widget [name] resolves to in
/// [catalog] — used to name the colliding libraries in an ambiguity diagnostic.
List<String> _librariesForName(Catalog catalog, String name) =>
    findWidgetsByName(catalog, name)
        .map((w) => w.library.namespace)
        .toSet()
        .toList()
      ..sort();

/// Walks [node], appending the resolved [WidgetEntry] for every non-local
/// `ConstructorCall` to [out]. Mirrors `validateModelAgainstCatalog`'s walk so
/// the derivation sees exactly the widget references the build-time gate does.
void _collectReferences(
  Object? node,
  Catalog catalog,
  Set<String> localNames,
  List<WidgetEntry> out,
  Set<String> ambiguous,
) {
  if (node is ConstructorCall) {
    // A library-local `widget` definition resolves within the surface — it is
    // not a catalog reference. Its body is walked separately as its own
    // library widget, so its catalog usage is still counted.
    if (!localNames.contains(node.name)) {
      final candidates = findWidgetsByName(catalog, node.name);
      if (candidates.isNotEmpty) {
        // A name resolving to more than one LIBRARY is ambiguous (a shadow).
        // Multiple candidates from the SAME library are a catalog-integrity
        // concern guarded elsewhere; here only a cross-library split blocks the
        // stamp. (`WidgetLibrary` overrides equality, so the set dedups by
        // library identity.)
        final libraries = candidates.map((c) => c.library).toSet();
        if (libraries.length > 1) {
          ambiguous.add(node.name);
        } else {
          out.add(candidates.first);
        }
      }
    }
    for (final argEntry in node.arguments.entries) {
      _collectReferences(argEntry.value, catalog, localNames, out, ambiguous);
    }
  } else if (node is List) {
    for (final child in node) {
      _collectReferences(child, catalog, localNames, out, ambiguous);
    }
  } else if (node is Switch) {
    for (final output in node.outputs.values) {
      _collectReferences(output, catalog, localNames, out, ambiguous);
    }
  } else if (node is Loop) {
    _collectReferences(node.output, catalog, localNames, out, ambiguous);
  } else if (node is WidgetBuilderDeclaration) {
    _collectReferences(node.widget, catalog, localNames, out, ambiguous);
  } else if (node is Map) {
    for (final value in node.values) {
      _collectReferences(value, catalog, localNames, out, ambiguous);
    }
  }
  // Remaining node types (literal scalars, references, event handlers) carry no
  // catalog widget references.
}
