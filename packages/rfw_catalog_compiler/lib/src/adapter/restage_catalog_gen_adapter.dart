import 'package:analyzer/dart/element/element.dart'
    show ClassElement, ConstructorElement, Element;
import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/factory_variant_fields.dart';
import 'package:rfw_catalog_compiler/src/ir/ir.dart';
import 'package:rfw_catalog_compiler/src/ir/ir_lower.dart' as ir_lower;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Resolves widget wire IDs for the catalog-gen adapter.
typedef RestageWidgetWireIdResolver = WireId Function(WidgetEntry widget);

/// Resolves property wire IDs for the catalog-gen adapter.
typedef RestagePropertyWireIdResolver = WireId Function(
  WidgetEntry widget,
  PropertyEntry property,
);

/// Resolves decomposition wire-ID references for the catalog-gen adapter.
typedef RestageDecompositionResolver = DecompositionRecipe Function(
  WidgetEntry widget,
  DecompositionRecipe recipe,
);

/// Resolves structured entry wire identity for the catalog-gen adapter.
///
/// The returned entry should carry resolved wire IDs on the entry itself,
/// its fields, and its variants. Entries the resolver cannot match against
/// the event log should be returned unchanged so the allocator can mint
/// fresh IDs in catalog-declaration order.
typedef RestageStructuredResolver = StructuredEntry Function(
  StructuredEntry entry,
);

/// Resolves union entry wire identity for the catalog-gen adapter.
///
/// The returned entry should carry its resolved wire ID when the event log
/// already records the union. Entries the resolver cannot match against the
/// event log should be returned unchanged so the allocator can mint a fresh
/// ID in catalog-declaration order.
typedef RestageUnionResolver = UnionEntry Function(
  UnionEntry entry,
);

/// Merges or replaces the deprecation on a catalog entry.
///
/// Called after the entry's wire ID is resolved. [resolvedId] is the wire ID
/// on the entry after upstream resolution — a stable ID when the event log
/// carries a matching entry, or the unallocated sentinel when it does not.
/// A resolver receiving a sentinel should return [existing] unchanged.
///
/// [existing] is the deprecation already set on the entry (e.g. a
/// `source`-layer deprecation from the reflector). The resolver may return a
/// new [DeprecationInfo] that combines both layers, return [existing]
/// unchanged, or return `null` to clear it.
///
/// When no hook is supplied the existing value passes through unmodified.
typedef RestageCatalogDeprecationResolver = DeprecationInfo? Function(
  WireId resolvedId,
  DeprecationInfo? existing,
);

/// Optional wire-ID hooks for the transitional restage_catalog_gen adapter.
///
/// With no hooks supplied, the reflected entries keep their existing sentinel
/// IDs. Supplying resolvers backed by event-log replay and allocation swaps in
/// stable IDs without changing the curation builder's call shape.
@immutable
final class RestageCatalogGenWireIdHooks {
  /// Creates wire-ID hooks.
  const RestageCatalogGenWireIdHooks({
    this.widget,
    this.property,
    this.decomposition,
    this.structured,
    this.union,
    this.deprecation,
  });

  /// Optional widget wire-ID resolver.
  final RestageWidgetWireIdResolver? widget;

  /// Optional property wire-ID resolver.
  final RestagePropertyWireIdResolver? property;

  /// Optional decomposition resolver for structured refs and flat mappings.
  final RestageDecompositionResolver? decomposition;

  /// Optional resolver for standalone structured catalog entries.
  final RestageStructuredResolver? structured;

  /// Optional resolver for discriminated-union catalog entries.
  final RestageUnionResolver? union;

  /// Optional deprecation resolver.
  ///
  /// When supplied, called for every catalog entry that carries a
  /// [DeprecationInfo] field — after the entry's wire ID is resolved. The
  /// resolved ID is a stable ID when the event log carries a matching entry,
  /// or the unallocated sentinel when it does not. The resolver may merge a
  /// catalog-lifecycle layer into the existing value, return it unchanged, or
  /// return `null`. When absent the existing value passes through unmodified.
  final RestageCatalogDeprecationResolver? deprecation;
}

/// Adapter from restage_catalog_gen's reflected schema entries into compiler
/// IR.
///
/// The current reflector already returns public schema entries, but this
/// adapter still routes them through [CatalogIR], [WidgetIR], [PropertyIR], and
/// lowering so downstream emitters consume compiler-lowered schema. The adapter
/// is intentionally narrow and lossless for fields that exist in the current
/// built-in registries.
final class RestageCatalogGenAdapter {
  /// Creates an adapter.
  const RestageCatalogGenAdapter({
    this.wireIds = const RestageCatalogGenWireIdHooks(),
  });

