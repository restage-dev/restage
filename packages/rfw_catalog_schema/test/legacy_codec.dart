import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:rfw_catalog_schema/src/catalog.dart';
import 'package:rfw_catalog_schema/src/catalog_codec.dart';
import 'package:rfw_catalog_schema/src/decomposition_recipe.dart';
import 'package:rfw_catalog_schema/src/default_source_codec.dart';
import 'package:rfw_catalog_schema/src/default_value_source.dart';
import 'package:rfw_catalog_schema/src/factory_variant.dart';
import 'package:rfw_catalog_schema/src/library_info.dart';
import 'package:rfw_catalog_schema/src/property_entry.dart';
import 'package:rfw_catalog_schema/src/property_type.dart';
import 'package:rfw_catalog_schema/src/structured_entry.dart';
import 'package:rfw_catalog_schema/src/union_entry.dart';
import 'package:rfw_catalog_schema/src/widget_entry.dart';
import 'package:rfw_catalog_schema/src/widget_library.dart';
import 'package:rfw_catalog_schema/src/widget_metadata.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// Legacy v2 wire-shape schema version. Pre-canonical: no wire IDs,
/// no envelope counts beyond `widgetCount`, no structured / union /
/// design-token sections, no compat rules, recipes keyed by source
/// names instead of wire IDs.
///
/// Transitional. Use [encodeLegacyCatalogV2] and
/// [decodeLegacyCatalogV2] only at the projection boundary between the
/// canonical schema in memory and a persisted v2 baseline; everything else
/// should speak canonical via `encodeCatalog` / `decodeCatalog`.
const int kLegacySchemaVersion = 2;

/// Decoded projection of a legacy v2 catalog JSON file.
///
/// This is deliberately not a [Catalog]. The v2 wire shape has no wire IDs,
/// structured entries, unions, design tokens, or compatibility rules, so it
/// cannot be treated as a public final-form canonical catalog until an
/// allocator has assigned real IDs. Transitional consumers that still need
/// the existing [WidgetEntry] API can call
/// [toCatalogWithInternalPlaceholders]; `encodeCatalog` rejects that result
/// until the placeholders are replaced by allocated IDs.
@immutable
final class LegacyCatalogV2 {
  /// Const constructor.
  const LegacyCatalogV2({
    required this.schemaVersion,
    required this.generatedAt,
    required this.libraries,
    required this.widgets,
    this.structuredTypes = const [],
    this.unions = const [],
    this.designTokens = const [],
  });

  /// Legacy schema version. Always [kLegacySchemaVersion] for decoded input.
  final int schemaVersion;

  /// ISO-8601 UTC timestamp from the v2 baseline.
  final String generatedAt;

  /// Per-library v2 envelope metadata.
  final Map<WidgetLibrary, LibraryInfo> libraries;

  /// Legacy widget entries, without canonical wire IDs.
  final List<LegacyWidgetEntry> widgets;

  /// Additive structured-type section emitted by [encodeLegacyCatalogV2].
  /// Preserved as raw v2-shape maps so reader/writer round-trip the same
  /// surface; the legacy projection has no wire IDs to materialize as
  /// canonical [StructuredEntry] instances. Defaults to `const []` for
  /// pre-extension v2 blobs that omit the section entirely.
  final List<Map<String, dynamic>> structuredTypes;

  /// Additive discriminated-union section. Same raw-map round-trip
  /// rationale as [structuredTypes]; empty by default for older v2 blobs.
  final List<Map<String, dynamic>> unions;

  /// Additive design-token section. Same raw-map round-trip rationale
  /// as [structuredTypes]; empty by default for older v2 blobs.
  final List<Map<String, dynamic>> designTokens;

  /// Legacy widgets belonging to [library].
  List<LegacyWidgetEntry> widgetsIn(WidgetLibrary library) =>
      widgets.where((w) => w.library == library).toList(growable: false);

  /// Transitional projection into the current in-memory [Catalog] shape.
  ///
  /// The returned entries carry internal `WireId.unallocated*` placeholders
  /// only so existing pre-allocator tooling can reuse [WidgetEntry]-based
  /// diff and factory-emission code. The projection is not canonical and
  /// cannot be emitted by `encodeCatalog`.
  Catalog toCatalogWithInternalPlaceholders() {
    return Catalog(
      schemaVersion: schemaVersion,
      generatedAt: generatedAt,
      libraries: libraries,
      widgets: [
        for (final widget in widgets)
          widget.toWidgetEntryWithInternalPlaceholders(),
      ],
    );
  }
}

