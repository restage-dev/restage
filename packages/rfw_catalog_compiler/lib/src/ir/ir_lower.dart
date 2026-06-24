import 'package:rfw_catalog_compiler/src/ir/catalog_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/decomposition_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/design_token_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/factory_variant_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/property_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/structured_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/union_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/widget_ir.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Lowers a catalog IR root to the public schema.
Catalog lowerCatalog(CatalogIR ir) {
  final widgets = ir.widgets.map(lowerWidget).toList(growable: false);
  final structuredTypes =
      ir.structuredTypes.map(lowerStructured).toList(growable: false);
  final unions = ir.unions.map(lowerUnion).toList(growable: false);
  final designTokens =
      ir.designTokens.map(lowerDesignToken).toList(growable: false);

  final libraries = <WidgetLibrary>{
    ...ir.libraryVersions.keys,
    ...widgets.map((entry) => entry.library),
    ...structuredTypes.map((entry) => entry.library),
    ...unions.map((entry) => entry.library),
    ...designTokens.map((entry) => entry.library),
  };
  final missingVersionLibraries =
      libraries.where((library) => !ir.libraryVersions.containsKey(library));
  if (missingVersionLibraries.isNotEmpty) {
    final names = missingVersionLibraries
        .map((library) => library.namespace)
        .toList(growable: false)
      ..sort();
    throw StateError(
      'Missing library version metadata for ${names.join(', ')}.',
    );
  }

  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: ir.generatedAt,
    flutterVersion: ir.flutterVersion,
    libraries: {
      for (final library in libraries)
        library: LibraryInfo(
          version: ir.libraryVersions[library]!,
          capabilityVersion: ir.libraryCapabilityVersions[library],
        ),
    },
    widgets: widgets,
    structuredTypes: structuredTypes,
    unions: unions,
    designTokens: designTokens,
  );
}

/// Lowers one widget IR entry to the public schema.
WidgetEntry lowerWidget(WidgetIR ir) {
  return WidgetEntry(
    wireId: ir.wireId,
    name: ir.name,
    library: ir.library,
    category: ir.category,
    description: ir.description,
    flutterType: ir.provenance.flutterType,
    childrenSlot: ir.childrenSlot,
    fires: ir.fires,
    properties: ir.properties.map(lowerProperty).toList(growable: false),
    decomposes: ir.decomposes.map(lowerDecomposition).toList(growable: false),
    sinceVersion: ir.sinceVersion,
    deprecatedSince: ir.deprecatedSince,
    stability: ir.stability,
    deprecated: ir.deprecated,
  );
}

/// Lowers one property IR entry to the public schema.
PropertyEntry lowerProperty(PropertyIR ir) {
  return PropertyEntry(
    wireId: ir.wireId,
    name: ir.name,
    type: ir.type.loweredPropertyType,
    description: ir.description,
    required: ir.required,
    defaultBrandToken: ir.legacyDefaultBrandToken,
    synthetic: ir.metadata.synthetic,
    positional: ir.positional,
    enumType: ir.enumType,
    widgetType: ir.widgetType,
    callbackSignature: ir.callbackSignature ?? ir.type.callbackSignature,
    firesAs: ir.metadata.firesAs,
    defaultSource: ir.defaultSource?.lowered,
    mutuallyExclusiveWith: ir.metadata.mutuallyExclusiveWith,
    requiresAncestor: ir.metadata.requiresAncestor,
    category: ir.metadata.category,
    priority: ir.metadata.priority,
    validationRule: ir.metadata.validationRule,
    deprecated: ir.metadata.deprecated,
    structuredRef: ir.type.structuredRef,
    valueShape: ir.type.valueShape,
  );
}

/// Lowers one decomposition IR entry to the public schema.
DecompositionRecipe lowerDecomposition(DecompositionIR ir) {
  return DecompositionRecipe(
    structuredRef: ir.structuredRef,
    flatProperties: ir.flatPropertyRefs,
    targetArg: ir.targetArg,
    construction: ir.construction,
    fieldMappings: ir.fieldMappings,
    parameterMappings: ir.parameterMappings,
    discriminator: ir.discriminator,
  );
}

