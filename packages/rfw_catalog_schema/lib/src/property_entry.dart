import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/dart_const_value.dart';
import 'package:rfw_catalog_schema/src/default_value_source.dart';
import 'package:rfw_catalog_schema/src/deprecation_info.dart';
import 'package:rfw_catalog_schema/src/native_decompose.dart';
import 'package:rfw_catalog_schema/src/property_metadata.dart';
import 'package:rfw_catalog_schema/src/property_type.dart';
import 'package:rfw_catalog_schema/src/restage_constraints.dart';
import 'package:rfw_catalog_schema/src/validation_expr.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// One property on a catalog widget entry.
///
/// Identity is [wireId] — library-scoped, monotonically allocated, and
/// independent of property name. Renames preserve the wire ID.
///
/// The canonical default-value source is [defaultSource]. The legacy
/// [defaultValue] is a computed projection of it — a literal default reads
/// back through [defaultValue] without being stored twice, so the two can
/// never contradict each other. A [defaultBrandToken] is the exception: it
/// comes from a separate brand-token curation map and is not a
/// [DefaultValueSource], so on a built entry it never co-occurs with a
/// [defaultSource] (a producer convention, not a schema invariant). The
/// authoring surfaces accept at most one defaulting strategy as input.
/// Producers should treat [defaultSource] as the canonical surface for
/// literal / token-reference / theme-binding / Flutter-ctor defaults.
@immutable
final class PropertyEntry {
  /// Const constructor.
  const PropertyEntry({
    required this.wireId,
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
    this.defaultBrandToken,
    this.synthetic,
    this.positional = false,
    this.enumType,
    this.widgetType,
    this.callbackSignature,
    this.defaultSource,
    this.constructorNullable = false,
    this.constructorDefault,
    this.mutuallyExclusiveWith,
    this.requiresAncestor,
    this.category,
    this.priority,
    this.validationRule,
    this.constraints = RestageConstraints.empty,
    this.deprecated,
    this.structuredRef,
    this.valueShape,
  });

  /// Stable wire identity for this property. Library-scoped — two
  /// properties in the same library never share a wire ID even across
  /// widgets. Identity is independent of [name].
  final WireId wireId;

  /// The constructor parameter / field name. Advisory; identity is
  /// [wireId].
  final String name;

  /// Catalog property type, inferred from the field's static Dart type.
  final PropertyType type;

  /// Human-readable description (from `@RestageProperty.description`).
  final String description;

  /// Whether the property is required at construction.
  final bool required;

  /// Legacy literal default value — a computed projection of
  /// [defaultSource]: the value of a [LiteralDefault] source, or `null` for
  /// any other source kind (or no source). Retained as a read accessor
  /// because the current code generator still consults this field; it is
  /// derived, never stored, so it cannot contradict [defaultSource]. Not
  /// part of the canonical wire shape — the codec serializes [defaultSource]
  /// only.
  Object? get defaultValue => switch (defaultSource) {
        LiteralDefault(:final value) => value,
        _ => null,
      };

  /// Legacy brand-token default — an independent legacy field sourced from
  /// the brand-token curation map, naming a token the runtime resolves via
  /// the theme. Unlike [defaultValue], it is not a [DefaultValueSource]; on
  /// a built entry it never co-occurs with a [defaultSource] (a producer
  /// convention — brand tokens are curated onto params that carry no
  /// resolvable literal default — rather than a schema invariant). Like
  /// [defaultValue], not serialized on the wire (the codec emits
  /// [defaultSource]). `null` when no brand-token default applies.
  final String? defaultBrandToken;

  /// When non-null, marks this property as a synthetic catalog name
  /// that does not map directly to a constructor parameter. The value
  /// identifies the translation strategy the codegen applies when
  /// constructing the underlying widget.
  ///
  /// Recognized strategies:
  ///
  /// * `'iconData'` — the property's `int` codepoint value wraps as
  ///   `IconData(value, fontFamily: 'MaterialIcons')` and is passed to
  ///   the widget's `icon` parameter (not the catalog property name).
  /// * `'gateOnPressed'` — the property's `bool` value gates the
  ///   widget's `onPressed` handler. When true, `onPressed: null` is
  ///   emitted instead of binding the handler from the data source.
  ///
  /// Properties with a non-null `synthetic` are skipped by the simple
  /// scalar emitter; the codegen surface that knows the strategy
  /// handles them.
  final String? synthetic;

  /// When `true`, the codegen emits this property's value as a
  /// positional constructor argument rather than a named one. Used for
  /// widgets whose first ctor arg is positional — e.g.
  /// `Image.network(String src, {...})` (catalog property `'url'`)
  /// and `Icon(IconData? icon, {...})` (catalog property
  /// `'iconCodepoint'` with the `'iconData'` synthetic). Catalog
  /// property names for positional values still document the semantic
  /// purpose; the codegen uses them to look up the value but does not
  /// emit them as `name:` prefixes in the generated code.
  ///
  /// Multiple positional properties on one entry emit in catalog
  /// declaration order, before any named arguments.
  final bool positional;

