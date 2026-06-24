import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/native_decompose.dart';
import 'package:rfw_catalog_schema/src/property_entry.dart';
import 'package:rfw_catalog_schema/src/property_type.dart';
import 'package:rfw_catalog_schema/src/widget_entry.dart';
import 'package:rfw_catalog_schema/src/widget_metadata.dart';

/// Curation entry for one widget in a built-in library
/// (`restage_core` / `restage_material` / `restage_cupertino`).
///
/// The curation builder reads each entry from a list annotated with
/// `RestageBuiltinLibrary` and combines:
///
/// * **The Flutter class itself** — supplied as the type argument [T] —
///   from which most [PropertyEntry] fields derive automatically by
///   walking the constructor parameter list (name, type, dartdoc,
///   required-flag, literal default).
/// * **The fields on this curation entry** — design choices that cannot
///   be inferred from a constructor signature: the catalog [category],
///   event mapping ([fires]), native structured-type decomposition metadata
///   ([nativeDecomposes]), brand-token defaults ([brandTokens]), parameter
///   exclusions ([excludeParams]), synthetic catalog properties
///   ([synthetics]), and per-property overrides ([propertyOverrides]).
///
/// The type argument [T] should resolve to a `Widget` subclass at the
/// call site. The schema cannot enforce this constraint directly because
/// the host package is pure Dart and does not depend on Flutter; the
/// builder rejects non-Widget [T] at build time.
///
/// ## Constructor selection
///
/// By default, [T]'s unnamed canonical constructor is targeted. Set
/// [constructorName] to target a named constructor — e.g. `'network'`
/// for `Image.network`, `'tonal'` for `FilledButton.tonal`.
///
/// ## Catalog name
///
/// The resulting widget entry's name defaults to [T]'s class name
/// plus the capitalised [constructorName] when present (`FilledButton`
/// + `tonal` → `'FilledButtonTonal'`). Set [nameOverride] to suppress
/// the suffix
/// when only one constructor of the underlying class is curated and the
/// bare class name is preferable (e.g. `'Image'` for the lone
/// `Image.network` entry).
///
/// ## Example
///
/// ```dart
/// const BuiltinWidgetCuration<Text>(
///   category: WidgetCategory.decoration,
///   descriptionOverride: 'Static text with optional styling.',
///   propertyOverrides: {
///     'data': PropertyOverride(
///       description: 'The displayed text.',
///       positional: true,
///     ),
///     'color': PropertyOverride(defaultBrandToken: 'onBackground'),
///   },
///   nativeDecomposes: [kTextStyleNativeDecompose],
/// )
/// ```
@immutable
final class BuiltinWidgetCuration<T extends Object> {
  /// Const constructor.
  const BuiltinWidgetCuration({
    required this.category,
    this.constructorName,
    this.nameOverride,
    this.descriptionOverride,
    this.fires = const [],
    this.childrenSlot,
    this.deprecatedSince,
    this.minSchemaVersion = 1,
    this.sinceVersion = kBaselineCatalogVersion,
    this.excludeParams = const [],
    this.brandTokens = const {},
    this.nativeDecomposes = const [],
    this.synthetics = const [],
    this.propertyOverrides = const {},
  });

  /// Sub-grouping within the library (`paywall`, `layout`, `input`,
  /// `decoration`).
  final WidgetCategory category;

  /// Named-constructor segment when targeting a non-default constructor
  /// (e.g. `'network'` for `Image.network`). `null` selects the unnamed
  /// canonical constructor.
  final String? constructorName;

  /// Overrides the auto-derived widget entry name. Used when only one
  /// constructor of the underlying class is curated and the bare class
  /// name reads better than `ClassName + ConstructorName` (e.g.
  /// `'Image'` for the lone `Image.network` entry). `null` selects the
  /// auto-derived name.
  final String? nameOverride;

  /// Overrides the dartdoc-derived description. `null` keeps the
  /// inferred dartdoc description.
  final String? descriptionOverride;

  /// Events this widget can fire.
  final List<WidgetEventName> fires;