  /// Wire-ID resolution hooks.
  final RestageCatalogGenWireIdHooks wireIds;

  /// Routes reflected widgets through compiler IR and lowers to [Catalog].
  ///
  /// [capabilityVersion] is the library's declared monotonic capability version
  /// (distinct from the pub semver [version]); pass `null` when the library
  /// declared none — it is then omitted from the lowered `LibraryInfo`.
  Catalog lowerCatalog({
    required WidgetLibrary library,
    required String version,
    required String generatedAt,
    required List<WidgetEntry> widgets,
    int? capabilityVersion,
    List<StructuredEntry> structuredEntries = const [],
    List<UnionEntry> unions = const [],
    String? flutterVersion,
  }) {
    final catalogIr = CatalogIR(
      generatedAt: generatedAt,
      flutterVersion: flutterVersion,
      libraryVersions: {library: version},
      libraryCapabilityVersions: {
        if (capabilityVersion != null) library: capabilityVersion,
      },
      widgets: [
        for (final widget in widgets) _widgetToIr(widget),
      ],
      structuredTypes: [
        for (final entry in structuredEntries)
          _structuredToIr(wireIds.structured?.call(entry) ?? entry),
      ],
      unions: [
        for (final entry in unions)
          _unionToIr(wireIds.union?.call(entry) ?? entry),
      ],
    );
    return ir_lower.lowerCatalog(catalogIr);
  }

  /// Routes reflected widgets through compiler IR and lowers to schema entries.
  List<WidgetEntry> lowerWidgets(List<WidgetEntry> widgets) {
    return [
      for (final widget in widgets) lowerWidget(_widgetToIr(widget)),
    ];
  }

  /// Resolves the deprecation for an entry.
  ///
  /// [id] is the entry's wire ID after upstream resolution — a stable ID when
  /// the event log carries a matching entry, or the unallocated sentinel when
  /// it does not. Delegates to [RestageCatalogGenWireIdHooks.deprecation] when
  /// supplied; otherwise returns [existing] unchanged. When no hook is present
  /// the behavior is byte-identical to the previous behavior.
  DeprecationInfo? _resolveDeprecation(WireId id, DeprecationInfo? existing) {
    return wireIds.deprecation?.call(id, existing) ?? existing;
  }

  WidgetIR _widgetToIr(WidgetEntry widget) {
    final resolvedId = wireIds.widget?.call(widget) ?? widget.wireId;
    return WidgetIR(
      wireId: resolvedId,
      source: _adapterClassElement,
      constructor: _adapterConstructorElement,
      name: widget.name,
      library: widget.library,
      category: widget.category,
      description: widget.description,
      properties: [
        for (final property in widget.properties)
          _propertyToIr(widget, property),
      ],
      decomposes: [
        for (final recipe in widget.decomposes)
          _decompositionToIr(widget, recipe),
      ],
      fires: widget.fires,
      childrenSlot: widget.childrenSlot,
      sinceVersion: widget.sinceVersion,
      stability: widget.stability,
      diagnostics: const [],
      provenance: ProvenanceIR(
        flutterType: widget.flutterType,
        curationSource: null,
        derivationTrace: const ['restage_catalog_gen_adapter'],
      ),
      policyTrace: const [],
      deprecatedSince: widget.deprecatedSince,
      deprecated: _resolveDeprecation(resolvedId, widget.deprecated),
    );
  }

  PropertyIR _propertyToIr(WidgetEntry widget, PropertyEntry property) {
    final resolvedId =
        wireIds.property?.call(widget, property) ?? property.wireId;
    return PropertyIR(
      wireId: resolvedId,
      source: _adapterElement,
      name: property.name,
      type: ResolvedType(
        kind: _typeKindFor(property.type),
        structuredRef: property.structuredRef,
        callbackSignature: property.callbackSignature,
        valueShape: property.valueShape,
      ),
      description: property.description,
      required: property.required,
      defaultSource: _defaultSourceFor(property),
      legacyDefaultValue: property.defaultValue,
      legacyDefaultBrandToken: property.defaultBrandToken,
      metadata: PropertyMetadataIR(
        mutuallyExclusiveWith: property.mutuallyExclusiveWith,
        requiresAncestor: property.requiresAncestor,
        category: property.category,
        priority: property.priority,
        validationRule: property.validationRule,
        deprecated: _resolveDeprecation(resolvedId, property.deprecated),
        synthetic: property.synthetic,
        firesAs: property.firesAs,
      ),
      positional: property.positional,
      enumType: property.enumType,
      widgetType: property.widgetType,
      callbackSignature: property.callbackSignature,
      policyTrace: const [],
      diagnostics: const [],
    );
  }

