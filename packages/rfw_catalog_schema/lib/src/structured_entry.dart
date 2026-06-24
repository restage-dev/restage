import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/default_value_source.dart';
import 'package:rfw_catalog_schema/src/deprecation_info.dart';
import 'package:rfw_catalog_schema/src/factory_variant.dart';
import 'package:rfw_catalog_schema/src/native_decompose.dart';
import 'package:rfw_catalog_schema/src/property_metadata.dart';
import 'package:rfw_catalog_schema/src/property_type.dart';
import 'package:rfw_catalog_schema/src/stability.dart';
import 'package:rfw_catalog_schema/src/widget_library.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// One structured (value type) entry in the catalog.
///
/// Examples: `BoxDecoration`, `LinearGradient`, `TextStyle`,
/// `BorderRadius`, `EdgeInsets`. Each structured type carries its own
/// field list plus a set of [FactoryVariant]s describing the ways a
/// value can be authored in source.
@immutable
final class StructuredEntry {
  /// Const constructor.
  const StructuredEntry({
    required this.wireId,
    required this.name,
    required this.library,
    required this.description,
    required this.sourceType,
    required this.fields,
    required this.variants,
    this.stability = Stability.volatile,
    this.deprecated,
  });

  /// Wire identity for this structured entry.
  final WireId wireId;

  /// Advisory display name (`'BoxDecoration'`, `'LinearGradient'`).
  /// Identity is [wireId]; name may shift via `rename` events.
  final String name;

  /// Library this entry lives in.
  final WidgetLibrary library;

  /// Human-readable description.
  final String description;

  /// Advisory provenance: resolved Flutter / customer type for debug /
  /// introspection (`<library URI>#<class name>`). **Not identity.**
  /// Renames and source restructures may shift this without producing
  /// wire-compat events.
  final String sourceType;

  /// Structured fields. Each field has its own wire ID (a `p*` ID drawn
  /// from the library's property counter — the same counter widget
  /// properties use).
  final List<StructuredField> fields;

  /// Factory variants describing the ways a value of this structured
  /// type can be authored in source. At least one variant (typically
  /// the canonical unnamed constructor) is expected; types with only
  /// `constValue` instances (e.g. an enum-like static-const wrapper)
  /// may omit the constructor variant.
  final List<FactoryVariant> variants;

  /// Stability tier.
  final Stability stability;

  /// Lifecycle status.
  final DeprecationInfo? deprecated;
}

/// One field on a [StructuredEntry]. Same shape as `PropertyEntry`'s
/// declarative-compatible subset (no events, no widget slots).
@immutable
final class StructuredField {
  /// Const constructor.
  const StructuredField({
    required this.wireId,
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
    this.defaultSource,
    this.category,
    this.priority,
    this.deprecated,
    this.structuredRef,
    this.unionRef,
    this.valueShape,
  });

  /// Wire identity for this field. Drawn from the library's `p*`
  /// counter (shared with widget-level properties).
  final WireId wireId;

  /// Advisory display name (the source-level Dart field name).
  final String name;

  /// Catalog property type.
  final PropertyType type;

  /// Human-readable description.
  final String description;

  /// Whether the field is required at the structured type's
  /// canonical-constructor invocation.
  final bool required;

  /// How the runtime supplies this field's value when absent.
  final DefaultValueSource? defaultSource;

  /// Editor grouping for this field.
  final PropertyCategory? category;

  /// Editor priority for this field.
  final PropertyPriority? priority;

  /// Lifecycle status for this field.
  final DeprecationInfo? deprecated;

  /// Target structured entry when [type] is [PropertyType.structured].
  /// `null` for any other type. The wire ID is library-scoped; the
  /// library namespace in the [WireIdRef] is the namespace of the
  /// target structured entry, not necessarily the namespace of the
  /// owning structured entry.
  ///
  /// A `structured`-typed field carries exactly one of [structuredRef]
  /// or [unionRef]: [structuredRef] when the field resolves to a single
  /// concrete structured entry, [unionRef] when it resolves to a
  /// discriminated union of concrete entries.
  final WireIdRef? structuredRef;

  /// Target union entry when the field is typed against a discriminated
  /// union of structured entries (e.g. a `Gradient` or `ShapeBorder`
  /// field). `null` when the field resolves to a single concrete
  /// structured entry — see [structuredRef] — or to a non-structured
  /// type.
  final WireIdRef? unionRef;

  /// Native semantic shape for this structured-field value.
  final CatalogValueShape? valueShape;
}