  /// When [type] is [PropertyType.enumValue], names the Dart enum
  /// declaration this property carries — e.g. `'BoxFit'`, `'TextAlign'`,
  /// `'MainAxisAlignment'`. Used by the codegen surface to emit
  /// `RestageDecoders.enumByName<T>(T.values, source, path)` and resolve
  /// the [defaultValue] string (when set) against `T.values`. The named
  /// enum must be reachable from the per-library Flutter import the
  /// codegen emits.
  ///
  /// `null` for non-enum properties. Required when [type] is
  /// [PropertyType.enumValue]; the codegen rejects enum-typed entries
  /// missing this field.
  final String? enumType;

  /// When [type] is [PropertyType.widget], names the ctor parameter
  /// type when it isn't simply `Widget?` — e.g. `'PreferredSizeWidget'`
  /// for a `Scaffold.appBar` slot. The codegen emits a downcast
  /// `as <widgetType>` (or `as <widgetType>?` for optional slots) on the
  /// `source.child(...)` / `source.optionalChild(...)` call so the
  /// result type-checks against the ctor parameter.
  ///
  /// `null` (the default) means the slot accepts plain `Widget` /
  /// `Widget?` and no cast is emitted.
  final String? widgetType;

  /// When [type] is [PropertyType.event], names the typed Dart callback
  /// signature this slot accepts when it isn't simply `VoidCallback` —
  /// e.g. `'ValueChanged<bool>'` for `Switch.onChanged` /
  /// `Checkbox.onChanged`. The codegen emits
  /// `source.handler<<signature>>(path, (trigger) => (...) => trigger(...))`
  /// instead of the void-handler shortcut.
  ///
  /// Recognized signature shapes today: `'ValueChanged<T>'` for any
  /// scalar `T` (`bool`, `int`, `double`, `String`, including a nullable
  /// `T?`), and `'ValueChanged<List<E>>'` for a list-valued settled
  /// selection (e.g. a multi-select firing its whole selection as one
  /// `List<String>` over the dynamic-list wire). The codegen rejects
  /// unsupported signatures at build time so a typo surfaces loudly
  /// rather than degrading silently.
  ///
  /// `null` (the default) means the slot is a `VoidCallback?` and the
  /// codegen emits the `source.voidHandler(...)` shortcut.
  final String? callbackSignature;

  /// Discriminated default source — `LiteralDefault`,
  /// `TokenRefDefault`, `ThemeBindingDefault`, or `FlutterCtorDefault`.
  /// `null` means the catalog makes no claim about the default. This is
  /// the canonical default surface for literal / token-reference /
  /// theme-binding / Flutter-ctor defaults. The legacy [defaultValue] is a
  /// computed projection of it; a [defaultBrandToken] (out of scope for
  /// [DefaultValueSource]) never co-occurs with it.
  final DefaultValueSource? defaultSource;

  /// Whether the constructor-effective Dart input admits null.
  final bool constructorNullable;

  /// Exact source-derived Dart constructor default, independent of preview
  /// metadata in [defaultSource]. `null` means the formal declares no default.
  final DartConstValue? constructorDefault;

  /// Other properties on the same widget this one is mutually exclusive
  /// with. References by wire ID — property renames don't churn the
  /// relation. `null` / empty when no exclusivity rule applies.
  final List<WireId>? mutuallyExclusiveWith;

  /// Ancestor widget the property requires to be present in the host
  /// tree (e.g. a `Material`-required leaf widget requires a Material
  /// ancestor). Named by display label; the editor surfaces a warning
  /// when violated. `null` when no ancestor is required.
  final String? requiresAncestor;

  /// Coarse editor grouping (layout / style / behavior / accessibility
  /// / data). Drives inspector section placement.
  final PropertyCategory? category;

  /// Editor priority (primary / common / advanced). Drives inspector
  /// surface order.
  final PropertyPriority? priority;

  /// Validation rule applied to authored values.
  final ValidationExpr? validationRule;

  /// Typed JSON-Schema-shaped constraints applied to this property.
  ///
  /// Empty by default. Non-empty typed constraints and [validationRule] are
  /// mutually exclusive at production codec boundaries.
  final RestageConstraints constraints;

  /// Two-layer deprecation status (source + catalog lifecycle).
  final DeprecationInfo? deprecated;

  /// Target structured entry when [type] is [PropertyType.structured].
  /// `null` for any other type. The wire ID is library-scoped; the
  /// library namespace in the [WireIdRef] is the namespace of the
  /// target structured entry, not necessarily the namespace of the
  /// owning widget entry.
  final WireIdRef? structuredRef;

  /// Native semantic shape for this property value.
  final CatalogValueShape? valueShape;
}