  StructuredIR _structuredToIr(StructuredEntry entry) {
    return StructuredIR(
      wireId: entry.wireId,
      source: _adapterClassElement,
      name: entry.name,
      library: entry.library,
      description: entry.description,
      fields: [
        for (final field in entry.fields) _structuredFieldToIr(field),
      ],
      variants: [
        for (final variant in entry.variants) _factoryVariantToIr(variant),
      ],
      stability: entry.stability,
      diagnostics: const [],
      provenance: ProvenanceIR(
        flutterType: entry.sourceType,
        curationSource: null,
        derivationTrace: const ['restage_catalog_gen_adapter'],
      ),
      policyTrace: const [],
      deprecated: _resolveDeprecation(entry.wireId, entry.deprecated),
    );
  }

  UnionIR _unionToIr(UnionEntry entry) {
    return UnionIR(
      wireId: entry.wireId,
      source: _adapterClassElement,
      name: entry.name,
      library: entry.library,
      description: entry.description,
      sourceType: entry.sourceType,
      memberSourceTypes: entry.memberSourceTypes,
      discriminator: entry.discriminator,
      members: entry.members,
      stability: entry.stability,
      diagnostics: const [],
      provenance: ProvenanceIR(
        flutterType: entry.sourceType,
        curationSource: null,
        derivationTrace: const ['restage_catalog_gen_adapter'],
      ),
      policyTrace: const [],
      deprecated: _resolveDeprecation(entry.wireId, entry.deprecated),
    );
  }

  StructuredFieldIR _structuredFieldToIr(StructuredField field) {
    return StructuredFieldIR(
      wireId: field.wireId,
      source: _adapterElement,
      name: field.name,
      type: ResolvedType(
        kind: _typeKindFor(field.type),
        structuredRef: field.structuredRef,
        unionRef: field.unionRef,
        valueShape: field.valueShape,
      ),
      description: field.description,
      required: field.required,
      defaultSource: field.defaultSource == null
          ? null
          : ResolvedDefaultSource(
              lowered: field.defaultSource!,
              shape: _shapeFor(field.defaultSource!),
              origin: ResolvedDefaultOrigin.curationOverride,
            ),
      metadata: PropertyMetadataIR(
        category: field.category,
        priority: field.priority,
        deprecated: _resolveDeprecation(field.wireId, field.deprecated),
      ),
      diagnostics: const [],
    );
  }

  FactoryVariantIR _factoryVariantToIr(FactoryVariant variant) {
    // Project the sealed subtype back onto the compiler's flat IR mirror.
    final fields = factoryVariantFields(variant);
    return FactoryVariantIR(
      wireId: variant.wireId,
      sourceKind: factoryVariantSourceKind(variant),
      source: _adapterElement,
      namedConstructor: fields.namedConstructor,
      staticAccessor: fields.staticAccessor,
      argMappings: fields.argMappings,
      parameters: fields.parameters,
      description: variant.description,
      deprecated: _resolveDeprecation(variant.wireId, variant.deprecated),
    );
  }

  DecompositionIR _decompositionToIr(
    WidgetEntry widget,
    DecompositionRecipe recipe,
  ) {
    final resolved = wireIds.decomposition?.call(widget, recipe) ?? recipe;
    return DecompositionIR(
      structuredRef: resolved.structuredRef,
      flatPropertyRefs: resolved.flatProperties,
      targetArg: resolved.targetArg,
      construction: resolved.construction,
      fieldMappings: resolved.fieldMappings,
      parameterMappings: resolved.parameterMappings,
      discriminator: resolved.discriminator,
    );
  }
}

ResolvedDefaultSource? _defaultSourceFor(PropertyEntry property) {
  final defaultSource = property.defaultSource;
  if (defaultSource != null) {
    return ResolvedDefaultSource(
      lowered: defaultSource,
      shape: _shapeFor(defaultSource),
      origin: ResolvedDefaultOrigin.curationOverride,
    );
  }

  final legacyDefault = property.defaultValue;
  if (legacyDefault != null) {
    return ResolvedDefaultSource(
      lowered: LiteralDefault(legacyDefault),
      shape: ResolvedDefaultShape.literal,
      origin: ResolvedDefaultOrigin.curationOverride,
    );
  }

  // Legacy brand-token defaults name tokens but do not yet carry token wire
  // IDs. The compiler does not yet allocate design tokens, so the adapter
  // preserves defaultBrandToken separately instead of inventing a
  // TokenRefDefault.
  return null;
}

ResolvedDefaultShape _shapeFor(DefaultValueSource source) {
  return switch (source) {
    LiteralDefault() => ResolvedDefaultShape.literal,
    TokenRefDefault() => ResolvedDefaultShape.tokenReference,
    ThemeBindingDefault() => ResolvedDefaultShape.themeBinding,
    FlutterCtorDefault() => ResolvedDefaultShape.flutterCtorDefault,
  };
}

