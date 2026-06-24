// Canonical-Catalog fixture builders for the Phase 11 diff-tool suites.
//
// Every builder defaults every field, so a test names only what it varies.
// The diff tool joins entries by (library, wireId); these builders carry
// real wire IDs, which the shipped legacy-v2 catalogs do not — see the
// Phase 11 plan, Hard Question A.
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Default library namespace used by the fixture builders.
const String testNamespace = 'restage.core';

/// Default library used by the fixture builders.
const WidgetLibrary testLibrary = WidgetLibrary.core;

/// Builds a `(library, wireId)` reference from a wire-ID string.
WireIdRef ref(String wireId, {String library = testNamespace}) =>
    WireIdRef(library: library, wireId: WireId(wireId));

/// Builds a `DeprecationInfo` carrying a catalog-lifecycle layer.
DeprecationInfo catalogDeprecation({
  String reason = 'Deprecated for test.',
  String at = '2026-02-01T00:00:00Z',
  WireIdRef? replaceWith,
  String? transitionId,
}) =>
    DeprecationInfo(
      catalog: CatalogDeprecationInfo(
        reason: reason,
        at: at,
        replaceWith: replaceWith,
        transitionId: transitionId,
      ),
    );

/// Builds a widget entry.
WidgetEntry widgetEntry({
  required String wireId,
  String name = 'TestWidget',
  WidgetLibrary library = testLibrary,
  WidgetCategory category = WidgetCategory.layout,
  String description = 'A test widget.',
  String flutterType = 'package:flutter/src/widgets/basic.dart#TestWidget',
  ChildrenSlot childrenSlot = ChildrenSlot.none,
  List<WidgetEventName> fires = const [],
  List<PropertyEntry> properties = const [],
  List<DecompositionRecipe> decomposes = const [],
  DeprecationInfo? deprecated,
}) =>
    WidgetEntry(
      wireId: WireId(wireId),
      name: name,
      library: library,
      category: category,
      description: description,
      flutterType: flutterType,
      childrenSlot: childrenSlot,
      fires: fires,
      properties: properties,
      decomposes: decomposes,
      deprecated: deprecated,
    );

/// Builds a widget-level property entry.
PropertyEntry propertyEntry({
  required String wireId,
  String name = 'testProp',
  PropertyType type = PropertyType.string,
  String description = 'A test property.',
  bool required = false,
  String? synthetic,
  DefaultValueSource? defaultSource,
  PropertyCategory? category,
  PropertyPriority? priority,
  DeprecationInfo? deprecated,
}) =>
    PropertyEntry(
      wireId: WireId(wireId),
      name: name,
      type: type,
      description: description,
      required: required,
      synthetic: synthetic,
      defaultSource: defaultSource,
      category: category,
      priority: priority,
      deprecated: deprecated,
    );

/// Builds a structured-type field.
StructuredField structuredField({
  required String wireId,
  String name = 'testField',
  PropertyType type = PropertyType.string,
  String description = 'A test field.',
  bool required = false,
  DefaultValueSource? defaultSource,
  PropertyCategory? category,
  PropertyPriority? priority,
  DeprecationInfo? deprecated,
}) =>
    StructuredField(
      wireId: WireId(wireId),
      name: name,
      type: type,
      description: description,
      required: required,
      defaultSource: defaultSource,
      category: category,
      priority: priority,
      deprecated: deprecated,
    );

/// Builds a factory variant.
FactoryVariant factoryVariant({
  required String wireId,
  VariantSourceKind sourceKind = VariantSourceKind.constructor,
  String? namedConstructor,
  String? staticAccessor,
  Map<String, ArgMapping> argMappings = const {},
  String description = 'A test variant.',
  DeprecationInfo? deprecated,
}) {
  switch (sourceKind) {
    case VariantSourceKind.constructor:
      return ConstructorVariant(
        wireId: WireId(wireId),
        namedConstructor: namedConstructor,
        argMappings: argMappings,
        description: description,
        deprecated: deprecated,
      );
    case VariantSourceKind.staticMethod:
      return StaticMethodVariant(
        wireId: WireId(wireId),
        staticAccessor: staticAccessor!,
        argMappings: argMappings,
        description: description,
        deprecated: deprecated,
      );
    case VariantSourceKind.staticGetter:
      return StaticGetterVariant(
        wireId: WireId(wireId),
        staticAccessor: staticAccessor!,
        description: description,
        deprecated: deprecated,
      );
    case VariantSourceKind.constValue:
      return ConstValueVariant(
        wireId: WireId(wireId),
        staticAccessor: staticAccessor!,
        description: description,
        deprecated: deprecated,
      );
  }
}

/// Builds a structured-type entry.
StructuredEntry structuredEntry({
  required String wireId,
  String name = 'TestStructured',
  WidgetLibrary library = testLibrary,
  String description = 'A test structured type.',
  String sourceType = 'package:flutter/src/painting/test.dart#TestStructured',
  List<StructuredField> fields = const [],
  List<FactoryVariant> variants = const [],
  DeprecationInfo? deprecated,
}) =>
    StructuredEntry(
      wireId: WireId(wireId),
      name: name,
      library: library,
      description: description,
      sourceType: sourceType,
      fields: fields,
      variants: variants,
      deprecated: deprecated,
    );

/// Builds a discriminated-union entry.
UnionEntry unionEntry({
  required String wireId,
  String name = 'TestUnion',
  WidgetLibrary library = testLibrary,
  String description = 'A test union.',
  String sourceType = 'package:flutter/src/painting/test.dart#TestUnion',
  List<String> memberSourceTypes = const [],
  DiscriminatorSpec discriminator =
      const DiscriminatorSpec(field: '_s', values: []),
  List<WireIdRef> members = const [],
  DeprecationInfo? deprecated,
}) =>
    UnionEntry(
      wireId: WireId(wireId),
      name: name,
      library: library,
      description: description,
      sourceType: sourceType,
      memberSourceTypes: memberSourceTypes,
      discriminator: discriminator,
      members: members,
      deprecated: deprecated,
    );

/// Builds a design-token entry.
DesignTokenEntry designTokenEntry({
  required String wireId,
  String name = 'testToken',
  WidgetLibrary library = testLibrary,
  DesignTokenType type = DesignTokenType.color,
  String? description,
  ThemeBindingPath? resolver,
  Object? literalFallback = 4294967295,
  DeprecationInfo? deprecated,
}) =>
    DesignTokenEntry(
      wireId: WireId(wireId),
      name: name,
      library: library,
      type: type,
      description: description,
      resolver: resolver,
      literalFallback: literalFallback,
      deprecated: deprecated,
    );

/// Builds a canonical catalog snapshot.
Catalog catalog({
  List<WidgetEntry> widgets = const [],
  List<StructuredEntry> structuredTypes = const [],
  List<UnionEntry> unions = const [],
  List<DesignTokenEntry> designTokens = const [],
  String generatedAt = '2026-01-01T00:00:00Z',
}) =>
    Catalog(
      schemaVersion: 3,
      generatedAt: generatedAt,
      libraries: {
        testLibrary: const LibraryInfo(version: '0.1.0'),
      },
      widgets: widgets,
      structuredTypes: structuredTypes,
      unions: unions,
      designTokens: designTokens,
    );