/// Lowers one structured type IR entry to the public schema.
StructuredEntry lowerStructured(StructuredIR ir) {
  return StructuredEntry(
    wireId: ir.wireId,
    name: ir.name,
    library: ir.library,
    description: ir.description,
    sourceType: ir.provenance.flutterType,
    fields: ir.fields.map(lowerStructuredField).toList(growable: false),
    variants: ir.variants.map(lowerFactoryVariant).toList(growable: false),
    stability: ir.stability,
    deprecated: ir.deprecated,
  );
}

/// Lowers one structured field IR entry to the public schema.
StructuredField lowerStructuredField(StructuredFieldIR ir) {
  return StructuredField(
    wireId: ir.wireId,
    name: ir.name,
    type: ir.type.loweredPropertyType,
    description: ir.description,
    required: ir.required,
    defaultSource: ir.defaultSource?.lowered,
    category: ir.metadata.category,
    priority: ir.metadata.priority,
    deprecated: ir.metadata.deprecated,
    structuredRef: ir.type.structuredRef,
    unionRef: ir.type.unionRef,
    valueShape: ir.type.valueShape,
  );
}

/// Lowers one factory variant IR entry to the public schema, selecting the
/// sealed subtype for the IR's [FactoryVariantIR.sourceKind].
FactoryVariant lowerFactoryVariant(FactoryVariantIR ir) {
  switch (ir.sourceKind) {
    case VariantSourceKind.constructor:
      return ConstructorVariant(
        wireId: ir.wireId,
        namedConstructor: ir.namedConstructor,
        argMappings: ir.argMappings,
        parameters: ir.parameters,
        description: ir.description,
        deprecated: ir.deprecated,
      );
    case VariantSourceKind.staticMethod:
      return StaticMethodVariant(
        wireId: ir.wireId,
        staticAccessor: _requireIrStaticAccessor(ir),
        argMappings: ir.argMappings,
        parameters: ir.parameters,
        description: ir.description,
        deprecated: ir.deprecated,
      );
    case VariantSourceKind.staticGetter:
      return StaticGetterVariant(
        wireId: ir.wireId,
        staticAccessor: _requireIrStaticAccessor(ir),
        description: ir.description,
        deprecated: ir.deprecated,
      );
    case VariantSourceKind.constValue:
      return ConstValueVariant(
        wireId: ir.wireId,
        staticAccessor: _requireIrStaticAccessor(ir),
        description: ir.description,
        deprecated: ir.deprecated,
      );
  }
}

/// A static method / getter / const-field IR entry carries its accessor name;
/// the enumerator guarantees it. This guards a malformed IR rather than
/// relaxing the sealed schema type's non-null accessor.
String _requireIrStaticAccessor(FactoryVariantIR ir) {
  final accessor = ir.staticAccessor;
  if (accessor == null) {
    throw StateError(
      'FactoryVariantIR ${ir.wireId} of kind ${ir.sourceKind.name} has no '
      'staticAccessor',
    );
  }
  return accessor;
}

/// Lowers one union IR entry to the public schema.
UnionEntry lowerUnion(UnionIR ir) {
  return UnionEntry(
    wireId: ir.wireId,
    name: ir.name,
    library: ir.library,
    description: ir.description,
    sourceType: ir.sourceType,
    memberSourceTypes: ir.memberSourceTypes,
    discriminator: ir.discriminator,
    members: ir.members,
    stability: ir.stability,
    deprecated: ir.deprecated,
  );
}

/// Lowers one design token IR entry to the public schema.
DesignTokenEntry lowerDesignToken(DesignTokenIR ir) {
  return DesignTokenEntry(
    wireId: ir.wireId,
    name: ir.name,
    library: ir.library,
    type: ir.type,
    description: ir.description,
    resolver: ir.resolver,
    literalFallback: ir.literalFallback,
    stability: ir.stability,
    deprecated: ir.deprecated,
  );
}
