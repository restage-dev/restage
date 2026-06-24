import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/compat_rule.dart';
import 'package:rfw_catalog_schema/src/design_token.dart';
import 'package:rfw_catalog_schema/src/library_info.dart';
import 'package:rfw_catalog_schema/src/structured_entry.dart';
import 'package:rfw_catalog_schema/src/union_entry.dart';
import 'package:rfw_catalog_schema/src/widget_entry.dart';
import 'package:rfw_catalog_schema/src/widget_library.dart';

/// The complete generated catalog.
///
/// Authored as `kRegistry` in each curated library's `lib/registry.dart`,
/// emitted to `lib/src/widget_catalog/catalog.json` by the catalog
/// builder, and consumed by code-generation (build-time validation) and
/// the SDK runtime (widget registration).
///
/// A consumer typically obtains a catalog by decoding shipped JSON, then
/// looks entries up by name within a library:
///
/// ```dart
/// final Catalog catalog = decodeCatalog(catalogJson);
/// final button = catalog.findByName('FilledButton', WidgetLibrary.material);
/// ```
///
/// **Schema versions.** This type models the current canonical schema. JSON
/// inputs without canonical wire IDs are rejected by production decoders.
@immutable
final class Catalog {
  /// Const constructor.
  const Catalog({
    required this.schemaVersion,
    required this.generatedAt,
    required this.libraries,
    required this.widgets,
    this.structuredTypes = const [],
    this.unions = const [],
    this.designTokens = const [],
    this.flutterVersion,
    this.compatRules,
  });

  /// Catalog schema version.
  final int schemaVersion;

  /// ISO-8601 UTC timestamp identifying when the catalog was generated.
  final String generatedAt;

  /// Per-library metadata, keyed by [WidgetLibrary]. Equality is
  /// namespace-based — a typed subclass and `WidgetLibrary.custom(...)`
  /// carrying the same namespace resolve to the same entry.
  final Map<WidgetLibrary, LibraryInfo> libraries;

  /// All widget entries across all libraries.
  final List<WidgetEntry> widgets;

  /// All structured (value-type) entries. Empty when the catalog declares
  /// no structured types.
  final List<StructuredEntry> structuredTypes;

  /// All discriminated-union entries. Empty when the catalog declares no
  /// unions.
  final List<UnionEntry> unions;

  /// All design tokens. Empty when the catalog declares no design tokens.
  final List<DesignTokenEntry> designTokens;

  /// Flutter SDK version captured at generation. Optional; recorded
  /// where the catalog producer can determine it.
  final String? flutterVersion;

  /// Emitted by the diff tool; consumed by the backend forwarding
  /// table at blob decode time. `null` for catalogs that haven't been
  /// diff-tooled (e.g. fresh emissions outside a release flow).
  final List<CompatRule>? compatRules;

  /// The catalog *content* version — the maximum [WidgetEntry.sinceVersion]
  /// over all widgets, floored at [kBaselineCatalogVersion].
  ///
  /// Derived (never stored) so it cannot drift from the entries it
  /// summarizes. An empty catalog reports the baseline. Delegates to the
  /// single canonical [contentVersionOf] formula so every content-version
  /// derivation in the toolchain shares one source of truth.
  int get contentVersion => contentVersionOf(widgets);

  /// Find a widget entry by name within a specific library. Returns
  /// `null` if not present. Names are unique within a library, not
  /// across libraries.
  WidgetEntry? findByName(String name, WidgetLibrary library) {
    for (final w in widgets) {
      if (w.name == name && w.library == library) return w;
    }
    return null;
  }

  /// All widgets belonging to a specific library.
  List<WidgetEntry> widgetsIn(WidgetLibrary library) =>
      widgets.where((w) => w.library == library).toList(growable: false);

  /// All structured-type entries belonging to a specific library.
  List<StructuredEntry> structuredTypesIn(WidgetLibrary library) =>
      structuredTypes
          .where((s) => s.library == library)
          .toList(growable: false);

  /// All discriminated-union entries belonging to a specific library.
  List<UnionEntry> unionsIn(WidgetLibrary library) =>
      unions.where((u) => u.library == library).toList(growable: false);

  /// All design-token entries belonging to a specific library.
  List<DesignTokenEntry> designTokensIn(WidgetLibrary library) =>
      designTokens.where((t) => t.library == library).toList(growable: false);
}