/// Legacy v2 widget entry without canonical wire identity.
@immutable
final class LegacyWidgetEntry {
  /// Const constructor.
  const LegacyWidgetEntry({
    required this.name,
    required this.library,
    required this.category,
    required this.description,
    required this.flutterType,
    required this.childrenSlot,
    required this.fires,
    required this.properties,
    this.decomposes = const [],
    this.deprecatedSince,
  });

  /// Legacy catalog key.
  final String name;

  /// Library this widget belongs to.
  final WidgetLibrary library;

  /// Widget category.
  final WidgetCategory category;

  /// Human-readable description.
  final String description;

  /// Advisory Flutter type provenance.
  final String flutterType;

  /// Children slot.
  final ChildrenSlot childrenSlot;

  /// Events this widget can fire.
  final List<WidgetEventName> fires;

  /// Legacy properties, without wire IDs.
  final List<LegacyPropertyEntry> properties;

  /// Legacy decomposition recipes, keyed by source names.
  final List<LegacyDecompositionRecipe> decomposes;

  /// Legacy v2 deprecation marker.
  final String? deprecatedSince;

  /// Transitional projection into [WidgetEntry] for pre-allocator tools.
  WidgetEntry toWidgetEntryWithInternalPlaceholders() {
    return WidgetEntry(
      wireId: WireId.unallocated(WireIdKind.widget),
      name: name,
      library: library,
      category: category,
      description: description,
      flutterType: flutterType,
      childrenSlot: childrenSlot,
      fires: fires,
      properties: [
        for (final property in properties)
          property.toPropertyEntryWithInternalPlaceholders(),
      ],
      decomposes: [
        for (final recipe in decomposes)
          recipe.toDecompositionRecipeWithInternalPlaceholders(library),
      ],
      deprecatedSince: deprecatedSince,
    );
  }
}

/// Legacy v2 property entry without canonical wire identity.
@immutable
final class LegacyPropertyEntry {
  /// Const constructor.
  const LegacyPropertyEntry({
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
    this.defaultValue,
    this.defaultBrandToken,
    this.defaultSource,
    this.synthetic,
    this.positional = false,
    this.enumType,
    this.widgetType,
    this.callbackSignature,
    this.firesAs,
  });

  /// Legacy property name.
  final String name;

  /// Property type.
  final PropertyType type;

  /// Human-readable description.
  final String description;

  /// Whether the property is required.
  final bool required;

  /// Legacy literal default value.
  final Object? defaultValue;

  /// Legacy brand-token default name.
  final String? defaultBrandToken;

  /// Canonical discriminated default source, carried additively on the
  /// v2 wire shape.
  ///
  /// Transitional: the legacy v2 projection predates discriminated default
  /// sources and historically dropped them, exposing only the flattened
  /// [defaultValue] / [defaultBrandToken] pair. This field rides alongside
  /// those legacy fields so a consumer that decodes the v2 baseline (the
  /// codegen factory builder) can still observe a materialized
  /// [ThemeBindingDefault] / [FlutterCtorDefault]. It is a bridge until the
  /// codegen path consumes the fully canonical catalog; older v2 blobs that
  /// omit the `defaultSource` key decode this as `null`.
  final DefaultValueSource? defaultSource;

  /// Legacy synthetic strategy.
  final String? synthetic;

  /// Whether this property maps to a positional argument.
  final bool positional;

  /// Enum type name for enum-valued properties.
  final String? enumType;

  /// Widget slot type override.
  final String? widgetType;

  /// Callback signature override.
  final String? callbackSignature;

  /// Event taxonomy alias.
  final String? firesAs;

  /// Transitional projection into [PropertyEntry] for pre-allocator tools.
  PropertyEntry toPropertyEntryWithInternalPlaceholders() {
    return PropertyEntry(
      wireId: WireId.unallocated(WireIdKind.property),
      name: name,
      type: type,
      description: description,
      required: required,
      defaultBrandToken: defaultBrandToken,
      defaultSource: defaultSource ??
          (defaultValue != null ? LiteralDefault(defaultValue!) : null),
      synthetic: synthetic,
      positional: positional,
      enumType: enumType,
      widgetType: widgetType,
      callbackSignature: callbackSignature,
      firesAs: firesAs,
    );
  }
}