ResolvedTypeKind _typeKindFor(PropertyType type) {
  return switch (type) {
    PropertyType.widget => ResolvedTypeKind.widget,
    PropertyType.widgetList => ResolvedTypeKind.widgetList,
    PropertyType.color => ResolvedTypeKind.color,
    PropertyType.length => ResolvedTypeKind.length,
    PropertyType.edgeInsets => ResolvedTypeKind.edgeInsets,
    PropertyType.alignment => ResolvedTypeKind.alignment,
    PropertyType.alignmentXY => ResolvedTypeKind.alignmentXY,
    PropertyType.offset => ResolvedTypeKind.offset,
    PropertyType.fontWeight => ResolvedTypeKind.fontWeight,
    PropertyType.duration => ResolvedTypeKind.duration,
    PropertyType.curve => ResolvedTypeKind.curve,
    PropertyType.boolean => ResolvedTypeKind.boolean,
    PropertyType.integer => ResolvedTypeKind.integer,
    PropertyType.real => ResolvedTypeKind.real,
    PropertyType.string => ResolvedTypeKind.string,
    PropertyType.stringList => ResolvedTypeKind.stringList,
    PropertyType.booleanList => ResolvedTypeKind.booleanList,
    PropertyType.event => ResolvedTypeKind.event,
    PropertyType.dataReference => ResolvedTypeKind.dataReference,
    PropertyType.enumValue => ResolvedTypeKind.enumValue,
    PropertyType.gradient => ResolvedTypeKind.gradient,
    PropertyType.border => ResolvedTypeKind.border,
    PropertyType.shapeBorder => ResolvedTypeKind.shapeBorder,
    PropertyType.boxShadowList => ResolvedTypeKind.boxShadowList,
    PropertyType.locale => ResolvedTypeKind.locale,
    PropertyType.paint => ResolvedTypeKind.paint,
    PropertyType.shadowList => ResolvedTypeKind.shadowList,
    PropertyType.fontFeatureList => ResolvedTypeKind.fontFeatureList,
    PropertyType.fontVariationList => ResolvedTypeKind.fontVariationList,
    PropertyType.textDecoration => ResolvedTypeKind.textDecoration,
    PropertyType.structured => ResolvedTypeKind.structured,
    PropertyType.inlineSpan => ResolvedTypeKind.inlineSpan,
    PropertyType.decorationImage => ResolvedTypeKind.decorationImage,
    PropertyType.selectionOptionList => ResolvedTypeKind.selectionOptionList,
    // The adapter consumes WidgetEntry from local annotation-driven
    // reflection, not decoded JSON, so PropertyType.unknown should
    // never reach here. Surface loudly if it does.
    PropertyType.unknown => throw StateError(
        'PropertyType.unknown is a decoder-side forward-compat '
        'sentinel and must not appear in a locally-reflected catalog.',
      ),
  };
}

// The intermediate representation carries analyzer `Element` fields that only
// the source-walking compiler path populates and reads. This adapter builds the
// same IR from an already-reflected catalog, so it has no analyzer elements to
// supply. These placeholders fill the non-nullable element fields and must
// never be dereferenced: any member access throws immediately rather than
// silently returning a fabricated value.
//
// Invariant: IR produced by this adapter is element-free. Code that needs a
// real analyzer element must run on the source-walking path, not on
// adapter-constructed IR.
final ClassElement _adapterClassElement = _AdapterClassElement();
final ConstructorElement _adapterConstructorElement =
    _AdapterConstructorElement();
final Element _adapterElement = _AdapterElement();

/// Placeholder [ClassElement] for adapter-constructed IR. Element fields on
/// adapter IR are never read; any access throws [StateError].
final class _AdapterClassElement implements ClassElement {
  @override
  Never noSuchMethod(Invocation invocation) => throw _adapterElementError;
}

/// Placeholder [ConstructorElement] for adapter-constructed IR. Element fields
/// on adapter IR are never read; any access throws [StateError].
final class _AdapterConstructorElement implements ConstructorElement {
  @override
  Never noSuchMethod(Invocation invocation) => throw _adapterElementError;
}

/// Placeholder [Element] for adapter-constructed IR. Element fields on adapter
/// IR are never read; any access throws [StateError].
final class _AdapterElement implements Element {
  @override
  Never noSuchMethod(Invocation invocation) => throw _adapterElementError;
}

StateError get _adapterElementError => StateError(
      'Analyzer element fields must not be dereferenced on adapter-constructed '
      'catalog IR; this IR is element-free. Run on the source-walking path if '
      'a real analyzer element is required.',
    );
