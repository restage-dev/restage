import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:rfw_catalog_compiler/src/policy/policy_ledger.dart';
import 'package:rfw_catalog_compiler/src/walker/abstract_type_fallback.dart';
import 'package:rfw_catalog_compiler/src/walker/element_fqn.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Resolves the semantic [CatalogValueShape] of a Dart [type].
///
/// This is the single value-shape resolver shared by the two catalog
/// producers: the recipe path (which decomposes a structured type's
/// constructor parameters) and the structured walker (which materializes a
/// structured type's fields). Sharing one resolver keeps the two producers
/// from disagreeing about how a value type lowers — an enum, a typed scalar,
/// a `List<T>`, or a `WidgetStateProperty<T>` resolves to the same shape
/// wherever it appears.
///
/// Resolution order:
///
/// 1. `WidgetStateProperty<T>` unwraps to the shape of its single type
///    argument `T` (per-state resolution is a runtime concern, not a
///    catalog-shape one).
/// 2. A Dart `enum` lowers to an [EnumShape] carrying its source-qualified
///    type.
/// 3. A recognized scalar (`bool` / `int` / `double` / `Color` / `EdgeInsets`
///    / `FontWeight` / `Duration` / …) lowers to a [ScalarShape].
/// 4. A registered abstract-union base (`Gradient` / `BoxBorder` /
///    `ShapeBorder`) lowers to a [UnionShape] and records its FQN into
///    [referencedUnionFqns] for the union back-pass.
/// 5. A `List<T>` of a recognized scalar item lowers to a [ListShape]; a
///    `List<BoxShadow>` lowers to the boxed box-shadow list shape.
/// 6. A known recipe structured type ([knownRecipeStructuredTypes]) lowers to
///    a [StructuredShape] whose `structuredRef` is resolved by a later pass.
///
/// Returns null for any type that does not map to a catalog value shape.
///
/// [library] and [policy] are required for the union path (resolving a
/// registered abstract base and minting its library-qualified reference); the
/// scalar/enum/list paths work without them.
CatalogValueShape? resolveValueShape(
  DartType type, {
  WidgetLibrary? library,
  PolicyLedger? policy,
  Set<String>? referencedUnionFqns,
}) {
  final widgetStateValueType = _widgetStatePropertyValueType(type);
  if (widgetStateValueType != null) {
    return resolveValueShape(
      widgetStateValueType,
      library: library,
      policy: policy,
      referencedUnionFqns: referencedUnionFqns,
    );
  }

  final enumElement = type.element;
  if (enumElement is EnumElement) {
    return EnumShape(
      propertyType: PropertyType.enumValue,
      enumRef: DartTypeRef(
        libraryUri: enumElement.library.identifier,
        symbolName: enumElement.name ?? '<unnamed>',
      ),
    );
  }

  final scalar = _scalarShapeForDartType(type);
  if (scalar != null) return scalar;

  final unionShape = _unionValueShapeForDartType(
    type,
    library: library,
    policy: policy,
    referencedUnionFqns: referencedUnionFqns,
  );
  if (unionShape != null) return unionShape;

  final listShape = _listValueShapeForDartType(type);
  if (listShape != null) return listShape;

  final listElement = _structuredListElement(type);
  if (listElement?.name == 'BoxShadow' && library != null) {
    return ListShape(
      propertyType: PropertyType.boxShadowList,
      itemShape: StructuredShape(
        propertyType: PropertyType.structured,
        structuredRef: WireIdRef(
          library: library.namespace,
          wireId: WireId.unallocatedStructured,
        ),
      ),
      wireCodec: CatalogWireCodec.rfwBoxShadowList,
    );
  }

  final structuredElement = classElementFor(type);
  if (structuredElement != null &&
      library != null &&
      knownRecipeStructuredTypes.contains(structuredElement.name)) {
    return StructuredShape(
      propertyType: PropertyType.structured,
      structuredRef: WireIdRef(
        library: library.namespace,
        wireId: WireId.unallocatedStructured,
      ),
    );
  }
  return null;
}

/// Whether [shape] carries a reference that a later linking pass must resolve.
///
/// A [StructuredShape] or [UnionShape] points at a catalog entry whose wire ID
/// is assigned by the allocator/back-pass; a [ListShape] needs linking when
/// its item shape does. Scalar and enum shapes are self-contained.
bool valueShapeNeedsLinking(CatalogValueShape? shape) {
  return switch (shape) {
    null => false,
    StructuredShape() || UnionShape() => true,
    ListShape(:final itemShape) => valueShapeNeedsLinking(itemShape),
    ScalarShape() || EnumShape() => false,
  };
}

/// Structured value types the recipe path decomposes natively. A field or
/// parameter of one of these resolves to a [StructuredShape] whose
/// `structuredRef` points at the type's own catalog entry.
const Set<String> knownRecipeStructuredTypes = {
  'BorderRadius',
  'BorderSide',
  'BoxDecoration',
  'BoxShadow',
  'ButtonStyle',
  'RoundedRectangleBorder',
  'Size',
  'TextStyle',
};