  /// Overrides the inferred [ChildrenSlot]. `null` infers from the
  /// constructor — a `child:` parameter selects [ChildrenSlot.single],
  /// a `children:` parameter selects [ChildrenSlot.list], otherwise
  /// [ChildrenSlot.none].
  final ChildrenSlot? childrenSlot;

  /// Marks the entry as deprecated since the named catalog version.
  /// `null` for active entries.
  final String? deprecatedSince;

  /// Catalog schema version this entry requires.
  final int minSchemaVersion;

  /// Catalog *content* version that introduced this widget — populates
  /// [WidgetEntry.sinceVersion] on the reflected entry. Defaults to
  /// [kBaselineCatalogVersion], so every existing curation stays at the
  /// baseline and emits no version bytes. A widget curated above the
  /// baseline floors only the surfaces that use it (the content-version
  /// capability contract); it does not touch any other entry.
  ///
  /// Distinct axis from [minSchemaVersion]: content version tracks *which
  /// widgets exist*; schema version tracks the catalog JSON structure.
  final int sinceVersion;

  /// Constructor parameter names to skip when deriving [PropertyEntry]
  /// entries — used for parameters the catalog does not surface, or
  /// that are replaced by a synthetic.
  final List<String> excludeParams;

  /// Brand-token defaults keyed by constructor parameter name. The
  /// value populates the resulting [PropertyEntry.defaultBrandToken]
  /// field.
  final Map<String, String> brandTokens;

  /// Native structured-type decomposition metadata authored from source names.
  ///
  /// The generator resolves these curation-only names against analyzer data and
  /// lowers them into canonical v4 wire-ID refs, receiver-aware construction,
  /// field mappings, transforms, and factory-parameter metadata.
  final List<NativeDecompositionCuration> nativeDecomposes;

  /// Catalog properties that do not correspond 1:1 to a constructor
  /// parameter. Two shapes are supported, distinguished by whether
  /// [PropertyEntry.synthetic] is set:
  ///
  /// * **Translation-strategy synthetics** — `synthetic` non-null —
  ///   handled by the codegen's synthetic emitter. Examples:
  ///   `iconCodepoint` on `Icon` (wraps into `IconData`), `disabled`
  ///   gating a button's `onPressed` (`gateOnPressed`).
  /// * **Recipe-flat additions** — `synthetic` null — surfacing flat
  ///   properties hoisted out of native structured decomposition. Their names
  ///   are referenced by [nativeDecomposes]. Example: `fontSize`, `fontWeight`,
  ///   and `color` flats on `Text` paired with `TextStyle` native metadata.
  ///
  /// Each entry is appended verbatim to the resulting widget's
  /// property list.
  final List<PropertyEntry> synthetics;

  /// Per-parameter overrides applied on top of the inferred property
  /// surface. Keys are constructor parameter names.
  final Map<String, PropertyOverride> propertyOverrides;
}

/// Curation-only native decomposition metadata.
@immutable
final class NativeDecompositionCuration {
  /// Creates a native decomposition curation entry.
  const NativeDecompositionCuration({
    required this.structuredType,
    required this.targetArg,
    required this.construction,
    required this.fieldMappings,
    this.parameterMappings = const [],
  });

  /// Source type name of the structured value being reconstructed.
  final String structuredType;

  /// Widget constructor parameter receiving the reconstructed value.
  final String targetArg;

  /// Callable used to construct the structured value.
  final NativeFactoryCuration construction;

  /// Explicit mappings from structured fields to flat widget properties.
  final List<NativeFieldMappingCuration> fieldMappings;

  /// Explicit mappings from constructor parameters to flat widget properties.
  final List<NativeParameterMappingCuration> parameterMappings;
}

/// Curation-only callable identity for native construction/transforms.
@immutable
final class NativeFactoryCuration {
  /// Creates a result-structured-type constructor invocation.
  const NativeFactoryCuration.constructor({String? namedConstructor})
      : kind = NativeFactoryCurationKind.constructor,
        receiver = const ResultStructuredTypeReceiver(),
        memberName = namedConstructor;

  /// Creates a static invocation on the owning widget type.
  const NativeFactoryCuration.owningWidgetStatic(this.memberName)
      : kind = NativeFactoryCurationKind.staticMethod,
        receiver = const OwningWidgetTypeReceiver();