/// Legacy v2 decomposition recipe keyed by source names.
@immutable
final class LegacyDecompositionRecipe {
  /// Const constructor.
  const LegacyDecompositionRecipe({
    required this.structuredType,
    required this.flatProperties,
    this.factoryConvention,
  });

  /// Legacy structured type name, e.g. `TextStyle`.
  final String structuredType;

  /// Legacy map from structured constructor argument to flat property name.
  final Map<String, String> flatProperties;

  /// Optional legacy factory convention.
  final String? factoryConvention;

  /// Transitional projection into [DecompositionRecipe].
  DecompositionRecipe toDecompositionRecipeWithInternalPlaceholders(
    WidgetLibrary owningLibrary,
  ) {
    return DecompositionRecipe(
      structuredRef: WireIdRef(
        library: owningLibrary.namespace,
        wireId: WireId.unallocated(WireIdKind.structured),
      ),
      flatProperties: const <WireId, WireId>{},
    );
  }
}

/// Project [catalog] onto the v2 wire shape and emit as JSON.
///
/// Drops canonical-only fields (wire IDs on widgets and properties,
/// envelope counts beyond `widgetCount`, compat rules, stability tier,
/// two-layer deprecation). The `defaultValue` and `defaultBrandToken` legacy
/// projections are populated from the canonical [PropertyEntry.defaultSource]
/// when set; otherwise from `legacyStructuredType` / `legacyFlatProperties`
/// on decomposition recipes. Producers that maintain the legacy fields
/// alongside canonical fields during the transition will see v2 emission
/// preserve the legacy values as authored.
///
/// Structured / union / design-token sections appear as additive
/// shape extensions: legacy decoders (which never read those keys)
/// ignore them, and consumers that have moved on to the canonical wire
/// shape can still read them through the v2 baseline.
String encodeLegacyCatalogV2(Catalog catalog) {
  final structuredNameByWireId = <WireId, String>{
    for (final structured in catalog.structuredTypes)
      structured.wireId: structured.name,
  };
  final structuredFieldNameByWireId = <WireId, String>{
    for (final structured in catalog.structuredTypes)
      for (final field in structured.fields) field.wireId: field.name,
  };
  return const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': kLegacySchemaVersion,
    'generatedAt': catalog.generatedAt,
    'libraries': {
      for (final entry in catalog.libraries.entries)
        entry.key.namespace: {
          'version': entry.value.version,
          // The legacy v2 envelope carried a per-library widgetCount; compute
          // it from the catalog now that LibraryInfo no longer stores it.
          'widgetCount': catalog.widgetsIn(entry.key).length,
        },
    },
    'widgets': [
      for (final widget in catalog.widgets)
        _widgetToLegacyJson(
          widget,
          structuredNameByWireId: structuredNameByWireId,
          structuredFieldNameByWireId: structuredFieldNameByWireId,
        ),
    ],
    'structuredTypes':
        catalog.structuredTypes.map(_structuredToLegacyJson).toList(),
    'unions': catalog.unions.map(_unionToLegacyJson).toList(),
    'designTokens': const <Map<String, dynamic>>[],
  });
}

Map<String, dynamic> _structuredToLegacyJson(StructuredEntry entry) {
  return {
    'name': entry.name,
    'library': entry.library.namespace,
    'description': entry.description,
    'sourceType': entry.sourceType,
    'fields': entry.fields.map(_structuredFieldToLegacyJson).toList(),
    'variants': entry.variants.map(_factoryVariantToLegacyJson).toList(),
  };
}

/// Projects a [UnionEntry] onto the v2 legacy catalog shape. Wire IDs are
/// dropped; members are emitted as source-type FQNs and the discriminator
/// carries the field name only.
Map<String, dynamic> _unionToLegacyJson(UnionEntry entry) {
  return {
    'name': entry.name,
    'library': entry.library.namespace,
    'description': entry.description,
    'sourceType': entry.sourceType,
    // Legacy shape identifies members by source FQN rather than wire ID —
    // the FQN list is index-aligned with the entry's discriminator values.
    'members': entry.memberSourceTypes,
    // DiscriminatorSpec.values (wire ID refs) are intentionally omitted —
    // the legacy shape is FQN-only and identifies members via the `members`
    // FQN list above, not by wire ID.
    'discriminator': {'field': entry.discriminator.field},
  };
}