/// The canonical Flutter FQN of `WidgetStateProperty`. The unwrap is gated on
/// this identity so a lookalike project type merely *named*
/// `WidgetStateProperty` (from a non-Flutter library) is not mis-shaped as the
/// Flutter carrier.
const String _kWidgetStatePropertyFqn =
    'package:flutter/src/widgets/widget_state.dart#WidgetStateProperty';

DartType? _widgetStatePropertyValueType(DartType type) {
  if (type is! InterfaceType || type.typeArguments.length != 1) return null;
  final element = type.element;
  if (element.name != 'WidgetStateProperty') return null;
  // Require the canonical Flutter FQN before unwrapping. The identity is read
  // off the element's defining library, so a lookalike project type merely
  // named `WidgetStateProperty` (a different library) does not match.
  if (interfaceFqnOrNull(element) != _kWidgetStatePropertyFqn) return null;
  return type.typeArguments.single;
}

CatalogValueShape? _unionValueShapeForDartType(
  DartType type, {
  WidgetLibrary? library,
  PolicyLedger? policy,
  Set<String>? referencedUnionFqns,
}) {
  if (library == null || policy == null) return null;
  final fqn = typeFqn(type);
  if (fqn == null || policy.unionRegistry.lookup(fqn) == null) return null;
  referencedUnionFqns?.add(fqn);
  final propertyType = switch (_typeDisplayName(type)) {
    'Gradient' => PropertyType.gradient,
    'BoxBorder' => PropertyType.border,
    'ShapeBorder' => PropertyType.shapeBorder,
    'OutlinedBorder' => PropertyType.shapeBorder,
    _ => abstractStructuredFallback(type),
  };
  final wireCodec = switch (propertyType) {
    PropertyType.gradient => CatalogWireCodec.rfwGradient,
    PropertyType.border => CatalogWireCodec.rfwBorder,
    PropertyType.shapeBorder => CatalogWireCodec.rfwShapeBorder,
    _ => null,
  };
  if (propertyType == null || wireCodec == null) return null;
  return UnionShape(
    propertyType: propertyType,
    unionRef: WireIdRef(
      library: library.namespace,
      wireId: WireId.unallocatedUnion,
    ),
    wireCodec: wireCodec,
  );
}

CatalogValueShape? _scalarShapeForDartType(DartType type) {
  final propertyType = switch (_typeDisplayName(type)) {
    'bool' => PropertyType.boolean,
    'int' => PropertyType.integer,
    'double' || 'num' => PropertyType.real,
    'String' => PropertyType.string,
    'Color' => PropertyType.color,
    'EdgeInsets' ||
    'EdgeInsetsGeometry' ||
    'EdgeInsetsDirectional' =>
      PropertyType.edgeInsets,
    'Alignment' ||
    'AlignmentGeometry' ||
    'AlignmentDirectional' =>
      PropertyType.alignment,
    'Offset' => PropertyType.offset,
    'FontWeight' => PropertyType.fontWeight,
    'Duration' => PropertyType.duration,
    'Curve' => PropertyType.curve,
    'Locale' => PropertyType.locale,
    'Paint' => PropertyType.paint,
    'TextDecoration' => PropertyType.textDecoration,
    _ => null,
  };
  if (propertyType == null) return null;
  return ScalarShape(
    propertyType: propertyType,
    dartTypeRef: _dartTypeRef(type),
  );
}

CatalogValueShape? _listValueShapeForDartType(DartType type) {
  if (type is! InterfaceType) return null;
  final displayName = _typeDisplayName(type);
  if (displayName != 'List' && !displayName.startsWith('List<')) return null;
  if (type.typeArguments.length != 1) return null;
  final itemType = type.typeArguments.single;
  final itemDisplayName = _typeDisplayName(itemType);
  final propertyType = switch (itemDisplayName) {
    'String' => PropertyType.stringList,
    'Shadow' => PropertyType.shadowList,
    'FontFeature' => PropertyType.fontFeatureList,
    'FontVariation' => PropertyType.fontVariationList,
    _ => null,
  };
  if (propertyType == null) return null;
  return ListShape(
    propertyType: propertyType,
    itemShape: ScalarShape(
      propertyType:
          itemDisplayName == 'String' ? PropertyType.string : propertyType,
      dartTypeRef: _dartTypeRef(itemType),
    ),
  );
}

ClassElement? _structuredListElement(DartType type) {
  final displayName = _typeDisplayName(type);
  if (type is! InterfaceType ||
      (displayName != 'List' && !displayName.startsWith('List<'))) {
    return null;
  }
  if (type.typeArguments.length != 1) return null;
  return classElementFor(type.typeArguments.single);
}

DartTypeRef? _dartTypeRef(DartType type) {
  final element = type.element;
  final name = element?.name;
  final library = element?.library;
  if (name == null || name.isEmpty || library == null) return null;
  return DartTypeRef(libraryUri: library.identifier, symbolName: name);
}

String _typeDisplayName(DartType type) {
  final displayName = type.getDisplayString();
  if (displayName.endsWith('?') || displayName.endsWith('*')) {
    return displayName.substring(0, displayName.length - 1);
  }
  return displayName;
}