  /// Callable kind.
  final NativeFactoryCurationKind kind;

  /// Invocation receiver.
  final FactoryReceiver receiver;

  /// Named constructor or static method name.
  final String? memberName;
}

/// Callable category for [NativeFactoryCuration].
enum NativeFactoryCurationKind {
  /// Constructor on the result structured type.
  constructor,

  /// Static method.
  staticMethod,
}

/// Curation-only mapping from one structured field to one flat property.
@immutable
final class NativeFieldMappingCuration {
  /// Creates a native field mapping.
  const NativeFieldMappingCuration({
    required this.field,
    required this.property,
    this.transform = const NativeValueTransformCuration.identity(),
  });

  /// Structured source field/constructor-parameter name.
  final String field;

  /// Flat widget property name.
  final String property;

  /// Explicit value transform.
  final NativeValueTransformCuration transform;
}

/// Curation-only mapping from one factory parameter to one flat property.
@immutable
final class NativeParameterMappingCuration {
  /// Creates a native parameter mapping.
  const NativeParameterMappingCuration({
    required this.parameter,
    required this.property,
    this.transform = const NativeValueTransformCuration.identity(),
  });

  /// Constructor/static parameter label. Positional parameters use
  /// their index string.
  final String parameter;

  /// Flat widget property name.
  final String property;

  /// Explicit value transform.
  final NativeValueTransformCuration transform;
}

/// Curation-only value transform for a native field mapping.
@immutable
final class NativeValueTransformCuration {
  /// Identity transform.
  const NativeValueTransformCuration.identity()
      : kind = NativeValueTransformCurationKind.identity,
        resultStructuredType = null,
        invocation = null,
        argumentBindings = const [],
        itemTransform = null,
        scalarCoercion = null;

  /// Constructs another structured value from the flat property value.
  const NativeValueTransformCuration.constructVariant({
    required this.resultStructuredType,
    required this.invocation,
    required this.argumentBindings,
  })  : kind = NativeValueTransformCurationKind.constructVariant,
        itemTransform = null,
        scalarCoercion = null;

  /// Projects each list item through [itemTransform].
  const NativeValueTransformCuration.projectList({
    required this.itemTransform,
  })  : kind = NativeValueTransformCurationKind.projectList,
        resultStructuredType = null,
        invocation = null,
        argumentBindings = const [],
        scalarCoercion = null;

  /// Coerces a scalar value by named policy.
  const NativeValueTransformCuration.coerceScalar({
    required this.scalarCoercion,
  })  : kind = NativeValueTransformCurationKind.coerceScalar,
        resultStructuredType = null,
        invocation = null,
        argumentBindings = const [],
        itemTransform = null;

  /// Transform kind.
  final NativeValueTransformCurationKind kind;

  /// Source structured type produced by a construct-variant transform.
  final String? resultStructuredType;

  /// Callable used by a construct-variant transform.
  final NativeFactoryCuration? invocation;

  /// Argument bindings for construct-variant transforms.
  final List<NativeTransformArgumentBindingCuration> argumentBindings;

  /// Item transform for list projection.
  final NativeValueTransformCuration? itemTransform;

  /// Named scalar coercion.
  final String? scalarCoercion;
}

/// Native value transform kind.
enum NativeValueTransformCurationKind {
  /// Direct value mapping.
  identity,

  /// Construct a nested structured value.
  constructVariant,

  /// Project a list item-by-item.
  projectList,

  /// Coerce scalar values.
  coerceScalar,
}

/// Curation-only transform argument binding.
@immutable
final class NativeTransformArgumentBindingCuration {
  /// Creates a transform argument binding.
  const NativeTransformArgumentBindingCuration({
    required this.parameter,
    required this.source,
    required this.nullPolicy,
    required this.missingPolicy,
    this.literal,
    this.nestedTransform,
  });

  /// Callable parameter label. Positional parameters use their index string.
  final String parameter;

  /// Source for the argument value.
  final TransformArgumentSource source;

  /// Literal value when [source] is [TransformArgumentSource.literal].
  final Object? literal;

  /// Nested value transform when [source] is
  /// [TransformArgumentSource.nestedTransform].
  final NativeValueTransformCuration? nestedTransform;