Map<String, dynamic> _structuredFieldToLegacyJson(StructuredField field) {
  return {
    'name': field.name,
    'type': field.type.name,
    'description': field.description,
    if (field.required) 'required': true,
    if (field.structuredRef != null)
      'structuredRef': {
        'library': field.structuredRef!.library,
        'wireId': field.structuredRef!.wireId.value,
      },
  };
}

Map<String, dynamic> _factoryVariantToLegacyJson(FactoryVariant variant) {
  Map<String, dynamic> argMappingsJson(Map<String, ArgMapping> argMappings) => {
        if (argMappings.isNotEmpty)
          'argMappings': {
            for (final entry in argMappings.entries)
              entry.key: [
                for (final id in entry.value.targetFields) id.value,
              ],
          },
      };
  return {
    'sourceKind': factoryVariantSourceKind(variant).name,
    ...switch (variant) {
      ConstructorVariant(:final namedConstructor, :final argMappings) => {
          if (namedConstructor != null) 'namedConstructor': namedConstructor,
          ...argMappingsJson(argMappings),
        },
      StaticMethodVariant(:final staticAccessor, :final argMappings) => {
          'staticAccessor': staticAccessor,
          ...argMappingsJson(argMappings),
        },
      StaticGetterVariant(:final staticAccessor) => {
          'staticAccessor': staticAccessor,
        },
      ConstValueVariant(:final staticAccessor) => {
          'staticAccessor': staticAccessor,
        },
    },
    if (variant.description != null) 'description': variant.description,
  };
}

Map<String, dynamic> _widgetToLegacyJson(
  WidgetEntry w, {
  required Map<WireId, String> structuredNameByWireId,
  required Map<WireId, String> structuredFieldNameByWireId,
}) {
  final propertyNameByWireId = <WireId, String>{
    for (final property in w.properties) property.wireId: property.name,
  };
  return {
    'name': w.name,
    'library': w.library.namespace,
    'category': w.category.name,
    'description': w.description,
    'flutterType': w.flutterType,
    'childrenSlot': w.childrenSlot.name,
    'fires': w.fires.map((e) => e.name).toList(),
    'properties': w.properties.map(_propertyToLegacyJson).toList(),
    if (w.decomposes.isNotEmpty)
      'decomposes': [
        for (final recipe in w.decomposes)
          _decompositionToLegacyJson(
            recipe,
            widgetName: w.name,
            propertyNameByWireId: propertyNameByWireId,
            structuredNameByWireId: structuredNameByWireId,
            structuredFieldNameByWireId: structuredFieldNameByWireId,
          ),
      ],
    if (w.deprecatedSince != null) 'deprecatedSince': w.deprecatedSince,
  };
}

// Local builds never emit `PropertyType.unknown` — the sentinel only
// arises on the decode side when reading a payload from a newer
// schema that introduced a new enum member. The encoder treats the
// enum's `.name` opaquely.
Map<String, dynamic> _propertyToLegacyJson(PropertyEntry p) {
  assert(
    p.type != PropertyType.unknown,
    'PropertyType.unknown is decoder-only; local builds never construct it.',
  );
  return {
    'name': p.name,
    'type': p.type.name,
    'description': p.description,
    if (p.required) 'required': true,
    if (p.defaultValue != null) 'defaultValue': p.defaultValue,
    if (p.defaultBrandToken != null) 'defaultBrandToken': p.defaultBrandToken,
    // Additive transitional field: the discriminated default source rides
    // alongside the flattened legacy `defaultValue` / `defaultBrandToken`
    // pair, never replacing them. Legacy v2 decoders that predate this key
    // ignore it; the codegen factory builder reads it back to observe a
    // materialized ThemeBindingDefault / FlutterCtorDefault.
    if (p.defaultSource != null)
      'defaultSource': defaultSourceToJson(p.defaultSource!),
    if (p.synthetic != null) 'synthetic': p.synthetic,
    if (p.positional) 'positional': true,
    if (p.enumType != null) 'enumType': p.enumType,
    if (p.widgetType != null) 'widgetType': p.widgetType,
    if (p.callbackSignature != null) 'callbackSignature': p.callbackSignature,
    if (p.firesAs != null) 'firesAs': p.firesAs,
  };
}

