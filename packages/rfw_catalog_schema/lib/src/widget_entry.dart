import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/decomposition_recipe.dart';
import 'package:rfw_catalog_schema/src/deprecation_info.dart';
import 'package:rfw_catalog_schema/src/property_entry.dart';
import 'package:rfw_catalog_schema/src/stability.dart';
import 'package:rfw_catalog_schema/src/widget_library.dart';
import 'package:rfw_catalog_schema/src/widget_metadata.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// The baseline catalog *content* version — the version every widget is
/// considered to have existed at when the catalog content line begins.
///
/// The content version is a monotonic integer that tracks *which widgets and
/// capabilities exist*. It is a distinct axis from the catalog *format*
/// version (which tracks the JSON structure) and from a package's published
/// semantic version. A widget's [WidgetEntry.sinceVersion] is the content
/// version that introduced (or last capability-changed) it; new or changed
/// widgets carry a higher value.
const int kBaselineCatalogVersion = 1;

/// The content version of a set of widget entries — the maximum
/// [WidgetEntry.sinceVersion] over [widgets], floored at
/// [kBaselineCatalogVersion] (so an empty set reports the baseline, never
/// zero).
///
/// This is the **single canonical content-version formula**. The catalog's
/// `contentVersion` delegates to it, the generated per-library
/// `k…CatalogContentVersion` constants are derived from it, and any other
/// content-version derivation must reuse it rather than recompute. One formula
/// means independent derivations cannot silently drift apart.
int contentVersionOf(Iterable<WidgetEntry> widgets) {
  var max = kBaselineCatalogVersion;
  for (final widget in widgets) {
    if (widget.sinceVersion > max) max = widget.sinceVersion;
  }
  return max;
}

/// One widget entry in the catalog.
///
/// Identity is [wireId] — library-scoped, monotonically allocated. Names
/// and source paths ([flutterType]) are advisory labels that may shift
/// via rename events; the wire ID does not.
@immutable
final class WidgetEntry {
  /// Const constructor.
  const WidgetEntry({
    required this.wireId,
    required this.name,
    required this.library,
    required this.category,
    required this.description,
    required this.flutterType,
    required this.childrenSlot,
    required this.properties,
    this.decomposes = const [],
    this.sinceVersion = kBaselineCatalogVersion,
    this.deprecatedSince,
    this.stability = Stability.volatile,
    this.deprecated,
  }) : assert(
          sinceVersion >= kBaselineCatalogVersion,
          'sinceVersion must be at or above the baseline content version',
        );

  /// Stable wire identity for this widget. Library-scoped and
  /// monotonically allocated against the library's `wire_ids.events.jsonl`
  /// log. Renames or source restructures do not change this value.
  final WireId wireId;

  /// Catalog key (e.g. `'FilledButton'`). Advisory; identity is
  /// [wireId].
  final String name;

  /// Sibling library this widget belongs to.
  final WidgetLibrary library;

  /// Sub-grouping within the library.
  final WidgetCategory category;

  /// Human-readable description.
  final String description;

  /// Canonical type identifier in `'<package URI>#<class name>'` format —
  /// e.g. `'package:flutter/src/widgets/container.dart#Container'`.
  ///
  /// Advisory provenance, not identity. Renames or source restructures
  /// shift [flutterType] without affecting wire references; consumers
  /// must not derive identity-typed references from this field.
  final String flutterType;

  /// Children slot — none / single / list.
  final ChildrenSlot childrenSlot;

  /// Properties exposed by this widget. Includes decomposed flats — a
  /// widget that accepts a `TextStyle` constructor argument lists the
  /// flattened properties (`fontSize`, `fontWeight`, `color`) here, with
  /// the corresponding [DecompositionRecipe] in [decomposes].
  final List<PropertyEntry> properties;

  /// Structured parameter types this widget accepts as constructor
  /// arguments and how they flatten to entries in [properties].
  ///
  /// Empty for widgets that accept only flat scalar arguments (e.g.
  /// `SizedBox`). One recipe per structured argument
  /// (`TextStyle` on `Text`, `ButtonStyle` on `FilledButton`, etc.).
  final List<DecompositionRecipe> decomposes;

  /// Catalog *content* version that introduced (or last capability-changed)
  /// this widget. Defaults to [kBaselineCatalogVersion]. A surface's required
  /// content version is the maximum [sinceVersion] over the widgets it uses,
  /// so a client that ships an older catalog can be told, before render,
  /// whether it can faithfully display the surface.
  ///
  /// Content versions are cumulative: a widget present at version N stays
  /// renderable at every version greater than N. An incompatible change
  /// allocates a new [wireId] and [sinceVersion] rather than mutating an
  /// existing entry.
  ///
  /// **The line is GLOBAL across the built-in libraries, not per library.** A
  /// client advertises one installed content version — the maximum over every
  /// built-in library it ships — and the pre-render check compares a surface's
  /// floor against that single number. So a new widget must be stamped above
  /// the highest [sinceVersion] anywhere in the built-in set at the time it
  /// lands, not above its own library's highest. Stamp it at its library's
  /// next value and the floor it produces is one an older client already
  /// clears on the strength of a *different* library's version: the check
  /// passes, and the widget is not there to render. The floor fails open, and
  /// it is the only thing standing between a new widget and a client that
  /// cannot draw it.
  final int sinceVersion;

  /// Legacy plain-string deprecation marker — the catalog version where
  /// this widget became deprecated. Superseded by the structured
  /// [deprecated]; not part of the canonical wire shape (the codec
  /// serializes [deprecated]). Retained as an in-memory field. `null` for
  /// active widgets.
  final String? deprecatedSince;

  /// Stability tier. [Stability.volatile] (default) for entries that may
  /// change shape across releases; [Stability.stable] for entries
  /// promoted via `@StableWidget` or a maintainer commitment.
  final Stability stability;

  /// Two-layer deprecation status (source-level `@Deprecated` plus
  /// catalog-lifecycle `deprecate` event).
  final DeprecationInfo? deprecated;
}