  /// Null handling policy.
  final TransformNullPolicy nullPolicy;

  /// Missing-value handling policy.
  final TransformMissingPolicy missingPolicy;
}

/// Override for a single inferred [PropertyEntry] field.
///
/// All fields are nullable; a non-null value replaces the inferred
/// value, while `null` preserves it. Authored on
/// [BuiltinWidgetCuration.propertyOverrides], keyed by constructor
/// parameter name.
@immutable
final class PropertyOverride {
  /// Const constructor.
  ///
  /// Asserts that at most one of [defaultValue] or [defaultBrandToken]
  /// is provided — they are mutually exclusive defaulting strategies,
  /// matching `RestageProperty`'s rule.
  const PropertyOverride({
    this.name,
    this.type,
    this.description,
    this.required,
    this.defaultValue,
    this.defaultBrandToken,
    this.positional,
    this.enumType,
    this.widgetType,
    this.callbackSignature,
    this.firesAs,
  }) : assert(
          defaultValue == null || defaultBrandToken == null,
          'Use either defaultValue or defaultBrandToken, not both',
        );

  /// Replacement [PropertyEntry.name] — exposes the property under a
  /// different catalog name than the underlying constructor parameter.
  /// The override map's key still matches the param (so the reflector
  /// finds it); this field changes only what the emitted catalog entry
  /// surfaces. Used when the parameter name is awkward — e.g.
  /// `Image.network(String src)` exposes `name: 'url'`,
  /// `Text(String data)` exposes `name: 'text'`.
  final String? name;

  /// Replacement [PropertyType] for the inferred catalog type. Plays two
  /// distinct roles:
  ///
  /// - **Refines** an inferred type when the inference rule (e.g. `double`
  ///   → [PropertyType.real]) is less specific than the editor inspector
  ///   wants — a `Container.width` param is structurally a `double` but
  ///   semantically a length, and editor surfaces benefit from the
  ///   `length` hint. The codegen emitter treats `length` and `real`
  ///   identically, so for that case this field is editor-side cosmetic
  ///   only.
  /// - **Supplies** a type for a parameter whose Dart type the reflector
  ///   cannot mechanically infer and which is not a walkable structured
  ///   type. Without an override such a param is dropped with an
  ///   `unsupportedPropertyType` diagnostic; with one, the reflector
  ///   adopts the declared type and surfaces the param as a hand-modelled
  ///   slot (e.g. a recursive inline-span decoded by a bespoke decoder).
  ///
  /// `null` keeps the inferred type.
  final PropertyType? type;

  /// Replacement [PropertyEntry.description]. `null` keeps the
  /// dartdoc-derived description.
  final String? description;

  /// Replacement [PropertyEntry.required]. `null` keeps the value
  /// derived from the parameter's required-ness.
  final bool? required;

  /// Replacement [PropertyEntry.defaultValue]. `null` keeps the value
  /// derived from the parameter's literal default expression.
  final Object? defaultValue;

  /// Replacement [PropertyEntry.defaultBrandToken]. Mutually exclusive
  /// with [defaultValue].
  final String? defaultBrandToken;

  /// Replacement [PropertyEntry.positional] flag. `null` keeps `false`
  /// (the default for named parameters).
  final bool? positional;

  /// Replacement [PropertyEntry.enumType]. Required when the underlying
  /// parameter resolves to [PropertyType.enumValue] and the catalog
  /// needs the Dart enum name for codegen.
  final String? enumType;

  /// Replacement [PropertyEntry.widgetType]. Required when a
  /// non-canonical `Widget` slot needs a downcast (e.g.
  /// `'PreferredSizeWidget'` for a `Scaffold.appBar` slot).
  final String? widgetType;

  /// Replacement [PropertyEntry.callbackSignature]. Required when the
  /// catalog event slot needs a typed handler beyond `VoidCallback?`
  /// (e.g. `'ValueChanged<bool>'` for `Switch.onChanged`).
  final String? callbackSignature;

  /// Replacement [PropertyEntry.firesAs]. Set when the ctor names an
  /// event parameter differently from the catalog event taxonomy.
  final String? firesAs;
}