Map<String, dynamic> _decompositionToLegacyJson(
  DecompositionRecipe r, {
  required String widgetName,
  required Map<WireId, String> propertyNameByWireId,
  required Map<WireId, String> structuredNameByWireId,
  required Map<WireId, String> structuredFieldNameByWireId,
}) {
  final structuredType = structuredNameByWireId[r.structuredRef.wireId];
  final flatProperties = _projectLegacyFlatProperties(
    r,
    widgetName: widgetName,
    propertyNameByWireId: propertyNameByWireId,
    structuredFieldNameByWireId: structuredFieldNameByWireId,
  );
  if (structuredType == null) {
    throw CatalogSchemaException(
      'DecompositionRecipe targeted at wire-ID-keyed flat mapping cannot '
      'project to legacy v2 wire shape: structuredRef has no matching '
      'structuredTypes entry.',
    );
  }
  return {
    'structuredType': structuredType,
    'flatProperties': flatProperties,
  };
}

/// Parse a v2 catalog JSON string into a legacy projection.
///
/// The result is not a canonical [Catalog] because v2 JSON carries no wire
/// IDs. Consumers that need the old `WidgetEntry`-based in-memory shape can
/// call [LegacyCatalogV2.toCatalogWithInternalPlaceholders] at an explicit
/// legacy boundary; canonical emission still requires allocator-owned IDs.
///
/// Throws [CatalogSchemaException] on malformed input or an unsupported
/// schema version.
LegacyCatalogV2 decodeLegacyCatalogV2(String source) {
  final Object? raw;
  try {
    raw = jsonDecode(source);
  } on FormatException catch (e) {
    throw CatalogSchemaException('Invalid JSON: ${e.message}');
  }
  if (raw is! Map<String, dynamic>) {
    throw CatalogSchemaException('Top-level value must be a JSON object');
  }
  final version = raw['schemaVersion'];
  if (version != kLegacySchemaVersion) {
    throw CatalogSchemaException(
      'decodeLegacyCatalogV2 expects schemaVersion $kLegacySchemaVersion; '
      'got $version. Use decodeCatalog for the canonical wire shape.',
    );
  }
  final generatedAt = raw['generatedAt'];
  final librariesRaw = raw['libraries'];
  final widgetsRaw = raw['widgets'];
  if (generatedAt is! String || librariesRaw is! Map || widgetsRaw is! List) {
    throw CatalogSchemaException(
      'Missing or malformed required fields '
      '(generatedAt, libraries, widgets)',
    );
  }
  return LegacyCatalogV2(
    schemaVersion: version as int,
    generatedAt: generatedAt,
    libraries: {
      for (final entry in librariesRaw.entries)
        WidgetLibrary.fromNamespace(entry.key as String): _legacyLibraryInfo(
          (entry.value as Map).cast<String, dynamic>(),
          'libraries["${entry.key}"]',
        ),
    },
    widgets: [
      for (var i = 0; i < widgetsRaw.length; i++)
        _legacyWidgetFromJson(
          (widgetsRaw[i] as Map).cast<String, dynamic>(),
          'widgets[$i]',
        ),
    ],
    // Additive sections: pre-extension v2 blobs omit them and decode as
    // empty lists; extended blobs round-trip the raw v2-shape maps the
    // encoder emitted. Symmetry with the encoder is the load-bearing
    // property — without it, any v2 reader sees a different surface
    // than the writer produced.
    structuredTypes:
        _legacyRawSection(raw['structuredTypes'], 'structuredTypes'),
    unions: _legacyRawSection(raw['unions'], 'unions'),
    designTokens: _legacyRawSection(raw['designTokens'], 'designTokens'),
  );
}

List<Map<String, dynamic>> _legacyRawSection(Object? raw, String path) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw CatalogSchemaException(
      '$path: malformed optional list field',
    );
  }
  return [
    for (var i = 0; i < raw.length; i++)
      (raw[i] as Map).cast<String, dynamic>(),
  ];
}

LibraryInfo _legacyLibraryInfo(Map<String, dynamic> j, String path) {
  if (j['version'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: version',
    );
  }
  if (j['widgetCount'] is! int) {
    throw CatalogSchemaException(
      '$path: missing required int field: widgetCount',
    );
  }
  // The legacy v2 envelope mandated widgetCount; it is validated above but
  // discarded — LibraryInfo no longer stores per-kind counts.
  return LibraryInfo(version: j['version'] as String);
}

LegacyWidgetEntry _legacyWidgetFromJson(Map<String, dynamic> j, String path) {
  if (j['name'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: name',
    );
  }
  final name = j['name'] as String;
  final widgetPath = '$path "$name"';
  if (j['library'] is! String) {
    throw CatalogSchemaException(
      '$widgetPath: missing required string field: library',
    );
  }
  if (j['category'] is! String) {
    throw CatalogSchemaException(
      '$widgetPath: missing required string field: category',
    );
  }
  if (j['description'] is! String) {
    throw CatalogSchemaException(
      '$widgetPath: missing required string field: description',
    );
  }
  if (j['flutterType'] is! String) {
    throw CatalogSchemaException(
      '$widgetPath: missing required string field: flutterType',
    );
  }
  if (j['childrenSlot'] is! String) {
    throw CatalogSchemaException(
      '$widgetPath: missing required string field: childrenSlot',
    );
  }
  if (j['fires'] is! List) {
    throw CatalogSchemaException(
      '$widgetPath: missing required list field: fires',
    );
  }
  if (j['properties'] is! List) {
    throw CatalogSchemaException(
      '$widgetPath: missing required list field: properties',
    );
  }
  final decomposesRaw = j['decomposes'];
  if (decomposesRaw != null && decomposesRaw is! List) {
    throw CatalogSchemaException(
      '$widgetPath: malformed optional list field: decomposes',
    );
  }
  final propertiesRaw = j['properties'] as List;
  final library = WidgetLibrary.fromNamespace(j['library'] as String);
  return LegacyWidgetEntry(
    name: name,
    library: library,
    category: _legacyEnum(
      WidgetCategory.values,
      j['category'] as String,
      'category',
      widgetPath,
    ),
    description: j['description'] as String,
    flutterType: j['flutterType'] as String,
    childrenSlot: _legacyEnum(
      ChildrenSlot.values,
      j['childrenSlot'] as String,
      'childrenSlot',
      widgetPath,
    ),
    fires: (j['fires'] as List)
        .map(
          (e) => _legacyEnum(
            WidgetEventName.values,
            e as String,
            'fires',
            widgetPath,
          ),
        )
        .toList(),
    properties: [
      for (var i = 0; i < propertiesRaw.length; i++)
        _legacyPropertyFromJson(
          (propertiesRaw[i] as Map).cast<String, dynamic>(),
          '$widgetPath.properties[$i]',
        ),
    ],
    decomposes: decomposesRaw == null
        ? const []
        : [
            for (var i = 0; i < (decomposesRaw as List).length; i++)
              _legacyDecompositionFromJson(
                (decomposesRaw[i] as Map).cast<String, dynamic>(),
                '$widgetPath.decomposes[$i]',
              ),
          ],
    deprecatedSince: j['deprecatedSince'] as String?,
  );
}

LegacyPropertyEntry _legacyPropertyFromJson(
  Map<String, dynamic> j,
  String path,
) {
  if (j['name'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: name',
    );
  }
  if (j['type'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: type',
    );
  }
  if (j['description'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: description',
    );
  }
  return LegacyPropertyEntry(
    name: j['name'] as String,
    // Forward-compat: unknown PropertyType names fall back to the
    // `unknown` sentinel rather than throwing. New enum members can
    // land additively in newer catalog schemas without breaking
    // older decoder builds.
    type: _tryLegacyEnum(PropertyType.values, j['type'] as String) ??
        PropertyType.unknown,
    description: j['description'] as String,
    required: j['required'] as bool? ?? false,
    defaultValue: j['defaultValue'],
    defaultBrandToken: j['defaultBrandToken'] as String?,
    // Additive transitional field — tolerate its absence: older v2 blobs
    // authored before the key existed omit it and decode as null.
    defaultSource:
        defaultSourceFromJson(j['defaultSource'], '$path.defaultSource'),
    synthetic: j['synthetic'] as String?,
    positional: j['positional'] as bool? ?? false,
    enumType: j['enumType'] as String?,
    widgetType: j['widgetType'] as String?,
    callbackSignature: j['callbackSignature'] as String?,
    firesAs: j['firesAs'] as String?,
  );
}

LegacyDecompositionRecipe _legacyDecompositionFromJson(
  Map<String, dynamic> j,
  String path,
) {
  if (j['structuredType'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: structuredType',
    );
  }
  if (j['flatProperties'] is! Map) {
    throw CatalogSchemaException(
      '$path: missing required map field: flatProperties',
    );
  }
  // Validate eagerly. Map.cast returns a lazy view that defers TypeError
  // to first read — turning a structurally-broken catalog into a successful
  // decode that explodes far from the source.
  final legacyFlat = <String, String>{};
  for (final entry in (j['flatProperties'] as Map).entries) {
    if (entry.key is! String || entry.value is! String) {
      throw CatalogSchemaException(
        '$path.flatProperties: must map string to string; got '
        '${entry.key.runtimeType} -> ${entry.value.runtimeType}',
      );
    }
    legacyFlat[entry.key as String] = entry.value as String;
  }
  return LegacyDecompositionRecipe(
    factoryConvention: j['factoryConvention'] as String?,
    structuredType: j['structuredType'] as String,
    flatProperties: legacyFlat,
  );
}

T _legacyEnum<T extends Enum>(
  List<T> values,
  String name,
  String label,
  String path,
) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw CatalogSchemaException('$path: unknown $label value: $name');
}

/// Looks up [name] in [values] and returns the matching enum, or
/// `null` when [name] is not recognized. Use at call sites that
/// want forward-compat with additive enum evolution (e.g. a
/// payload from a newer catalog schema introducing a new member);
/// the call site supplies the fallback (typically an `unknown`
/// sentinel) via `?? ...`.
T? _tryLegacyEnum<T extends Enum>(List<T> values, String name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// Projects a canonical [Catalog] (e.g. from `decodeCatalog`) into the v2
/// **consumer shape** the build-time codegen consumers read.
///
/// This is the canonical-side analogue of
/// [LegacyCatalogV2.toCatalogWithInternalPlaceholders]. The codegen factory
/// builder and the paywall transpiler were written against the v2 projection's
/// flat [PropertyEntry.defaultValue] and name-keyed legacy decomposition
/// fields.
/// The canonical wire shape carries the same information differently
/// ([PropertyEntry.defaultSource]; wire-ID-keyed
/// [DecompositionRecipe.structuredRef] / [DecompositionRecipe.flatProperties]),
/// so a consumer that decodes a canonical catalog calls this projection to
/// recover the shape it expects. Like `toCatalogWithInternalPlaceholders`, the
/// result is widget-only (the structured / union sections are not part of the
/// consumer surface).
///
/// **Recovered:**
/// * `defaultValue` ← `defaultSource` when it is a [LiteralDefault].
/// * `legacyStructuredType` ← the recipe's `structuredRef` target name
///   (resolved against [Catalog.structuredTypes]).
/// * `legacyFlatProperties` ← the recipe's `flatProperties`, resolving each
///   mapped widget-property wire ID to its name. The curation names every flat
///   property identically to the structured constructor argument it feeds
///   (key == value), so the argument key is recovered from the flat-property
///   name; when the structured field name is itself resolvable, an
///   [ArgumentError] fires if the two disagree, so a future curation that
///   breaks the invariant fails loudly rather than mis-mapping.
///
/// **Not recovered:** `defaultBrandToken`. The canonical wire shape does not
/// carry it and it is not derivable from `defaultSource` (the built-in
/// brand-token defaults predate [TokenRefDefault]). The codegen consumers do
/// not read it — the factory emitter treats a brand-token default as a
/// no-fallback Flutter ctor default — so the omission does not change emitted
/// output. A structured-walker follow-up restores it.
extension CatalogConsumerProjection on Catalog {
  /// See [CatalogConsumerProjection].
  Catalog toConsumerShape() {
    final structuredNameByWireId = <WireId, String>{
      for (final structured in structuredTypes)
        structured.wireId: structured.name,
    };
    final structuredFieldNameByWireId = <WireId, String>{
      for (final structured in structuredTypes)
        for (final field in structured.fields) field.wireId: field.name,
    };
    return Catalog(
      schemaVersion: schemaVersion,
      generatedAt: generatedAt,
      libraries: libraries,
      widgets: [
        for (final widget in widgets)
          _widgetToConsumerShape(
            widget,
            structuredNameByWireId,
            structuredFieldNameByWireId,
          ),
      ],
    );
  }
}

WidgetEntry _widgetToConsumerShape(
  WidgetEntry widget,
  Map<WireId, String> structuredNameByWireId,
  Map<WireId, String> structuredFieldNameByWireId,
) {
  final propertyNameByWireId = <WireId, String>{
    for (final property in widget.properties) property.wireId: property.name,
  };
  return WidgetEntry(
    wireId: widget.wireId,
    name: widget.name,
    library: widget.library,
    category: widget.category,
    description: widget.description,
    flutterType: widget.flutterType,
    childrenSlot: widget.childrenSlot,
    fires: widget.fires,
    properties: [
      for (final property in widget.properties)
        _propertyToConsumerShape(property),
    ],
    decomposes: [
      for (final recipe in widget.decomposes)
        _recipeToConsumerShape(
          recipe,
          widgetName: widget.name,
          propertyNameByWireId: propertyNameByWireId,
          structuredNameByWireId: structuredNameByWireId,
          structuredFieldNameByWireId: structuredFieldNameByWireId,
        ),
    ],
    deprecatedSince: widget.deprecatedSince,
    stability: widget.stability,
    deprecated: widget.deprecated,
  );
}

PropertyEntry _propertyToConsumerShape(PropertyEntry property) {
  return PropertyEntry(
    wireId: property.wireId,
    name: property.name,
    type: property.type,
    description: property.description,
    required: property.required,
    defaultBrandToken: property.defaultBrandToken,
    synthetic: property.synthetic,
    positional: property.positional,
    enumType: property.enumType,
    widgetType: property.widgetType,
    callbackSignature: property.callbackSignature,
    firesAs: property.firesAs,
    defaultSource: property.defaultSource,
    mutuallyExclusiveWith: property.mutuallyExclusiveWith,
    requiresAncestor: property.requiresAncestor,
    category: property.category,
    priority: property.priority,
    validationRule: property.validationRule,
    deprecated: property.deprecated,
    structuredRef: property.structuredRef,
  );
}

DecompositionRecipe _recipeToConsumerShape(
  DecompositionRecipe recipe, {
  required String widgetName,
  required Map<WireId, String> propertyNameByWireId,
  required Map<WireId, String> structuredNameByWireId,
  required Map<WireId, String> structuredFieldNameByWireId,
}) {
  return DecompositionRecipe(
    structuredRef: recipe.structuredRef,
    flatProperties: recipe.flatProperties,
    targetArg: recipe.targetArg,
    construction: recipe.construction,
    fieldMappings: recipe.fieldMappings,
    discriminator: recipe.discriminator,
  );
}

Map<String, String> _projectLegacyFlatProperties(
  DecompositionRecipe recipe, {
  required String widgetName,
  required Map<WireId, String> propertyNameByWireId,
  required Map<WireId, String> structuredFieldNameByWireId,
}) {
  final result = <String, String>{};
  recipe.flatProperties.forEach((structuredFieldWireId, widgetPropertyWireId) {
    final flatName = propertyNameByWireId[widgetPropertyWireId];
    if (flatName == null) {
      throw CatalogSchemaException(
        'toConsumerShape: decomposition on $widgetName references widget '
        'property wire ID ${widgetPropertyWireId.value}, which is not a '
        'property of the widget.',
      );
    }
    // The structured-argument key equals the flat-property name in the curated
    // libraries (key == value). When the structured field name is itself
    // present in the catalog, assert the invariant so a future curation that
    // names a flat property differently from its structured argument fails
    // loudly here rather than silently mis-mapping the decomposition.
    final structuredFieldName =
        structuredFieldNameByWireId[structuredFieldWireId];
    if (structuredFieldName != null && structuredFieldName != flatName) {
      throw CatalogSchemaException(
        'toConsumerShape: decomposition on $widgetName maps structured field '
        "'$structuredFieldName' to differently-named flat property "
        "'$flatName'. The v2 consumer projection recovers the structured "
        'argument from the flat-property name and cannot represent a rename; '
        'align the names or migrate the consumer off the legacy projection.',
      );
    }
    result[flatName] = flatName;
  });
  return result;
}
