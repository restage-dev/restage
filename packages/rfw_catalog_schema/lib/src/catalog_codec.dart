import 'dart:convert';

import 'package:rfw_catalog_schema/src/catalog.dart';
import 'package:rfw_catalog_schema/src/compat_rule.dart';
import 'package:rfw_catalog_schema/src/decomposition_recipe.dart';
import 'package:rfw_catalog_schema/src/default_source_codec.dart';
import 'package:rfw_catalog_schema/src/default_value_source.dart';
import 'package:rfw_catalog_schema/src/deprecation_info.dart';
import 'package:rfw_catalog_schema/src/design_token.dart';
import 'package:rfw_catalog_schema/src/discriminator_spec.dart';
import 'package:rfw_catalog_schema/src/factory_variant.dart';
import 'package:rfw_catalog_schema/src/library_info.dart';
import 'package:rfw_catalog_schema/src/native_decompose.dart';
import 'package:rfw_catalog_schema/src/property_entry.dart';
import 'package:rfw_catalog_schema/src/property_metadata.dart';
import 'package:rfw_catalog_schema/src/property_type.dart';
import 'package:rfw_catalog_schema/src/stability.dart';
import 'package:rfw_catalog_schema/src/structured_entry.dart';
import 'package:rfw_catalog_schema/src/union_entry.dart';
import 'package:rfw_catalog_schema/src/validation_expr.dart';
import 'package:rfw_catalog_schema/src/widget_entry.dart';
import 'package:rfw_catalog_schema/src/widget_library.dart';
import 'package:rfw_catalog_schema/src/widget_metadata.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// Schema version emitted by [encodeCatalog] and accepted by
/// [decodeCatalog].
///
/// This codec speaks the canonical wire shape: wire IDs on every entry,
/// discriminated default sources, library envelope counts for each kind,
/// the structured/union/design-token sections, and the compatibility-rule
/// emission slot. Production catalog readers are current-only; historical
/// wire shapes belong in isolated fixtures, not runtime decode paths.
const int kSupportedSchemaVersion = 4;

/// Thrown when JSON parsing fails or schema version doesn't match.
class CatalogSchemaException implements Exception {
  /// Create an exception with [message] explaining the failure.
  CatalogSchemaException(this.message);

  /// Human-readable description of why decoding failed.
  final String message;

  @override
  String toString() => 'CatalogSchemaException: $message';
}

/// Encode [catalog] as a pretty-printed JSON string in the canonical
/// schema wire shape.
String encodeCatalog(Catalog catalog) {
  _validateCanonicalCatalog(catalog);
  return const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': kSupportedSchemaVersion,
    'generatedAt': catalog.generatedAt,
    if (catalog.flutterVersion != null)
      'flutterVersion': catalog.flutterVersion,
    'libraries': {
      for (final entry in catalog.libraries.entries)
        entry.key.namespace: {
          'version': entry.value.version,
          // Omitted when the library declared no capability version (built-ins
          // always omit it). Conditional-omit keeps the committed catalogs
          // byte-neutral and mirrors the `sinceVersion` discipline.
          if (entry.value.capabilityVersion != null)
            'capabilityVersion': entry.value.capabilityVersion,
        },
    },
    'widgets': catalog.widgets.map(_widgetToJson).toList(),
    if (catalog.structuredTypes.isNotEmpty)
      'structuredTypes':
          catalog.structuredTypes.map(_structuredToJson).toList(),
    if (catalog.unions.isNotEmpty)
      'unions': catalog.unions.map(_unionToJson).toList(),
    if (catalog.designTokens.isNotEmpty)
      'designTokens': catalog.designTokens.map(_designTokenToJson).toList(),
    if (catalog.compatRules != null && catalog.compatRules!.isNotEmpty)
      'compatRules': catalog.compatRules!.map(_compatRuleToJson).toList(),
  });
}

void _validateCanonicalCatalog(Catalog catalog) {
  if (catalog.schemaVersion != kSupportedSchemaVersion) {
    throw CatalogSchemaException(
      'Cannot encode catalog schemaVersion ${catalog.schemaVersion} as the '
      'canonical v$kSupportedSchemaVersion wire shape. Convert legacy '
      'catalogs at an explicit boundary first.',
    );
  }
  for (final entry in catalog.libraries.entries) {
    _validateCapabilityVersion(
      entry.value.capabilityVersion,
      'libraries["${entry.key.namespace}"].capabilityVersion',
    );
  }
  for (var i = 0; i < catalog.widgets.length; i++) {
    _validateWidget(catalog.widgets[i], 'widgets[$i]');
  }
  for (var i = 0; i < catalog.structuredTypes.length; i++) {
    _validateStructured(catalog.structuredTypes[i], 'structuredTypes[$i]');
  }
  for (var i = 0; i < catalog.unions.length; i++) {
    _validateUnion(catalog.unions[i], 'unions[$i]');
  }
  for (var i = 0; i < catalog.designTokens.length; i++) {
    _validateDesignToken(catalog.designTokens[i], 'designTokens[$i]');
  }
  final compatRules = catalog.compatRules;
  if (compatRules != null) {
    for (var i = 0; i < compatRules.length; i++) {
      _validateCompatRule(compatRules[i], 'compatRules[$i]');
    }
  }
}

void _validateWidget(WidgetEntry widget, String path) {
  final widgetPath = '$path "${widget.name}"';
  _expectWireIdKind(
    widget.wireId,
    WireIdKind.widget,
    '$widgetPath.wireId',
  );
  _validateSinceVersion(widget.sinceVersion, '$widgetPath.sinceVersion');
  for (var i = 0; i < widget.properties.length; i++) {
    _validateProperty(widget.properties[i], '$widgetPath.properties[$i]');
  }
  for (var i = 0; i < widget.decomposes.length; i++) {
    _validateDecomposition(
      widget.decomposes[i],
      '$widgetPath.decomposes[$i]',
    );
  }
  _validateDeprecation(widget.deprecated, '$widgetPath.deprecated');
}

void _validateProperty(PropertyEntry property, String path) {
  _expectWireIdKind(property.wireId, WireIdKind.property, '$path.wireId');
  _validateDefaultSource(property.defaultSource, '$path.defaultSource');
  final mutex = property.mutuallyExclusiveWith;
  if (mutex != null) {
    for (var i = 0; i < mutex.length; i++) {
      _expectWireIdKind(
        mutex[i],
        WireIdKind.property,
        '$path.mutuallyExclusiveWith[$i]',
      );
    }
  }
  final structuredRef = property.structuredRef;
  if (structuredRef != null) {
    _validateWireIdRef(
      structuredRef,
      '$path.structuredRef',
      expectedKind: WireIdKind.structured,
    );
  }
  _requireEnumIdentity(property, path);
  _validateValueShape(property.valueShape, '$path.valueShape');
  _validateDeprecation(property.deprecated, '$path.deprecated');
}

/// An `enumValue`-typed property must carry enum identity so the catalog
/// constrains the slot to a known member set rather than accepting any string.
///
/// Identity may arrive either way (the OR form — both are valid carriers and
/// real catalogs use both):
///
/// * a non-empty `enumType` naming the Dart enum declaration, or
/// * an [EnumShape] `valueShape`, which carries the source-qualified enum
///   reference (`enumRef`).
///
/// Without at least one of these, nothing pins the slot to a member set and
/// the validator would accept an arbitrary string — a silent-loss class. This
/// guard runs on the encode / native-coherence validation path, so a catalog
/// missing both can never be written.
void _requireEnumIdentity(PropertyEntry property, String path) {
  if (property.type != PropertyType.enumValue) return;
  final enumType = property.enumType;
  final hasEnumType = enumType != null && enumType.isNotEmpty;
  final hasEnumShape = property.valueShape is EnumShape;
  if (hasEnumType || hasEnumShape) return;
  throw CatalogSchemaException(
    '$path: enumValue property must carry enumType or an EnumShape (enumRef)',
  );
}

void _validateDecomposition(DecompositionRecipe recipe, String path) {
  _validateWireIdRef(
    recipe.structuredRef,
    '$path.structuredRef',
    expectedKind: WireIdKind.structured,
  );
  for (final entry in recipe.flatProperties.entries) {
    _expectWireIdKind(
      entry.key,
      WireIdKind.property,
      '$path.flatProperties (key)',
    );
    _expectWireIdKind(
      entry.value,
      WireIdKind.property,
      '$path.flatProperties[${entry.key}]',
    );
  }
  if (recipe.targetArg != null && recipe.targetArg!.isEmpty) {
    throw CatalogSchemaException('$path.targetArg: must not be empty');
  }
  _validateFactoryInvocation(recipe.construction, '$path.construction');
  for (var i = 0; i < recipe.fieldMappings.length; i++) {
    _validateFieldMapping(recipe.fieldMappings[i], '$path.fieldMappings[$i]');
  }
  for (var i = 0; i < recipe.parameterMappings.length; i++) {
    _validateParameterMapping(
      recipe.parameterMappings[i],
      '$path.parameterMappings[$i]',
    );
  }
  _validateDiscriminator(recipe.discriminator, '$path.discriminator');
}

void _validateStructured(StructuredEntry entry, String path) {
  final structuredPath = '$path "${entry.name}"';
  _expectWireIdKind(
    entry.wireId,
    WireIdKind.structured,
    '$structuredPath.wireId',
  );
  for (var i = 0; i < entry.fields.length; i++) {
    _validateStructuredField(entry.fields[i], '$structuredPath.fields[$i]');
  }
  for (var i = 0; i < entry.variants.length; i++) {
    _validateFactoryVariant(
      entry.variants[i],
      '$structuredPath.variants[$i]',
    );
  }
  _validateDeprecation(entry.deprecated, '$structuredPath.deprecated');
}

void _validateStructuredField(StructuredField field, String path) {
  _expectWireIdKind(field.wireId, WireIdKind.property, '$path.wireId');
  _validateDefaultSource(field.defaultSource, '$path.defaultSource');
  // The ref/type-shape contract (mutual exclusion + structured-needs-a-ref +
  // placement-by-type). Shared with the decoder so the encode / local-build
  // path is held to the same contract as the wire-decode path.
  _checkStructuredFieldRefShape(field, path);
  final structuredRef = field.structuredRef;
  final unionRef = field.unionRef;
  if (structuredRef != null) {
    _validateWireIdRef(
      structuredRef,
      '$path.structuredRef',
      expectedKind: WireIdKind.structured,
    );
  }
  if (unionRef != null) {
    _validateWireIdRef(
      unionRef,
      '$path.unionRef',
      expectedKind: WireIdKind.union,
    );
  }
  _validateValueShape(field.valueShape, '$path.valueShape');
  _validateDeprecation(field.deprecated, '$path.deprecated');
}

/// A [StructuredField]'s structured-slot references must be coherent with its
/// [PropertyType]:
///
/// * `structuredRef` and `unionRef` are mutually exclusive.
/// * a `structured`-typed field must carry exactly one of them — it resolves
///   to a concrete structured entry (`structuredRef`) or to a discriminated
///   union of structured entries (`unionRef`).
/// * a structured-slot reference (`structuredRef` or `unionRef`) is valid only
///   on a `structured`-typed field OR a union-category field (the
///   discriminated-union types in [_unionShapePropertyTypes] — border /
///   gradient / shapeBorder). Either reference kind is allowed on those types:
///   a union-category field usually resolves to a discriminated union
///   (`unionRef`), but when a widget accepts a single concrete variant it
///   resolves to that one concrete structured entry (`structuredRef`) instead
///   — e.g. a property typed `LinearGradient` rather than the `Gradient`
///   union.
///
/// `PropertyType.unknown` (the additive forward-compat sentinel) is exempt from
/// the placement rules: a payload from a newer schema may carry a field whose
/// type name this build does not recognize yet, and rejecting a ref on it would
/// break decode forward-compat. (Mirrors [_validatePropertyTypeForKind]'s
/// `unknown` exemption — broad over tight on the forward-compat sentinel.) The
/// mutual-exclusion and structured-needs-a-ref checks still apply to `unknown`,
/// since those are structural rather than type-placement rules.
///
/// The placement check keys off [_unionShapePropertyTypes] — the same
/// union-shape classification the codec and the catalog producer already use —
/// rather than a hardcoded type list, so the "which property types may carry a
/// structured-slot ref" set lives in exactly one place and a future
/// union-category type is covered automatically.
///
/// Enforced at BOTH decode (`_structuredFieldFromJson`, the load-bearing
/// customer-import path that covers plain `decodeCatalog`) and the encode /
/// `requireNativeCatalog` validation (`_validateStructuredField`).
void _checkStructuredFieldRefShape(StructuredField field, String path) {
  final type = field.type;
  final structuredRef = field.structuredRef;
  final unionRef = field.unionRef;
  if (structuredRef != null && unionRef != null) {
    throw CatalogSchemaException(
      '$path: a structured field carries both a structuredRef and a unionRef; '
      'they are mutually exclusive',
    );
  }
  if (type == PropertyType.structured &&
      structuredRef == null &&
      unionRef == null) {
    throw CatalogSchemaException(
      '$path: a structured-typed field must carry a structuredRef '
      '(concrete) or a unionRef (discriminated union)',
    );
  }
  if (type == PropertyType.unknown) return;
  if ((structuredRef != null || unionRef != null) &&
      type != PropertyType.structured &&
      !_unionShapePropertyTypes.contains(type)) {
    throw CatalogSchemaException(
      '$path: a structuredRef / unionRef is only valid on a structured-typed '
      'or union-category (border / gradient / shapeBorder) field; '
      'got PropertyType.${type.name}',
    );
  }
}

void _validateFactoryVariant(FactoryVariant variant, String path) {
  _expectWireIdKind(variant.wireId, WireIdKind.variant, '$path.wireId');
  // Argument mappings and callable parameters exist only on the callable
  // kinds (constructor / static method); the accessor kinds (static getter /
  // const field) are zero-arg and carry neither — structurally, via the
  // sealed subtype.
  switch (variant) {
    case ConstructorVariant(:final argMappings, :final parameters) ||
          StaticMethodVariant(:final argMappings, :final parameters):
      for (final entry in argMappings.entries) {
        for (var i = 0; i < entry.value.targetFields.length; i++) {
          _expectWireIdKind(
            entry.value.targetFields[i],
            WireIdKind.property,
            '$path.argMappings["${entry.key}"][$i]',
          );
        }
      }
      for (var i = 0; i < parameters.length; i++) {
        _validateFactoryParameter(parameters[i], '$path.parameters[$i]');
      }
    case StaticGetterVariant() || ConstValueVariant():
      break;
  }
  _validateDeprecation(variant.deprecated, '$path.deprecated');
}

void _validateFactoryParameter(FactoryParameter parameter, String path) {
  _expectWireIdKind(parameter.wireId, WireIdKind.parameter, '$path.wireId');
  switch (parameter.kind) {
    case FactoryParameterKind.named:
      if (parameter.name == null || parameter.name!.isEmpty) {
        throw CatalogSchemaException(
          '$path.name: named parameter requires name',
        );
      }
      if (parameter.position != null) {
        throw CatalogSchemaException(
          '$path.position: named parameter must not carry position',
        );
      }
    case FactoryParameterKind.positional:
      if (parameter.position == null || parameter.position! < 0) {
        throw CatalogSchemaException(
          '$path.position: positional parameter requires non-negative position',
        );
      }
      if (parameter.name != null) {
        throw CatalogSchemaException(
          '$path.name: positional parameter must not carry name',
        );
      }
  }
  _validateParameterDefaultValue(
    parameter.defaultValue,
    parameter.valueShape,
    '$path.defaultValue',
  );
  _validateValueShape(parameter.valueShape, '$path.valueShape');
}

void _validateParameterDefaultValue(
  FactoryParameterDefaultValue? defaultValue,
  CatalogValueShape valueShape,
  String path,
) {
  if (defaultValue == null) return;
  switch (defaultValue) {
    case LiteralParameterDefault(:final value):
      if (value is! bool &&
          value is! int &&
          value is! double &&
          value is! String) {
        throw CatalogSchemaException(
          '$path.value: literal default must be bool, int, double, or String; '
          'got ${value.runtimeType}',
        );
      }
      if (!_literalDefaultMatchesShape(value, valueShape)) {
        throw CatalogSchemaException(
          '$path.value: literal default $value is not compatible with '
          'PropertyType.${valueShape.propertyType.name}',
        );
      }
    case StaticMemberParameterDefault(:final staticType, :final memberName):
      _validateDartTypeRef(staticType, '$path.staticType');
      if (memberName.isEmpty) {
        throw CatalogSchemaException(
          '$path.memberName: static member default requires memberName',
        );
      }
  }
}

bool _literalDefaultMatchesShape(Object? value, CatalogValueShape shape) {
  switch (shape.propertyType) {
    case PropertyType.boolean:
      return value is bool;
    case PropertyType.integer:
      return value is int;
    case PropertyType.real:
    case PropertyType.length:
      return value is int || value is double;
    case PropertyType.string:
    case PropertyType.enumValue:
    case PropertyType.curve:
      return value is String;
    case PropertyType.color:
    case PropertyType.fontWeight:
    case PropertyType.duration:
      return value is int;
    case PropertyType.widget:
    case PropertyType.widgetList:
    case PropertyType.edgeInsets:
    case PropertyType.alignment:
    case PropertyType.alignmentXY:
    case PropertyType.offset:
    case PropertyType.stringList:
    case PropertyType.booleanList:
    case PropertyType.event:
    case PropertyType.dataReference:
    case PropertyType.gradient:
    case PropertyType.border:
    case PropertyType.boxShadowList:
    case PropertyType.locale:
    case PropertyType.paint:
    case PropertyType.shadowList:
    case PropertyType.fontFeatureList:
    case PropertyType.fontVariationList:
    case PropertyType.textDecoration:
    case PropertyType.shapeBorder:
    case PropertyType.structured:
    // A recursive span map is never a bare literal default.
    case PropertyType.inlineSpan:
    // A self-describing image map is never a bare literal default.
    case PropertyType.decorationImage:
    // A list of option maps is never a bare literal default.
    case PropertyType.selectionOptionList:
    case PropertyType.unknown:
      return false;
  }
}

void _validateDartTypeRef(DartTypeRef ref, String path) {
  if (ref.libraryUri.isEmpty) {
    throw CatalogSchemaException('$path.libraryUri: must not be empty');
  }
  if (ref.symbolName.isEmpty) {
    throw CatalogSchemaException('$path.symbolName: must not be empty');
  }
}

/// PropertyTypes a `UnionShape` may carry — the discriminated-union types.
const Set<PropertyType> _unionShapePropertyTypes = {
  PropertyType.border,
  PropertyType.gradient,
  PropertyType.shapeBorder,
};

/// PropertyTypes a `ListShape` may carry — the list-category types.
const Set<PropertyType> _listShapePropertyTypes = {
  PropertyType.widgetList,
  PropertyType.stringList,
  PropertyType.booleanList,
  PropertyType.boxShadowList,
  PropertyType.shadowList,
  PropertyType.fontFeatureList,
  PropertyType.fontVariationList,
};

/// The propertyType-compat invariant: a value shape's [PropertyType] must be
/// consistent with its shape `kind` (BROAD-scalar rule). The subtype
/// constructors carry a debug-mode mirror assert; this is the canonical
/// enforcement.
///
/// `PropertyType.unknown` (the additive forward-compat sentinel) is exempt on
/// every kind — an unrecognized wire propertyType name decodes to `unknown`
/// and must stay opaque rather than be rejected.
void _validatePropertyTypeForKind(
  String kind,
  PropertyType propertyType,
  String path,
) {
  if (propertyType == PropertyType.unknown) return;
  final bool ok;
  switch (kind) {
    case 'scalar':
      // The catch-all single-value category: anything that is not one of the
      // two categorical types with a dedicated subtype.
      ok = propertyType != PropertyType.enumValue &&
          propertyType != PropertyType.structured;
    case 'enumValue':
      ok = propertyType == PropertyType.enumValue;
    case 'structured':
      ok = propertyType == PropertyType.structured;
    case 'union':
      ok = _unionShapePropertyTypes.contains(propertyType);
    case 'list':
      ok = _listShapePropertyTypes.contains(propertyType);
    default:
      // An unrecognized kind is rejected by the constructing switch; nothing
      // to check here.
      return;
  }
  if (!ok) {
    throw CatalogSchemaException(
      '$path: $kind value shape carries incompatible '
      'PropertyType.${propertyType.name}',
    );
  }
}

void _validateValueShape(CatalogValueShape? shape, String path) {
  if (shape == null) return;
  // The per-category reference fields are now non-null by construction; the
  // remaining cross-field invariants are the self-contained per-shape checks
  // (propertyType-compat and the wireCodec-placement check — both also run at
  // decode in _valueShapeFromJson, pre-construction), the wire-ID kinds, and
  // list recursion.
  final kind = catalogValueShapeKindName(shape);
  _validatePropertyTypeForKind(kind, shape.propertyType, path);
  _rejectWireCodecOnCategoricalShape(kind, shape.wireCodec, path);
  switch (shape) {
    case ScalarShape():
      break;
    case EnumShape(:final enumRef):
      // An EnumShape's whole purpose is to carry enum identity; an empty
      // enumRef would satisfy the enum-identity guard while pinning the slot
      // to nothing. Validate it like the other categorical references.
      _validateDartTypeRef(enumRef, '$path.enumRef');
    case StructuredShape(:final structuredRef):
      _validateWireIdRef(
        structuredRef,
        '$path.structuredRef',
        expectedKind: WireIdKind.structured,
      );
    case UnionShape(:final unionRef):
      _validateWireIdRef(
        unionRef,
        '$path.unionRef',
        expectedKind: WireIdKind.union,
      );
    case ListShape(:final itemShape):
      _validateValueShape(itemShape, '$path.itemShape');
  }
}

/// Rejects a `wireCodec` on a categorical (enum/structured) value shape, where
/// the wire shape is fully implied by the category and the codec hint can
/// never carry meaning. `wireCodec` is only meaningful on scalar/union/list
/// shapes.
///
/// Self-contained (no catalog index), so — like [_validatePropertyTypeForKind]
/// — it runs at BOTH decode (`_valueShapeFromJson`, pre-construction) and the
/// encode / `requireNativeCatalog` guard.
void _rejectWireCodecOnCategoricalShape(
  String kind,
  CatalogWireCodec? wireCodec,
  String path,
) {
  if (wireCodec == null) return;
  if (kind == 'enumValue' || kind == 'structured') {
    throw CatalogSchemaException(
      '$path: $kind value shape must not carry a wireCodec '
      '(wireCodec is meaningful only for scalar/union/list shapes)',
    );
  }
}

void _validateFieldMapping(DecompositionFieldMapping mapping, String path) {
  _expectWireIdKind(mapping.fieldRef, WireIdKind.property, '$path.fieldRef');
  _expectWireIdKind(
    mapping.propertyRef,
    WireIdKind.property,
    '$path.propertyRef',
  );
  _validateValueTransform(mapping.transform, '$path.transform');
}

void _validateParameterMapping(
  DecompositionParameterMapping mapping,
  String path,
) {
  _expectWireIdKind(
    mapping.parameterRef,
    WireIdKind.parameter,
    '$path.parameterRef',
  );
  _expectWireIdKind(
    mapping.propertyRef,
    WireIdKind.property,
    '$path.propertyRef',
  );
  _validateValueTransform(mapping.transform, '$path.transform');
}

void _validateValueTransform(
  DecompositionValueTransform transform,
  String path,
) {
  switch (transform) {
    case IdentityTransform():
      return;
    case ConstructVariantTransform(
        :final resultStructuredRef,
        :final invocation,
        :final argumentBindings,
      ):
      _validateWireIdRef(
        resultStructuredRef,
        '$path.resultStructuredRef',
        expectedKind: WireIdKind.structured,
      );
      _validateFactoryInvocation(invocation, '$path.invocation');
      for (var i = 0; i < argumentBindings.length; i++) {
        _validateArgumentBinding(
          argumentBindings[i],
          '$path.argumentBindings[$i]',
        );
      }
    case ProjectListTransform(:final itemTransform):
      _validateValueTransform(itemTransform, '$path.itemTransform');
    case CoerceScalarTransform(:final scalarCoercion):
      if (scalarCoercion.isEmpty) {
        throw CatalogSchemaException(
          '$path.scalarCoercion: coerceScalar requires scalarCoercion',
        );
      }
  }
}

void _validateFactoryInvocation(FactoryInvocation? invocation, String path) {
  if (invocation == null) return;
  _validateWireIdRef(
    invocation.variantRef,
    '$path.variantRef',
    expectedKind: WireIdKind.variant,
  );
  // The explicit-receiver dartTypeRef presence is now guaranteed structurally
  // by ExplicitDartTypeReceiver (non-null field).
}

void _validateArgumentBinding(TransformArgumentBinding binding, String path) {
  _expectWireIdKind(
    binding.parameterRef,
    WireIdKind.parameter,
    '$path.parameterRef',
  );
  switch (binding) {
    case PropertyValueArgumentBinding():
    case LiteralArgumentBinding():
      // A literal binding needs no further checks: a null `literal` encodes
      // the intentional Dart `null` value (the emitters render `null` for
      // it), so absence is valid rather than a missing field.
      return;
    case NestedTransformArgumentBinding(:final nestedTransform):
      _validateValueTransform(nestedTransform, '$path.nestedTransform');
  }
}

void _validateUnion(UnionEntry entry, String path) {
  final unionPath = '$path "${entry.name}"';
  _expectWireIdKind(entry.wireId, WireIdKind.union, '$unionPath.wireId');
  // members[i] is index-aligned with memberSourceTypes[i] and with the
  // discriminant discriminator.values[i]; a length disagreement means the
  // wire shape can no longer correlate a member to its source type or
  // discriminant. Runs on both encode (_validateCanonicalCatalog) and
  // decode-validation (requireNativeCatalog).
  if (entry.members.length != entry.memberSourceTypes.length ||
      entry.members.length != entry.discriminator.values.length) {
    throw CatalogSchemaException(
      '$unionPath: union members (${entry.members.length}), memberSourceTypes '
      '(${entry.memberSourceTypes.length}), and discriminator.values '
      '(${entry.discriminator.values.length}) must all have the same length '
      '(each member is index-aligned with its source type and discriminant)',
    );
  }
  _validateDiscriminator(entry.discriminator, '$unionPath.discriminator');
  for (var i = 0; i < entry.members.length; i++) {
    _validateWireIdRef(
      entry.members[i],
      '$unionPath.members[$i]',
      expectedKind: WireIdKind.structured,
    );
  }
  _validateDeprecation(entry.deprecated, '$unionPath.deprecated');
}

void _validateDiscriminator(DiscriminatorSpec? spec, String path) {
  if (spec == null) return;
  for (var i = 0; i < spec.values.length; i++) {
    _validateWireIdRef(
      spec.values[i],
      '$path.values[$i]',
      expectedKind: WireIdKind.structured,
    );
  }
}

void _validateDesignToken(DesignTokenEntry entry, String path) {
  _expectWireIdKind(entry.wireId, WireIdKind.designToken, '$path.wireId');
  _validateDeprecation(entry.deprecated, '$path.deprecated');
}

void _validateDefaultSource(DefaultValueSource? source, String path) {
  if (source == null) return;
  switch (source) {
    case LiteralDefault():
    case ThemeBindingDefault():
    case FlutterCtorDefault():
      return;
    case TokenRefDefault(:final token):
      _validateWireIdRef(
        token,
        '$path.token',
        expectedKind: WireIdKind.designToken,
      );
  }
}

void _validateDeprecation(DeprecationInfo? deprecation, String path) {
  final replaceWith = deprecation?.catalog?.replaceWith;
  if (replaceWith != null) {
    _validateWireIdRef(replaceWith, '$path.catalog.replaceWith');
  }
}

void _validateCompatRule(CompatRule rule, String path) {
  _validateWireIdRef(rule.affectedRef, '$path.affectedRef');
  final successorRef = rule.successorRef;
  if (successorRef != null) {
    _validateWireIdRef(successorRef, '$path.successorRef');
  }
}

void _validateWireIdRef(
  WireIdRef ref,
  String path, {
  WireIdKind? expectedKind,
}) {
  _validateLibraryNamespace(ref.library, '$path.library');
  if (expectedKind == null) {
    _rejectUnallocated(ref.wireId, '$path.wireId');
    return;
  }
  _expectWireIdKind(ref.wireId, expectedKind, '$path.wireId');
}

void _validateLibraryNamespace(String library, String path) {
  if (!WidgetLibrary.isValidNamespace(library)) {
    throw CatalogSchemaException(
      "$path: '$library' is not a valid library namespace "
      '(expected dotted lowercase segments, e.g. `restage.core`)',
    );
  }
}

void _expectWireIdKind(WireId id, WireIdKind expectedKind, String path) {
  _rejectUnallocated(id, path);
  if (id.kind == expectedKind) return;
  throw CatalogSchemaException(
    '$path: expected ${expectedKind.name} wire ID '
    '(${expectedKind.prefix}*), got ${id.value}',
  );
}

void _rejectUnallocated(WireId id, String path) {
  if (!id.isUnallocated) return;
  throw CatalogSchemaException(
    '$path: unallocated sentinel wire ID ${id.value} is internal-only and '
    'cannot appear in the canonical v$kSupportedSchemaVersion wire shape',
  );
}

/// The catalog content version is monotonic from the baseline; nothing can be
/// introduced before [kBaselineCatalogVersion]. Enforced at BOTH decode
/// ([_sinceVersionFromJson]) and the encode / `requireNativeCatalog`
/// validation ([_validateWidget]).
void _validateSinceVersion(int sinceVersion, String path) {
  if (sinceVersion < kBaselineCatalogVersion) {
    throw CatalogSchemaException(
      '$path: sinceVersion $sinceVersion is below the baseline content '
      'version $kBaselineCatalogVersion',
    );
  }
}

/// A library's declared capability version is a positive monotonic integer
/// when present (an omitted version is `null`). Enforced at BOTH decode
/// ([_libraryInfo]) and the encode / `requireNativeCatalog` validation
/// ([_validateCanonicalCatalog]) so the encode/source boundary is as strict as
/// decode — the builder must never emit a catalog it cannot read back.
void _validateCapabilityVersion(int? capabilityVersion, String path) {
  if (capabilityVersion != null && capabilityVersion < 1) {
    throw CatalogSchemaException(
      '$path: capabilityVersion $capabilityVersion must be a positive integer '
      'when present',
    );
  }
}

Map<String, dynamic> _widgetToJson(WidgetEntry w) => {
      'wireId': w.wireId.value,
      'name': w.name,
      'library': w.library.namespace,
      'category': w.category.name,
      'description': w.description,
      'flutterType': w.flutterType,
      'childrenSlot': w.childrenSlot.name,
      'fires': w.fires.map((e) => e.name).toList(),
      'properties': w.properties.map(_propertyToJson).toList(),
      if (w.decomposes.isNotEmpty)
        'decomposes': w.decomposes.map(_decompositionToJson).toList(),
      // Omitted at the baseline (the common case), following the codec's
      // omit-defaults convention — a baseline catalog stays byte-identical.
      if (w.sinceVersion != kBaselineCatalogVersion)
        'sinceVersion': w.sinceVersion,
      if (w.stability != Stability.volatile) 'stability': w.stability.name,
      if (w.deprecated != null) 'deprecated': _deprecationToJson(w.deprecated!),
    };

// Local builds never emit `PropertyType.unknown` — the sentinel only
// arises on the decode side when reading a payload from a newer
// schema that introduced a new enum member. The encoder treats the
// enum's `.name` opaquely.
Map<String, dynamic> _propertyToJson(PropertyEntry p) {
  assert(
    p.type != PropertyType.unknown,
    'PropertyType.unknown is decoder-only; local builds never construct it.',
  );
  return {
    'wireId': p.wireId.value,
    'name': p.name,
    'type': p.type.name,
    'description': p.description,
    if (p.required) 'required': true,
    if (p.synthetic != null) 'synthetic': p.synthetic,
    if (p.positional) 'positional': true,
    if (p.enumType != null) 'enumType': p.enumType,
    if (p.widgetType != null) 'widgetType': p.widgetType,
    if (p.callbackSignature != null) 'callbackSignature': p.callbackSignature,
    if (p.firesAs != null) 'firesAs': p.firesAs,
    if (p.defaultSource != null)
      'defaultSource': defaultSourceToJson(p.defaultSource!),
    if (p.mutuallyExclusiveWith != null && p.mutuallyExclusiveWith!.isNotEmpty)
      'mutuallyExclusiveWith':
          p.mutuallyExclusiveWith!.map((id) => id.value).toList(),
    if (p.requiresAncestor != null) 'requiresAncestor': p.requiresAncestor,
    if (p.category != null) 'category': p.category!.name,
    if (p.priority != null) 'priority': p.priority!.name,
    if (p.validationRule != null)
      'validationRule': validationExprToJson(p.validationRule!),
    if (p.deprecated != null) 'deprecated': _deprecationToJson(p.deprecated!),
    if (p.structuredRef != null)
      'structuredRef': wireIdRefToJson(p.structuredRef!),
    if (p.valueShape != null) 'valueShape': _valueShapeToJson(p.valueShape!),
  };
}

Map<String, dynamic> _decompositionToJson(DecompositionRecipe r) => {
      'structuredRef': wireIdRefToJson(r.structuredRef),
      'flatProperties': {
        for (final entry in r.flatProperties.entries)
          entry.key.value: entry.value.value,
      },
      if (r.targetArg != null) 'targetArg': r.targetArg,
      if (r.construction != null)
        'construction': _factoryInvocationToJson(r.construction!),
      if (r.fieldMappings.isNotEmpty)
        'fieldMappings': r.fieldMappings.map(_fieldMappingToJson).toList(),
      if (r.parameterMappings.isNotEmpty)
        'parameterMappings':
            r.parameterMappings.map(_parameterMappingToJson).toList(),
      if (r.discriminator != null)
        'discriminator': _discriminatorToJson(r.discriminator!),
    };

Map<String, dynamic> _structuredToJson(StructuredEntry s) => {
      'wireId': s.wireId.value,
      'name': s.name,
      'library': s.library.namespace,
      'description': s.description,
      'sourceType': s.sourceType,
      'fields': s.fields.map(_structuredFieldToJson).toList(),
      'variants': s.variants.map(_factoryVariantToJson).toList(),
      'stability': s.stability.name,
      if (s.deprecated != null) 'deprecated': _deprecationToJson(s.deprecated!),
    };

Map<String, dynamic> _structuredFieldToJson(StructuredField f) {
  // PropertyType.unknown is decoder-only — see the assert below.
  assert(
    f.type != PropertyType.unknown,
    'PropertyType.unknown is decoder-only; local builds never construct it.',
  );
  return {
    'wireId': f.wireId.value,
    'name': f.name,
    'type': f.type.name,
    'description': f.description,
    if (f.required) 'required': true,
    if (f.defaultSource != null)
      'defaultSource': defaultSourceToJson(f.defaultSource!),
    if (f.category != null) 'category': f.category!.name,
    if (f.priority != null) 'priority': f.priority!.name,
    if (f.deprecated != null) 'deprecated': _deprecationToJson(f.deprecated!),
    if (f.structuredRef != null)
      'structuredRef': wireIdRefToJson(f.structuredRef!),
    if (f.unionRef != null) 'unionRef': wireIdRefToJson(f.unionRef!),
    if (f.valueShape != null) 'valueShape': _valueShapeToJson(f.valueShape!),
  };
}

Map<String, dynamic> _factoryVariantToJson(FactoryVariant v) => {
      // Field-key order matches the flat encoder this replaced: wireId,
      // sourceKind, the kind-specific (namedConstructor | staticAccessor),
      // argMappings, parameters, then the shared description + deprecated.
      // A given variant carries only one of namedConstructor/staticAccessor,
      // so the per-subtype spread lands those in the same wire position.
      'wireId': v.wireId.value,
      'sourceKind': factoryVariantSourceKind(v).name,
      ...switch (v) {
        ConstructorVariant(
          :final namedConstructor,
          :final argMappings,
          :final parameters,
        ) =>
          {
            if (namedConstructor != null) 'namedConstructor': namedConstructor,
            ..._argMappingsAndParametersToJson(argMappings, parameters),
          },
        StaticMethodVariant(
          :final staticAccessor,
          :final argMappings,
          :final parameters,
        ) =>
          {
            'staticAccessor': staticAccessor,
            ..._argMappingsAndParametersToJson(argMappings, parameters),
          },
        StaticGetterVariant(:final staticAccessor) => {
            'staticAccessor': staticAccessor,
          },
        ConstValueVariant(:final staticAccessor) => {
            'staticAccessor': staticAccessor,
          },
      },
      if (v.description != null) 'description': v.description,
      if (v.deprecated != null) 'deprecated': _deprecationToJson(v.deprecated!),
    };

/// The callable parameters of [variant] — empty for the accessor kinds
/// (static getter / const field), which are zero-arg by construction. Lets
/// the cross-reference resolver iterate every variant's parameters uniformly
/// without re-introducing a parameters field on the accessor subtypes.
List<FactoryParameter> _variantParameters(FactoryVariant variant) =>
    switch (variant) {
      ConstructorVariant(:final parameters) ||
      StaticMethodVariant(:final parameters) =>
        parameters,
      StaticGetterVariant() || ConstValueVariant() => const [],
    };

/// The shared `argMappings` (present-if-nonempty) + `parameters`
/// (present-if-nonempty) wire fields for the two callable variant kinds, in
/// their canonical key order.
Map<String, dynamic> _argMappingsAndParametersToJson(
  Map<String, ArgMapping> argMappings,
  List<FactoryParameter> parameters,
) =>
    {
      if (argMappings.isNotEmpty)
        'argMappings': {
          for (final entry in argMappings.entries)
            entry.key: entry.value.targetFields.map((id) => id.value).toList(),
        },
      if (parameters.isNotEmpty)
        'parameters': parameters.map(_factoryParameterToJson).toList(),
    };

Map<String, dynamic> _dartTypeRefToJson(DartTypeRef ref) => {
      'libraryUri': ref.libraryUri,
      'symbolName': ref.symbolName,
    };

Map<String, dynamic> _valueShapeToJson(CatalogValueShape shape) {
  // Field-key order matches the legacy flat encoder: kind, propertyType, the
  // category-specific reference, then the (cross-kind) wireCodec last.
  final wireCodec = shape.wireCodec;
  return switch (shape) {
    ScalarShape(:final dartTypeRef) => {
        'kind': 'scalar',
        'propertyType': shape.propertyType.name,
        if (dartTypeRef != null) 'dartTypeRef': _dartTypeRefToJson(dartTypeRef),
        if (wireCodec != null) 'wireCodec': wireCodec.name,
      },
    EnumShape(:final enumRef) => {
        'kind': 'enumValue',
        'propertyType': shape.propertyType.name,
        'enumRef': _dartTypeRefToJson(enumRef),
        if (wireCodec != null) 'wireCodec': wireCodec.name,
      },
    StructuredShape(:final structuredRef) => {
        'kind': 'structured',
        'propertyType': shape.propertyType.name,
        'structuredRef': wireIdRefToJson(structuredRef),
        if (wireCodec != null) 'wireCodec': wireCodec.name,
      },
    UnionShape(:final unionRef) => {
        'kind': 'union',
        'propertyType': shape.propertyType.name,
        'unionRef': wireIdRefToJson(unionRef),
        if (wireCodec != null) 'wireCodec': wireCodec.name,
      },
    ListShape(:final itemShape) => {
        'kind': 'list',
        'propertyType': shape.propertyType.name,
        'itemShape': _valueShapeToJson(itemShape),
        if (wireCodec != null) 'wireCodec': wireCodec.name,
      },
  };
}

Map<String, dynamic> _factoryParameterToJson(FactoryParameter parameter) => {
      'wireId': parameter.wireId.value,
      if (parameter.name != null) 'name': parameter.name,
      if (parameter.position != null) 'position': parameter.position,
      'kind': parameter.kind.name,
      'required': parameter.required,
      'nullable': parameter.nullable,
      'defaultPolicy': parameter.defaultPolicy.name,
      if (parameter.defaultValue != null)
        'defaultValue': _parameterDefaultValueToJson(parameter.defaultValue!),
      'valueShape': _valueShapeToJson(parameter.valueShape),
    };

Map<String, dynamic> _parameterDefaultValueToJson(
  FactoryParameterDefaultValue value,
) =>
    switch (value) {
      LiteralParameterDefault(:final value) => {
          'kind': 'literal',
          'value': value,
        },
      StaticMemberParameterDefault(:final staticType, :final memberName) => {
          'kind': 'staticMember',
          'staticType': _dartTypeRefToJson(staticType),
          'memberName': memberName,
        },
    };

Map<String, dynamic> _factoryInvocationToJson(FactoryInvocation invocation) => {
      'variantRef': wireIdRefToJson(invocation.variantRef),
      'receiver': _factoryReceiverToJson(invocation.receiver),
      if (invocation.memberName != null) 'memberName': invocation.memberName,
    };

Map<String, dynamic> _factoryReceiverToJson(FactoryReceiver receiver) =>
    switch (receiver) {
      ResultStructuredTypeReceiver() => {'kind': 'resultStructuredType'},
      OwningWidgetTypeReceiver() => {'kind': 'owningWidgetType'},
      ExplicitDartTypeReceiver(:final dartTypeRef) => {
          'kind': 'explicitDartType',
          'dartTypeRef': _dartTypeRefToJson(dartTypeRef),
        },
    };

Map<String, dynamic> _fieldMappingToJson(DecompositionFieldMapping mapping) => {
      'fieldRef': mapping.fieldRef.value,
      'propertyRef': mapping.propertyRef.value,
      'transform': _valueTransformToJson(mapping.transform),
    };

Map<String, dynamic> _parameterMappingToJson(
  DecompositionParameterMapping mapping,
) =>
    {
      'parameterRef': mapping.parameterRef.value,
      'propertyRef': mapping.propertyRef.value,
      'transform': _valueTransformToJson(mapping.transform),
    };

Map<String, dynamic> _valueTransformToJson(
  DecompositionValueTransform transform,
) =>
    switch (transform) {
      IdentityTransform() => {'kind': 'identity'},
      ConstructVariantTransform(
        :final resultStructuredRef,
        :final invocation,
        :final argumentBindings,
      ) =>
        {
          'kind': 'constructVariant',
          'resultStructuredRef': wireIdRefToJson(resultStructuredRef),
          'invocation': _factoryInvocationToJson(invocation),
          if (argumentBindings.isNotEmpty)
            'argumentBindings':
                argumentBindings.map(_argumentBindingToJson).toList(),
        },
      ProjectListTransform(:final itemTransform) => {
          'kind': 'projectList',
          'itemTransform': _valueTransformToJson(itemTransform),
        },
      CoerceScalarTransform(:final scalarCoercion) => {
          'kind': 'coerceScalar',
          'scalarCoercion': scalarCoercion,
        },
    };

Map<String, dynamic> _argumentBindingToJson(TransformArgumentBinding binding) {
  // Field-key order matches the legacy flat encoder: parameterRef, source,
  // the source-specific payload (literal/nestedTransform), nullPolicy,
  // missingPolicy. A null literal omits the `literal` key (intentional Dart
  // null is encoded by the source tag, not the key).
  return switch (binding) {
    PropertyValueArgumentBinding() => {
        'parameterRef': binding.parameterRef.value,
        'source': 'propertyValue',
        'nullPolicy': binding.nullPolicy.name,
        'missingPolicy': binding.missingPolicy.name,
      },
    LiteralArgumentBinding(:final literal) => {
        'parameterRef': binding.parameterRef.value,
        'source': 'literal',
        if (literal != null) 'literal': literal,
        'nullPolicy': binding.nullPolicy.name,
        'missingPolicy': binding.missingPolicy.name,
      },
    NestedTransformArgumentBinding(:final nestedTransform) => {
        'parameterRef': binding.parameterRef.value,
        'source': 'nestedTransform',
        'nestedTransform': _valueTransformToJson(nestedTransform),
        'nullPolicy': binding.nullPolicy.name,
        'missingPolicy': binding.missingPolicy.name,
      },
  };
}

Map<String, dynamic> _unionToJson(UnionEntry u) => {
      'wireId': u.wireId.value,
      'name': u.name,
      'library': u.library.namespace,
      'description': u.description,
      'sourceType': u.sourceType,
      'memberSourceTypes': u.memberSourceTypes,
      'discriminator': _discriminatorToJson(u.discriminator),
      'members': u.members.map(wireIdRefToJson).toList(),
      'stability': u.stability.name,
      if (u.deprecated != null) 'deprecated': _deprecationToJson(u.deprecated!),
    };

Map<String, dynamic> _discriminatorToJson(DiscriminatorSpec d) => {
      'field': d.field,
      'values': d.values.map(wireIdRefToJson).toList(),
    };

Map<String, dynamic> _designTokenToJson(DesignTokenEntry t) => {
      'wireId': t.wireId.value,
      'name': t.name,
      'library': t.library.namespace,
      'type': t.type.name,
      if (t.description != null) 'description': t.description,
      if (t.resolver != null) 'resolver': themeBindingToJson(t.resolver!),
      if (t.literalFallback != null) 'literalFallback': t.literalFallback,
      'stability': t.stability.name,
      if (t.deprecated != null) 'deprecated': _deprecationToJson(t.deprecated!),
    };

Map<String, dynamic> _deprecationToJson(DeprecationInfo d) => {
      if (d.source != null) 'source': _sourceDeprecationToJson(d.source!),
      if (d.catalog != null) 'catalog': _catalogDeprecationToJson(d.catalog!),
    };

Map<String, dynamic> _sourceDeprecationToJson(SourceDeprecationInfo d) => {
      'message': d.message,
      if (d.since != null) 'since': d.since,
    };

Map<String, dynamic> _catalogDeprecationToJson(CatalogDeprecationInfo d) => {
      'reason': d.reason,
      'at': d.at,
      if (d.transitionId != null) 'transitionId': d.transitionId,
      if (d.replaceWith != null) 'replaceWith': wireIdRefToJson(d.replaceWith!),
    };

Map<String, dynamic> _compatRuleToJson(CompatRule r) => {
      'fromVersion': r.fromVersion,
      'toVersion': r.toVersion,
      'kind': r.kind.name,
      'affectedRef': wireIdRefToJson(r.affectedRef),
      if (r.successorRef != null)
        'successorRef': wireIdRefToJson(r.successorRef!),
      if (r.transitionId != null) 'transitionId': r.transitionId,
      if (r.note != null) 'note': r.note,
    };

/// Parse a catalog JSON string emitted by [encodeCatalog].
///
/// Throws a [CatalogSchemaException] when the input is malformed, the
/// schema version is unsupported, or required fields are missing.
Catalog decodeCatalog(String source) {
  return _decodeCatalogWithVersions(
    source,
    allowedVersions: {kSupportedSchemaVersion},
  );
}

/// Validate that [catalog] is native-v4-consumable, returning it on success.
Catalog requireNativeCatalog(Catalog catalog) {
  if (catalog.schemaVersion != kSupportedSchemaVersion) {
    throw CatalogSchemaException(
      'Native catalogs must use schemaVersion $kSupportedSchemaVersion; '
      'got ${catalog.schemaVersion}.',
    );
  }
  _validateCanonicalCatalog(catalog);

  final structuredByRef = <(String, WireId), StructuredEntry>{};
  final variantsByRef = <(String, WireId), (WireIdRef, FactoryVariant)>{};
  final parametersByVariant = <(String, WireId), Set<WireId>>{};
  final parameterOwnerByRef = <(String, WireId), WireIdRef>{};
  final unionByRef = <(String, WireId), UnionEntry>{};
  for (final structured in catalog.structuredTypes) {
    final structuredRef = (
      structured.library.namespace,
      structured.wireId,
    );
    structuredByRef[structuredRef] = structured;
    for (final variant in structured.variants) {
      final variantRef = (
        structured.library.namespace,
        variant.wireId,
      );
      variantsByRef[variantRef] = (
        WireIdRef(
          library: structured.library.namespace,
          wireId: structured.wireId,
        ),
        variant,
      );
      final parameterIds = <WireId>{};
      final variantWireRef = WireIdRef(
        library: structured.library.namespace,
        wireId: variant.wireId,
      );
      for (final parameter in _variantParameters(variant)) {
        final parameterRef = (structured.library.namespace, parameter.wireId);
        final existingOwner = parameterOwnerByRef[parameterRef];
        if (existingOwner != null) {
          throw CatalogSchemaException(
            'duplicate parameter wire ID ${parameter.wireId} in '
            '${structured.library.namespace}: owned by $existingOwner and '
            '$variantWireRef',
          );
        }
        parameterOwnerByRef[parameterRef] = variantWireRef;
        parameterIds.add(parameter.wireId);
      }
      parametersByVariant[variantRef] = parameterIds;
    }
  }
  for (final union in catalog.unions) {
    unionByRef[(union.library.namespace, union.wireId)] = union;
  }

  for (final widget in catalog.widgets) {
    for (var i = 0; i < widget.properties.length; i++) {
      final property = widget.properties[i];
      final path = 'widget "${widget.name}".properties[$i]';
      _requireOptionalStructuredRef(
        property.structuredRef,
        structuredByRef,
        '$path.structuredRef',
      );
      _requireValueShapeRefs(
        property.valueShape,
        structuredByRef,
        unionByRef,
        '$path.valueShape',
      );
    }
  }

  for (final structured in catalog.structuredTypes) {
    for (var i = 0; i < structured.fields.length; i++) {
      final field = structured.fields[i];
      final path = 'structured "${structured.name}".fields[$i]';
      _requireOptionalStructuredRef(
        field.structuredRef,
        structuredByRef,
        '$path.structuredRef',
      );
      _requireOptionalUnionRef(field.unionRef, unionByRef, '$path.unionRef');
      _requireValueShapeRefs(
        field.valueShape,
        structuredByRef,
        unionByRef,
        '$path.valueShape',
      );
    }
    for (var i = 0; i < structured.variants.length; i++) {
      final variant = structured.variants[i];
      final parameters = _variantParameters(variant);
      for (var j = 0; j < parameters.length; j++) {
        final parameterPath =
            'structured "${structured.name}".variants[$i].parameters[$j]';
        _requireValueShapeRefs(
          parameters[j].valueShape,
          structuredByRef,
          unionByRef,
          '$parameterPath.valueShape',
        );
      }
    }
  }

  for (final union in catalog.unions) {
    for (var i = 0; i < union.members.length; i++) {
      _requireStructuredRef(
        union.members[i],
        structuredByRef,
        'union "${union.name}".members[$i]',
      );
    }
    for (var i = 0; i < union.discriminator.values.length; i++) {
      _requireStructuredRef(
        union.discriminator.values[i],
        structuredByRef,
        'union "${union.name}".discriminator.values[$i]',
      );
    }
  }

  for (final widget in catalog.widgets) {
    final widgetProperties = {for (final p in widget.properties) p.wireId};
    for (var i = 0; i < widget.decomposes.length; i++) {
      final recipe = widget.decomposes[i];
      final path = 'widget "${widget.name}".decomposes[$i]';
      final structured = structuredByRef[(
        recipe.structuredRef.library,
        recipe.structuredRef.wireId,
      )];
      if (structured == null) {
        throw CatalogSchemaException(
          '$path.structuredRef: missing structured entry '
          '${recipe.structuredRef}',
        );
      }
      if (recipe.targetArg == null || recipe.construction == null) {
        throw CatalogSchemaException(
          '$path: native recipe requires targetArg and construction',
        );
      }
      _requireVariant(
        recipe.construction!,
        variantsByRef,
        expectedResultStructuredRef: recipe.structuredRef,
        path: '$path.construction',
      );
      final constructionParameterIds = parametersByVariant[(
            recipe.construction!.variantRef.library,
            recipe.construction!.variantRef.wireId,
          )] ??
          const <WireId>{};
      final fields = {for (final field in structured.fields) field.wireId};
      for (var j = 0; j < recipe.fieldMappings.length; j++) {
        final mapping = recipe.fieldMappings[j];
        final mappingPath = '$path.fieldMappings[$j]';
        if (!fields.contains(mapping.fieldRef)) {
          throw CatalogSchemaException(
            '$mappingPath.fieldRef: missing field ${mapping.fieldRef}',
          );
        }
        if (!widgetProperties.contains(mapping.propertyRef)) {
          throw CatalogSchemaException(
            '$mappingPath.propertyRef: missing property ${mapping.propertyRef}',
          );
        }
        _requireTransformRefs(
          mapping.transform,
          variantsByRef,
          parametersByVariant,
          '$mappingPath.transform',
        );
      }
      for (var j = 0; j < recipe.parameterMappings.length; j++) {
        final mapping = recipe.parameterMappings[j];
        final mappingPath = '$path.parameterMappings[$j]';
        if (!constructionParameterIds.contains(mapping.parameterRef)) {
          throw CatalogSchemaException(
            '$mappingPath.parameterRef: missing construction parameter '
            '${mapping.parameterRef}',
          );
        }
        if (!widgetProperties.contains(mapping.propertyRef)) {
          throw CatalogSchemaException(
            '$mappingPath.propertyRef: missing property ${mapping.propertyRef}',
          );
        }
        _requireTransformRefs(
          mapping.transform,
          variantsByRef,
          parametersByVariant,
          '$mappingPath.transform',
        );
      }
    }
  }
  return catalog;
}

void _requireOptionalStructuredRef(
  WireIdRef? ref,
  Map<(String, WireId), StructuredEntry> structuredByRef,
  String path,
) {
  if (ref == null) return;
  _requireStructuredRef(ref, structuredByRef, path);
}

void _requireOptionalUnionRef(
  WireIdRef? ref,
  Map<(String, WireId), UnionEntry> unionByRef,
  String path,
) {
  if (ref == null) return;
  _requireUnionRef(ref, unionByRef, path);
}

void _requireStructuredRef(
  WireIdRef ref,
  Map<(String, WireId), StructuredEntry> structuredByRef,
  String path,
) {
  if (structuredByRef.containsKey((ref.library, ref.wireId))) return;
  throw CatalogSchemaException('$path: missing structured entry $ref');
}

void _requireUnionRef(
  WireIdRef ref,
  Map<(String, WireId), UnionEntry> unionByRef,
  String path,
) {
  if (unionByRef.containsKey((ref.library, ref.wireId))) return;
  throw CatalogSchemaException('$path: missing union entry $ref');
}

void _requireValueShapeRefs(
  CatalogValueShape? shape,
  Map<(String, WireId), StructuredEntry> structuredByRef,
  Map<(String, WireId), UnionEntry> unionByRef,
  String path,
) {
  if (shape == null) return;
  switch (shape) {
    case ScalarShape():
    case EnumShape():
      return;
    case StructuredShape(:final structuredRef):
      _requireStructuredRef(structuredRef, structuredByRef, path);
    case UnionShape(:final unionRef):
      _requireUnionRef(unionRef, unionByRef, path);
    case ListShape(:final itemShape):
      _requireValueShapeRefs(
        itemShape,
        structuredByRef,
        unionByRef,
        '$path.itemShape',
      );
  }
}

Catalog _decodeCatalogWithVersions(
  String source, {
  required Set<int> allowedVersions,
}) {
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
  if (version is! int || !allowedVersions.contains(version)) {
    throw CatalogSchemaException(
      'Unsupported catalog schemaVersion $version '
      '(expected ${allowedVersions.join(' or ')}).',
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
  final structuredRaw = _optionalListField(raw, 'structuredTypes');
  final unionsRaw = _optionalListField(raw, 'unions');
  final tokensRaw = _optionalListField(raw, 'designTokens');
  final compatRulesRaw = _optionalListField(raw, 'compatRules');
  // Untrusted wire->catalog path: wrap every decoded collection
  // `unmodifiable` so a decoded Catalog is immutable through its public
  // getters. The Catalog/entry const constructors are unchanged (the
  // local-build path keeps mutable collections by reference); only this
  // decode path is hardened. `Map.unmodifiable` / `List.unmodifiable`
  // preserve insertion order, so the re-encode wire bytes are unchanged.
  return Catalog(
    schemaVersion: version,
    generatedAt: generatedAt,
    flutterVersion: raw['flutterVersion'] as String?,
    libraries: Map.unmodifiable({
      for (final entry in librariesRaw.entries)
        WidgetLibrary.fromNamespace(_jsonKey(entry.key, 'libraries')):
            _libraryInfo(
          _jsonObject(
            entry.value,
            'libraries["${_jsonKey(entry.key, 'libraries')}"]',
          ),
          'libraries["${entry.key}"]',
        ),
    }),
    widgets: List.unmodifiable([
      for (var i = 0; i < widgetsRaw.length; i++)
        _widgetFromJson(
          _jsonObject(widgetsRaw[i], 'widgets[$i]'),
          'widgets[$i]',
        ),
    ]),
    structuredTypes: structuredRaw == null
        ? const []
        : List.unmodifiable([
            for (var i = 0; i < structuredRaw.length; i++)
              _structuredFromJson(
                _jsonObject(structuredRaw[i], 'structuredTypes[$i]'),
                'structuredTypes[$i]',
              ),
          ]),
    unions: unionsRaw == null
        ? const []
        : List.unmodifiable([
            for (var i = 0; i < unionsRaw.length; i++)
              _unionFromJson(
                _jsonObject(unionsRaw[i], 'unions[$i]'),
                'unions[$i]',
              ),
          ]),
    designTokens: tokensRaw == null
        ? const []
        : List.unmodifiable([
            for (var i = 0; i < tokensRaw.length; i++)
              _designTokenFromJson(
                _jsonObject(tokensRaw[i], 'designTokens[$i]'),
                'designTokens[$i]',
              ),
          ]),
    compatRules: compatRulesRaw == null
        ? null
        : List.unmodifiable([
            for (var i = 0; i < compatRulesRaw.length; i++)
              _compatRuleFromJson(
                _jsonObject(compatRulesRaw[i], 'compatRules[$i]'),
                'compatRules[$i]',
              ),
          ]),
  );
}

List<Object?>? _optionalListField(Map<String, dynamic> raw, String key) {
  final value = raw[key];
  if (value == null) return null;
  if (value is! List) {
    throw CatalogSchemaException(
      '$key: expected a JSON array, got ${value.runtimeType}',
    );
  }
  return List<Object?>.from(value);
}

String _jsonKey(Object? key, String path) {
  if (key is String) return key;
  throw CatalogSchemaException(
    '$path: expected object keys to be strings, got ${key.runtimeType}',
  );
}

Map<String, dynamic> _jsonObject(Object? value, String path) {
  if (value is! Map) {
    throw CatalogSchemaException(
      '$path: expected a JSON object, got ${value.runtimeType}',
    );
  }
  return {
    for (final entry in value.entries) _jsonKey(entry.key, path): entry.value,
  };
}

/// Reads the required string field [field] from [j], throwing a
/// [CatalogSchemaException] (not a raw `TypeError`) when it is absent or
/// not a string. Use for discriminator reads so malformed input surfaces
/// through the codec's documented exception contract rather than a cast
/// error that escapes the consumer's `on CatalogSchemaException` handler.
String _requiredString(Map<String, dynamic> j, String field, String path) {
  final value = j[field];
  if (value is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: $field',
    );
  }
  return value;
}

void _requireAllowedKeys(
  Map<String, dynamic> value,
  String path,
  Set<String> allowed,
) {
  for (final key in value.keys) {
    if (!allowed.contains(key)) {
      throw CatalogSchemaException('$path: unexpected field $key');
    }
  }
}

(WireIdRef, FactoryVariant) _requireVariant(
  FactoryInvocation invocation,
  Map<(String, WireId), (WireIdRef, FactoryVariant)> variantsByRef, {
  required WireIdRef expectedResultStructuredRef,
  required String path,
}) {
  final entry = variantsByRef[(
    invocation.variantRef.library,
    invocation.variantRef.wireId,
  )];
  if (entry == null) {
    throw CatalogSchemaException(
      '$path.variantRef: missing variant ${invocation.variantRef}',
    );
  }
  if (entry.$1 != expectedResultStructuredRef) {
    throw CatalogSchemaException(
      '$path.variantRef: variant ${invocation.variantRef} belongs to '
      '${entry.$1}, not $expectedResultStructuredRef',
    );
  }
  return entry;
}

void _requireTransformRefs(
  DecompositionValueTransform transform,
  Map<(String, WireId), (WireIdRef, FactoryVariant)> variantsByRef,
  Map<(String, WireId), Set<WireId>> parametersByVariant,
  String path,
) {
  switch (transform) {
    case IdentityTransform():
    case CoerceScalarTransform():
      return;
    case ProjectListTransform(:final itemTransform):
      _requireTransformRefs(
        itemTransform,
        variantsByRef,
        parametersByVariant,
        '$path.itemTransform',
      );
    case ConstructVariantTransform(
        :final resultStructuredRef,
        :final invocation,
        :final argumentBindings,
      ):
      _requireVariant(
        invocation,
        variantsByRef,
        expectedResultStructuredRef: resultStructuredRef,
        path: '$path.invocation',
      );
      final variantKey = (
        invocation.variantRef.library,
        invocation.variantRef.wireId,
      );
      final parameters = parametersByVariant[variantKey] ?? const <WireId>{};
      for (var i = 0; i < argumentBindings.length; i++) {
        final binding = argumentBindings[i];
        if (!parameters.contains(binding.parameterRef)) {
          throw CatalogSchemaException(
            '$path.argumentBindings[$i].parameterRef: parameter '
            '${binding.parameterRef} is not owned by '
            '${invocation.variantRef}',
          );
        }
        if (binding is NestedTransformArgumentBinding) {
          _requireTransformRefs(
            binding.nestedTransform,
            variantsByRef,
            parametersByVariant,
            '$path.argumentBindings[$i].nestedTransform',
          );
        }
      }
  }
}

LibraryInfo _libraryInfo(Map<String, dynamic> j, String path) {
  if (j['version'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: version',
    );
  }
  // Per-kind counts are derived from the catalog's entry lists, not stored.
  // Decode reads `version` and the optional `capabilityVersion`; any legacy
  // count keys are ignored.
  //
  // `capabilityVersion` is optional: an absent key means the library declared
  // none (null). When the key is present it must be a positive monotonic
  // integer — an explicit `null` or a non-int is malformed (the encoder omits
  // the key when null, so a present key always carries a real value). This
  // distinguishes absent-as-null from present-null, mirroring the
  // `sinceVersion` decode discipline.
  final int? capabilityVersion;
  if (!j.containsKey('capabilityVersion')) {
    capabilityVersion = null;
  } else {
    final raw = j['capabilityVersion'];
    if (raw is! int || raw < 1) {
      throw CatalogSchemaException(
        '$path: capabilityVersion must be a positive integer when present, '
        'got ${raw.runtimeType}: $raw',
      );
    }
    capabilityVersion = raw;
  }
  return LibraryInfo(
    version: j['version'] as String,
    capabilityVersion: capabilityVersion,
  );
}

WidgetEntry _widgetFromJson(Map<String, dynamic> j, String path) {
  if (j['name'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: name',
    );
  }
  // Once the name is in hand, prefer a more readable path for nested errors.
  final name = j['name'] as String;
  final widgetPath = '$path "$name"';
  final wireId = wireIdFromJson(
    j,
    'wireId',
    widgetPath,
    WireIdKind.widget,
  );
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
  return WidgetEntry(
    wireId: wireId,
    name: name,
    library: WidgetLibrary.fromNamespace(j['library'] as String),
    category: _enumFromName(
      WidgetCategory.values,
      j['category'] as String,
      'category',
      widgetPath,
    ),
    description: j['description'] as String,
    flutterType: j['flutterType'] as String,
    childrenSlot: _enumFromName(
      ChildrenSlot.values,
      j['childrenSlot'] as String,
      'childrenSlot',
      widgetPath,
    ),
    fires: List.unmodifiable([
      for (final e in j['fires'] as List)
        _enumFromName(
          WidgetEventName.values,
          e as String,
          'fires',
          widgetPath,
        ),
    ]),
    properties: List.unmodifiable([
      for (var i = 0; i < propertiesRaw.length; i++)
        _propertyFromJson(
          _jsonObject(propertiesRaw[i], '$widgetPath.properties[$i]'),
          '$widgetPath.properties[$i]',
        ),
    ]),
    decomposes: decomposesRaw == null
        ? const []
        : List.unmodifiable([
            for (var i = 0; i < (decomposesRaw as List).length; i++)
              _decompositionFromJson(
                _jsonObject(decomposesRaw[i], '$widgetPath.decomposes[$i]'),
                '$widgetPath.decomposes[$i]',
              ),
          ]),
    sinceVersion:
        _sinceVersionFromJson(j, 'sinceVersion', '$widgetPath.sinceVersion'),
    stability: _stabilityFromJson(j['stability'], '$widgetPath.stability'),
    deprecated: _deprecationFromJson(
      j['deprecated'],
      '$widgetPath.deprecated',
    ),
  );
}

PropertyEntry _propertyFromJson(Map<String, dynamic> j, String path) {
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
  final wireId = wireIdFromJson(j, 'wireId', path, WireIdKind.property);
  final mutexRaw = j['mutuallyExclusiveWith'];
  List<WireId>? mutuallyExclusiveWith;
  if (mutexRaw != null) {
    if (mutexRaw is! List) {
      throw CatalogSchemaException(
        '$path: malformed optional list field: mutuallyExclusiveWith',
      );
    }
    mutuallyExclusiveWith = List.unmodifiable([
      for (var i = 0; i < mutexRaw.length; i++)
        wireIdFromString(
          mutexRaw[i],
          '$path.mutuallyExclusiveWith[$i]',
          WireIdKind.property,
        ),
    ]);
  }
  final validationRuleRaw = j['validationRule'];
  return PropertyEntry(
    wireId: wireId,
    name: j['name'] as String,
    // Forward-compat: unknown PropertyType names fall back to the
    // `unknown` sentinel rather than throwing. New enum members can
    // land additively in newer catalog schemas without breaking
    // older decoder builds.
    type: _tryEnumFromName(PropertyType.values, j['type'] as String) ??
        PropertyType.unknown,
    description: j['description'] as String,
    required: j['required'] as bool? ?? false,
    synthetic: j['synthetic'] as String?,
    positional: j['positional'] as bool? ?? false,
    enumType: j['enumType'] as String?,
    widgetType: j['widgetType'] as String?,
    callbackSignature: j['callbackSignature'] as String?,
    firesAs: j['firesAs'] as String?,
    defaultSource:
        defaultSourceFromJson(j['defaultSource'], '$path.defaultSource'),
    mutuallyExclusiveWith: mutuallyExclusiveWith,
    requiresAncestor: j['requiresAncestor'] as String?,
    category: j['category'] == null
        ? null
        : _enumFromName(
            PropertyCategory.values,
            j['category'] as String,
            'category',
            path,
          ),
    priority: j['priority'] == null
        ? null
        : _enumFromName(
            PropertyPriority.values,
            j['priority'] as String,
            'priority',
            path,
          ),
    validationRule: validationRuleRaw == null
        ? null
        : validationExprFromJson(
            _jsonObject(validationRuleRaw, '$path.validationRule'),
            '$path.validationRule',
          ),
    deprecated: _deprecationFromJson(j['deprecated'], '$path.deprecated'),
    structuredRef: j['structuredRef'] == null
        ? null
        : wireIdRefFromJson(
            _jsonObject(j['structuredRef'], '$path.structuredRef'),
            '$path.structuredRef',
            expectedKind: WireIdKind.structured,
          ),
    valueShape: _valueShapeFromJson(j['valueShape'], '$path.valueShape'),
  );
}

DecompositionRecipe _decompositionFromJson(
  Map<String, dynamic> j,
  String path,
) {
  _requireAllowedKeys(j, path, const {
    'structuredRef',
    'flatProperties',
    'targetArg',
    'construction',
    'fieldMappings',
    'parameterMappings',
    'discriminator',
  });
  final structuredRefRaw = j['structuredRef'];
  if (structuredRefRaw is! Map) {
    throw CatalogSchemaException(
      '$path: missing required map field: structuredRef',
    );
  }
  final flatRaw = j['flatProperties'];
  if (flatRaw is! Map) {
    throw CatalogSchemaException(
      '$path: missing required map field: flatProperties',
    );
  }
  final flat = <WireId, WireId>{};
  for (final entry in flatRaw.entries) {
    if (entry.key is! String || entry.value is! String) {
      throw CatalogSchemaException(
        '$path.flatProperties: must map wire-ID string to wire-ID string; '
        'got ${entry.key.runtimeType} -> ${entry.value.runtimeType}',
      );
    }
    flat[wireIdFromString(
      entry.key,
      '$path.flatProperties (key)',
      WireIdKind.property,
    )] = wireIdFromString(
      entry.value,
      '$path.flatProperties[${entry.key}]',
      WireIdKind.property,
    );
  }
  final discriminatorRaw = j['discriminator'];
  final fieldMappingsRaw = j['fieldMappings'];
  var fieldMappings = const <DecompositionFieldMapping>[];
  if (fieldMappingsRaw != null) {
    if (fieldMappingsRaw is! List) {
      throw CatalogSchemaException(
        '$path: malformed optional list field: fieldMappings',
      );
    }
    fieldMappings = List.unmodifiable([
      for (var i = 0; i < fieldMappingsRaw.length; i++)
        _fieldMappingFromJson(
          _jsonObject(fieldMappingsRaw[i], '$path.fieldMappings[$i]'),
          '$path.fieldMappings[$i]',
        ),
    ]);
  }
  final parameterMappingsRaw = j['parameterMappings'];
  var parameterMappings = const <DecompositionParameterMapping>[];
  if (parameterMappingsRaw != null) {
    if (parameterMappingsRaw is! List) {
      throw CatalogSchemaException(
        '$path: malformed optional list field: parameterMappings',
      );
    }
    parameterMappings = List.unmodifiable([
      for (var i = 0; i < parameterMappingsRaw.length; i++)
        _parameterMappingFromJson(
          _jsonObject(
            parameterMappingsRaw[i],
            '$path.parameterMappings[$i]',
          ),
          '$path.parameterMappings[$i]',
        ),
    ]);
  }
  return DecompositionRecipe(
    structuredRef: wireIdRefFromJson(
      structuredRefRaw.cast<String, dynamic>(),
      '$path.structuredRef',
      expectedKind: WireIdKind.structured,
    ),
    flatProperties: Map.unmodifiable(flat),
    targetArg: j['targetArg'] as String?,
    construction: _factoryInvocationFromJson(
      j['construction'],
      '$path.construction',
    ),
    fieldMappings: fieldMappings,
    parameterMappings: parameterMappings,
    discriminator: discriminatorRaw == null
        ? null
        : _discriminatorFromJson(
            _jsonObject(discriminatorRaw, '$path.discriminator'),
            '$path.discriminator',
          ),
  );
}

StructuredEntry _structuredFromJson(Map<String, dynamic> j, String path) {
  final wireId = wireIdFromJson(j, 'wireId', path, WireIdKind.structured);
  if (j['name'] is! String) {
    throw CatalogSchemaException('$path: missing required string field: name');
  }
  final name = j['name'] as String;
  final structuredPath = '$path "$name"';
  if (j['library'] is! String) {
    throw CatalogSchemaException(
      '$structuredPath: missing required string field: library',
    );
  }
  if (j['description'] is! String) {
    throw CatalogSchemaException(
      '$structuredPath: missing required string field: description',
    );
  }
  if (j['sourceType'] is! String) {
    throw CatalogSchemaException(
      '$structuredPath: missing required string field: sourceType',
    );
  }
  if (j['fields'] is! List) {
    throw CatalogSchemaException(
      '$structuredPath: missing required list field: fields',
    );
  }
  if (j['variants'] is! List) {
    throw CatalogSchemaException(
      '$structuredPath: missing required list field: variants',
    );
  }
  final fieldsRaw = j['fields'] as List;
  final variantsRaw = j['variants'] as List;
  return StructuredEntry(
    wireId: wireId,
    name: name,
    library: WidgetLibrary.fromNamespace(j['library'] as String),
    description: j['description'] as String,
    sourceType: j['sourceType'] as String,
    fields: List.unmodifiable([
      for (var i = 0; i < fieldsRaw.length; i++)
        _structuredFieldFromJson(
          _jsonObject(fieldsRaw[i], '$structuredPath.fields[$i]'),
          '$structuredPath.fields[$i]',
        ),
    ]),
    variants: List.unmodifiable([
      for (var i = 0; i < variantsRaw.length; i++)
        _factoryVariantFromJson(
          _jsonObject(variantsRaw[i], '$structuredPath.variants[$i]'),
          '$structuredPath.variants[$i]',
        ),
    ]),
    stability: _stabilityFromJson(j['stability'], '$structuredPath.stability'),
    deprecated: _deprecationFromJson(
      j['deprecated'],
      '$structuredPath.deprecated',
    ),
  );
}

StructuredField _structuredFieldFromJson(Map<String, dynamic> j, String path) {
  final wireId = wireIdFromJson(j, 'wireId', path, WireIdKind.property);
  if (j['name'] is! String) {
    throw CatalogSchemaException('$path: missing required string field: name');
  }
  if (j['type'] is! String) {
    throw CatalogSchemaException('$path: missing required string field: type');
  }
  if (j['description'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: description',
    );
  }
  final field = StructuredField(
    wireId: wireId,
    name: j['name'] as String,
    // Forward-compat: unknown PropertyType names fall back to the
    // `unknown` sentinel rather than throwing. New enum members can
    // land additively in newer catalog schemas without breaking
    // older decoder builds.
    type: _tryEnumFromName(PropertyType.values, j['type'] as String) ??
        PropertyType.unknown,
    description: j['description'] as String,
    required: j['required'] as bool? ?? false,
    defaultSource:
        defaultSourceFromJson(j['defaultSource'], '$path.defaultSource'),
    category: j['category'] == null
        ? null
        : _enumFromName(
            PropertyCategory.values,
            j['category'] as String,
            'category',
            path,
          ),
    priority: j['priority'] == null
        ? null
        : _enumFromName(
            PropertyPriority.values,
            j['priority'] as String,
            'priority',
            path,
          ),
    deprecated: _deprecationFromJson(j['deprecated'], '$path.deprecated'),
    structuredRef: j['structuredRef'] == null
        ? null
        : wireIdRefFromJson(
            _jsonObject(j['structuredRef'], '$path.structuredRef'),
            '$path.structuredRef',
            expectedKind: WireIdKind.structured,
          ),
    unionRef: j['unionRef'] == null
        ? null
        : wireIdRefFromJson(
            _jsonObject(j['unionRef'], '$path.unionRef'),
            '$path.unionRef',
            expectedKind: WireIdKind.union,
          ),
    valueShape: _valueShapeFromJson(j['valueShape'], '$path.valueShape'),
  );
  // The decoder is the load-bearing half of the ref/type-shape contract: it
  // covers every entrypoint, including plain decodeCatalog (the customer-import
  // path), not just the requireNativeCatalog validation pass.
  _checkStructuredFieldRefShape(field, path);
  return field;
}

FactoryVariant _factoryVariantFromJson(Map<String, dynamic> j, String path) {
  final wireId = wireIdFromJson(j, 'wireId', path, WireIdKind.variant);
  if (j['sourceKind'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: sourceKind',
    );
  }
  final argMappingsRaw = j['argMappings'];
  final argMappings = <String, ArgMapping>{};
  if (argMappingsRaw != null) {
    if (argMappingsRaw is! Map) {
      throw CatalogSchemaException(
        '$path: malformed optional map field: argMappings',
      );
    }
    for (final entry in argMappingsRaw.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw CatalogSchemaException(
          '$path.argMappings: must map string to list<string>; got '
          '${entry.key.runtimeType} -> ${entry.value.runtimeType}',
        );
      }
      final targets = <WireId>[];
      for (final v in entry.value as List) {
        if (v is! String) {
          throw CatalogSchemaException(
            '$path.argMappings["${entry.key}"]: list entries must be wire ID '
            'strings; got ${v.runtimeType}',
          );
        }
        targets.add(
          wireIdFromString(
            v,
            '$path.argMappings',
            WireIdKind.property,
          ),
        );
      }
      argMappings[entry.key as String] =
          ArgMapping(targetFields: List.unmodifiable(targets));
    }
  }
  final parametersRaw = j['parameters'];
  var parameters = const <FactoryParameter>[];
  if (parametersRaw != null) {
    if (parametersRaw is! List) {
      throw CatalogSchemaException(
        '$path: malformed optional list field: parameters',
      );
    }
    parameters = List.unmodifiable([
      for (var i = 0; i < parametersRaw.length; i++)
        _factoryParameterFromJson(
          _jsonObject(parametersRaw[i], '$path.parameters[$i]'),
          '$path.parameters[$i]',
        ),
    ]);
  }
  final sourceKind = _enumFromName(
    VariantSourceKind.values,
    j['sourceKind'] as String,
    'sourceKind',
    path,
  );
  final namedConstructor = j['namedConstructor'] as String?;
  final staticAccessor = j['staticAccessor'] as String?;
  final description = j['description'] as String?;
  final deprecated = _deprecationFromJson(j['deprecated'], '$path.deprecated');
  switch (sourceKind) {
    case VariantSourceKind.constructor:
      return ConstructorVariant(
        wireId: wireId,
        namedConstructor: namedConstructor,
        argMappings: Map.unmodifiable(argMappings),
        parameters: parameters,
        description: description,
        deprecated: deprecated,
      );
    case VariantSourceKind.staticMethod:
      return StaticMethodVariant(
        wireId: wireId,
        staticAccessor:
            _requireVariantStaticAccessor(staticAccessor, sourceKind, path),
        argMappings: Map.unmodifiable(argMappings),
        parameters: parameters,
        description: description,
        deprecated: deprecated,
      );
    case VariantSourceKind.staticGetter:
      return StaticGetterVariant(
        wireId: wireId,
        staticAccessor:
            _requireVariantStaticAccessor(staticAccessor, sourceKind, path),
        description: description,
        deprecated: deprecated,
      );
    case VariantSourceKind.constValue:
      return ConstValueVariant(
        wireId: wireId,
        staticAccessor:
            _requireVariantStaticAccessor(staticAccessor, sourceKind, path),
        description: description,
        deprecated: deprecated,
      );
  }
}

/// A static method / getter / const-field variant carries its accessor name
/// non-null by construction; the wire must supply it. (The producers always
/// emit it; this guards a malformed payload rather than relaxing the type.)
String _requireVariantStaticAccessor(
  String? staticAccessor,
  VariantSourceKind sourceKind,
  String path,
) {
  if (staticAccessor == null) {
    throw CatalogSchemaException(
      '$path: a ${sourceKind.name} variant requires staticAccessor',
    );
  }
  return staticAccessor;
}

DartTypeRef _dartTypeRefFromJson(Map<String, dynamic> j, String path) {
  if (j['libraryUri'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: libraryUri',
    );
  }
  if (j['symbolName'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: symbolName',
    );
  }
  return DartTypeRef(
    libraryUri: j['libraryUri'] as String,
    symbolName: j['symbolName'] as String,
  );
}

CatalogValueShape? _valueShapeFromJson(Object? raw, String path) {
  if (raw == null) return null;
  if (raw is! Map) {
    throw CatalogSchemaException(
      '$path: valueShape must be an object; got ${raw.runtimeType}',
    );
  }
  final j = raw.cast<String, dynamic>();
  if (j['kind'] is! String) {
    throw CatalogSchemaException('$path: missing required string field: kind');
  }
  if (j['propertyType'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: propertyType',
    );
  }
  final kind = _requiredString(j, 'kind', path);
  final propertyType =
      _tryEnumFromName(PropertyType.values, j['propertyType'] as String) ??
          PropertyType.unknown;
  // Reject an incompatible (kind, propertyType) pairing before constructing
  // the subtype, so decode throws CatalogSchemaException (consistent with the
  // sibling malformed-wire errors) rather than tripping the constructor's
  // debug-mode mirror assert.
  _validatePropertyTypeForKind(kind, propertyType, path);
  // wireCodec is a cross-kind optional hint on the base; read it uniformly.
  final wireCodec = j['wireCodec'] == null
      ? null
      : _enumFromName(
          CatalogWireCodec.values,
          j['wireCodec'] as String,
          'wireCodec',
          path,
        );
  // Reject a wireCodec on a categorical (enum/structured) kind here too, so
  // decode throws consistently with the sibling malformed-wire errors rather
  // than admitting a meaningless hint that only the encode guard would catch.
  _rejectWireCodecOnCategoricalShape(kind, wireCodec, path);
  switch (kind) {
    case 'scalar':
      return ScalarShape(
        propertyType: propertyType,
        dartTypeRef: j['dartTypeRef'] == null
            ? null
            : _dartTypeRefFromJson(
                _jsonObject(j['dartTypeRef'], '$path.dartTypeRef'),
                '$path.dartTypeRef',
              ),
        wireCodec: wireCodec,
      );
    case 'enumValue':
      return EnumShape(
        propertyType: propertyType,
        enumRef: _dartTypeRefFromJson(
          _jsonObject(j['enumRef'], '$path.enumRef'),
          '$path.enumRef',
        ),
        wireCodec: wireCodec,
      );
    case 'structured':
      return StructuredShape(
        propertyType: propertyType,
        structuredRef: wireIdRefFromJson(
          _jsonObject(j['structuredRef'], '$path.structuredRef'),
          '$path.structuredRef',
          expectedKind: WireIdKind.structured,
        ),
        wireCodec: wireCodec,
      );
    case 'union':
      return UnionShape(
        propertyType: propertyType,
        unionRef: wireIdRefFromJson(
          _jsonObject(j['unionRef'], '$path.unionRef'),
          '$path.unionRef',
          expectedKind: WireIdKind.union,
        ),
        wireCodec: wireCodec,
      );
    case 'list':
      final itemShape = _valueShapeFromJson(j['itemShape'], '$path.itemShape');
      if (itemShape == null) {
        throw CatalogSchemaException(
          '$path.itemShape: list shape requires itemShape',
        );
      }
      return ListShape(
        propertyType: propertyType,
        itemShape: itemShape,
        wireCodec: wireCodec,
      );
    default:
      throw CatalogSchemaException('$path: unknown kind value: $kind');
  }
}

FactoryParameter _factoryParameterFromJson(
  Map<String, dynamic> j,
  String path,
) {
  final valueShape = _valueShapeFromJson(j['valueShape'], '$path.valueShape');
  if (valueShape == null) {
    throw CatalogSchemaException(
      '$path: missing required object field: valueShape',
    );
  }
  return FactoryParameter(
    wireId: wireIdFromJson(j, 'wireId', path, WireIdKind.parameter),
    name: j['name'] as String?,
    position: j['position'] as int?,
    kind: _enumFromName(
      FactoryParameterKind.values,
      _requiredString(j, 'kind', path),
      'kind',
      path,
    ),
    required: j['required'] as bool,
    nullable: j['nullable'] as bool,
    defaultPolicy: _enumFromName(
      FactoryParameterDefaultPolicy.values,
      j['defaultPolicy'] as String,
      'defaultPolicy',
      path,
    ),
    defaultValue: _parameterDefaultValueFromJson(
      j['defaultValue'],
      '$path.defaultValue',
    ),
    valueShape: valueShape,
  );
}

FactoryInvocation? _factoryInvocationFromJson(Object? raw, String path) {
  if (raw == null) return null;
  if (raw is! Map) {
    throw CatalogSchemaException(
      '$path: factory invocation must be an object; got ${raw.runtimeType}',
    );
  }
  final j = raw.cast<String, dynamic>();
  if (j['variantRef'] is! Map) {
    throw CatalogSchemaException(
      '$path: missing required map field: variantRef',
    );
  }
  if (j['receiver'] is! Map) {
    throw CatalogSchemaException('$path: missing required map field: receiver');
  }
  return FactoryInvocation(
    variantRef: wireIdRefFromJson(
      _jsonObject(j['variantRef'], '$path.variantRef'),
      '$path.variantRef',
      expectedKind: WireIdKind.variant,
    ),
    receiver: _factoryReceiverFromJson(
      _jsonObject(j['receiver'], '$path.receiver'),
      '$path.receiver',
    ),
    memberName: j['memberName'] as String?,
  );
}

FactoryReceiver _factoryReceiverFromJson(Map<String, dynamic> j, String path) {
  final kind = _requiredString(j, 'kind', path);
  switch (kind) {
    case 'resultStructuredType':
      return const ResultStructuredTypeReceiver();
    case 'owningWidgetType':
      return const OwningWidgetTypeReceiver();
    case 'explicitDartType':
      if (j['dartTypeRef'] is! Map) {
        throw CatalogSchemaException(
          '$path: explicitDartType receiver missing dartTypeRef',
        );
      }
      return ExplicitDartTypeReceiver(
        _dartTypeRefFromJson(
          _jsonObject(j['dartTypeRef'], '$path.dartTypeRef'),
          '$path.dartTypeRef',
        ),
      );
    default:
      throw CatalogSchemaException('$path: unknown kind value: $kind');
  }
}

DecompositionFieldMapping _fieldMappingFromJson(
  Map<String, dynamic> j,
  String path,
) {
  final transform = _valueTransformFromJson(j['transform'], '$path.transform');
  if (transform == null) {
    throw CatalogSchemaException(
      '$path: missing required object field: transform',
    );
  }
  return DecompositionFieldMapping(
    fieldRef: wireIdFromJson(j, 'fieldRef', path, WireIdKind.property),
    propertyRef: wireIdFromJson(j, 'propertyRef', path, WireIdKind.property),
    transform: transform,
  );
}

DecompositionParameterMapping _parameterMappingFromJson(
  Map<String, dynamic> j,
  String path,
) {
  final transform = _valueTransformFromJson(j['transform'], '$path.transform');
  if (transform == null) {
    throw CatalogSchemaException(
      '$path: missing required object field: transform',
    );
  }
  return DecompositionParameterMapping(
    parameterRef: wireIdFromJson(j, 'parameterRef', path, WireIdKind.parameter),
    propertyRef: wireIdFromJson(j, 'propertyRef', path, WireIdKind.property),
    transform: transform,
  );
}

FactoryParameterDefaultValue? _parameterDefaultValueFromJson(
  Object? raw,
  String path,
) {
  if (raw == null) return null;
  if (raw is! Map) {
    throw CatalogSchemaException(
      '$path: defaultValue must be an object; got ${raw.runtimeType}',
    );
  }
  final j = raw.cast<String, dynamic>();
  final kind = _requiredString(j, 'kind', path);
  switch (kind) {
    case 'literal':
      if (!j.containsKey('value')) {
        throw CatalogSchemaException(
          '$path: missing required field: value',
        );
      }
      return LiteralParameterDefault(j['value']);
    case 'staticMember':
      return StaticMemberParameterDefault(
        staticType: _dartTypeRefFromJson(
          _jsonObject(j['staticType'], '$path.staticType'),
          '$path.staticType',
        ),
        memberName: j['memberName'] as String,
      );
    default:
      throw CatalogSchemaException('$path: unknown kind value: $kind');
  }
}

DecompositionValueTransform? _valueTransformFromJson(Object? raw, String path) {
  if (raw == null) return null;
  if (raw is! Map) {
    throw CatalogSchemaException(
      '$path: transform must be an object; got ${raw.runtimeType}',
    );
  }
  final j = raw.cast<String, dynamic>();
  final kind = _requiredString(j, 'kind', path);
  switch (kind) {
    case 'identity':
      return const IdentityTransform();
    case 'constructVariant':
      final invocation =
          _factoryInvocationFromJson(j['invocation'], '$path.invocation');
      if (j['resultStructuredRef'] is! Map || invocation == null) {
        throw CatalogSchemaException(
          '$path: constructVariant requires resultStructuredRef and invocation',
        );
      }
      final bindingsRaw = j['argumentBindings'];
      return ConstructVariantTransform(
        resultStructuredRef: wireIdRefFromJson(
          _jsonObject(j['resultStructuredRef'], '$path.resultStructuredRef'),
          '$path.resultStructuredRef',
          expectedKind: WireIdKind.structured,
        ),
        invocation: invocation,
        argumentBindings: bindingsRaw == null
            ? const []
            : List.unmodifiable([
                for (var i = 0; i < (bindingsRaw as List).length; i++)
                  _argumentBindingFromJson(
                    _jsonObject(
                      bindingsRaw[i],
                      '$path.argumentBindings[$i]',
                    ),
                    '$path.argumentBindings[$i]',
                  ),
              ]),
      );
    case 'projectList':
      final itemTransform =
          _valueTransformFromJson(j['itemTransform'], '$path.itemTransform');
      if (itemTransform == null) {
        throw CatalogSchemaException(
          '$path: projectList requires itemTransform',
        );
      }
      return ProjectListTransform(itemTransform: itemTransform);
    case 'coerceScalar':
      return CoerceScalarTransform(
        scalarCoercion: j['scalarCoercion'] as String,
      );
    default:
      throw CatalogSchemaException('$path: unknown kind value: $kind');
  }
}

TransformArgumentBinding _argumentBindingFromJson(
  Map<String, dynamic> j,
  String path,
) {
  final parameterRef =
      wireIdFromJson(j, 'parameterRef', path, WireIdKind.parameter);
  final nullPolicy = _enumFromName(
    TransformNullPolicy.values,
    j['nullPolicy'] as String,
    'nullPolicy',
    path,
  );
  final missingPolicy = _enumFromName(
    TransformMissingPolicy.values,
    j['missingPolicy'] as String,
    'missingPolicy',
    path,
  );
  final source = j['source'] as String;
  switch (source) {
    case 'propertyValue':
      return PropertyValueArgumentBinding(
        parameterRef: parameterRef,
        nullPolicy: nullPolicy,
        missingPolicy: missingPolicy,
      );
    case 'literal':
      return LiteralArgumentBinding(
        literal: j['literal'],
        parameterRef: parameterRef,
        nullPolicy: nullPolicy,
        missingPolicy: missingPolicy,
      );
    case 'nestedTransform':
      final nested = _valueTransformFromJson(
        j['nestedTransform'],
        '$path.nestedTransform',
      );
      if (nested == null) {
        throw CatalogSchemaException(
          '$path.nestedTransform: nestedTransform source requires a transform',
        );
      }
      return NestedTransformArgumentBinding(
        nestedTransform: nested,
        parameterRef: parameterRef,
        nullPolicy: nullPolicy,
        missingPolicy: missingPolicy,
      );
    default:
      throw CatalogSchemaException('$path: unknown source value: $source');
  }
}

UnionEntry _unionFromJson(Map<String, dynamic> j, String path) {
  final wireId = wireIdFromJson(j, 'wireId', path, WireIdKind.union);
  if (j['name'] is! String) {
    throw CatalogSchemaException('$path: missing required string field: name');
  }
  final name = j['name'] as String;
  final unionPath = '$path "$name"';
  if (j['library'] is! String) {
    throw CatalogSchemaException(
      '$unionPath: missing required string field: library',
    );
  }
  if (j['description'] is! String) {
    throw CatalogSchemaException(
      '$unionPath: missing required string field: description',
    );
  }
  if (j['sourceType'] is! String) {
    throw CatalogSchemaException(
      '$unionPath: missing required string field: sourceType',
    );
  }
  if (j['memberSourceTypes'] is! List) {
    throw CatalogSchemaException(
      '$unionPath: missing required list field: memberSourceTypes',
    );
  }
  if (j['discriminator'] is! Map) {
    throw CatalogSchemaException(
      '$unionPath: missing required map field: discriminator',
    );
  }
  if (j['members'] is! List) {
    throw CatalogSchemaException(
      '$unionPath: missing required list field: members',
    );
  }
  final memberSourceTypesRaw = j['memberSourceTypes'] as List;
  final membersRaw = j['members'] as List;
  return UnionEntry(
    wireId: wireId,
    name: name,
    library: WidgetLibrary.fromNamespace(j['library'] as String),
    description: j['description'] as String,
    sourceType: j['sourceType'] as String,
    memberSourceTypes: List.unmodifiable([
      for (var i = 0; i < memberSourceTypesRaw.length; i++)
        if (memberSourceTypesRaw[i] is! String)
          throw CatalogSchemaException(
            '$unionPath.memberSourceTypes[$i]: expected string, '
            'got ${memberSourceTypesRaw[i].runtimeType}',
          )
        else
          memberSourceTypesRaw[i] as String,
    ]),
    discriminator: _discriminatorFromJson(
      _jsonObject(j['discriminator'], '$unionPath.discriminator'),
      '$unionPath.discriminator',
    ),
    members: List.unmodifiable([
      for (var i = 0; i < membersRaw.length; i++)
        wireIdRefFromJson(
          _jsonObject(membersRaw[i], '$unionPath.members[$i]'),
          '$unionPath.members[$i]',
          expectedKind: WireIdKind.structured,
        ),
    ]),
    stability: _stabilityFromJson(j['stability'], '$unionPath.stability'),
    deprecated: _deprecationFromJson(j['deprecated'], '$unionPath.deprecated'),
  );
}

DiscriminatorSpec _discriminatorFromJson(
  Map<String, dynamic> j,
  String path,
) {
  if (j['field'] is! String) {
    throw CatalogSchemaException('$path: missing required string field: field');
  }
  if (j['values'] is! List) {
    throw CatalogSchemaException('$path: missing required list field: values');
  }
  final valuesRaw = j['values'] as List;
  return DiscriminatorSpec(
    field: j['field'] as String,
    values: List.unmodifiable([
      for (var i = 0; i < valuesRaw.length; i++)
        wireIdRefFromJson(
          _jsonObject(valuesRaw[i], '$path.values[$i]'),
          '$path.values[$i]',
          expectedKind: WireIdKind.structured,
        ),
    ]),
  );
}

DesignTokenEntry _designTokenFromJson(Map<String, dynamic> j, String path) {
  final wireId = wireIdFromJson(j, 'wireId', path, WireIdKind.designToken);
  if (j['name'] is! String) {
    throw CatalogSchemaException('$path: missing required string field: name');
  }
  if (j['library'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: library',
    );
  }
  if (j['type'] is! String) {
    throw CatalogSchemaException('$path: missing required string field: type');
  }
  final resolverRaw = j['resolver'];
  return DesignTokenEntry(
    wireId: wireId,
    name: j['name'] as String,
    library: WidgetLibrary.fromNamespace(j['library'] as String),
    type: _enumFromName(
      DesignTokenType.values,
      j['type'] as String,
      'type',
      path,
    ),
    description: j['description'] as String?,
    resolver: resolverRaw == null
        ? null
        : themeBindingFromJson(
            _jsonObject(resolverRaw, '$path.resolver'),
            '$path.resolver',
          ),
    literalFallback: j['literalFallback'],
    stability: _stabilityFromJson(j['stability'], '$path.stability'),
    deprecated: _deprecationFromJson(j['deprecated'], '$path.deprecated'),
  );
}

DeprecationInfo? _deprecationFromJson(Object? raw, String path) {
  if (raw == null) return null;
  if (raw is! Map) {
    throw CatalogSchemaException(
      '$path: deprecation must be an object; got ${raw.runtimeType}',
    );
  }
  final j = raw.cast<String, dynamic>();
  final sourceRaw = j['source'];
  final catalogRaw = j['catalog'];
  return DeprecationInfo(
    source: sourceRaw == null
        ? null
        : _sourceDeprecationFromJson(
            _jsonObject(sourceRaw, '$path.source'),
            '$path.source',
          ),
    catalog: catalogRaw == null
        ? null
        : _catalogDeprecationFromJson(
            _jsonObject(catalogRaw, '$path.catalog'),
            '$path.catalog',
          ),
  );
}

SourceDeprecationInfo _sourceDeprecationFromJson(
  Map<String, dynamic> j,
  String path,
) {
  if (j['message'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: message',
    );
  }
  return SourceDeprecationInfo(
    message: j['message'] as String,
    since: j['since'] as String?,
  );
}

CatalogDeprecationInfo _catalogDeprecationFromJson(
  Map<String, dynamic> j,
  String path,
) {
  if (j['reason'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: reason',
    );
  }
  if (j['at'] is! String) {
    throw CatalogSchemaException('$path: missing required string field: at');
  }
  return CatalogDeprecationInfo(
    reason: j['reason'] as String,
    at: j['at'] as String,
    transitionId: j['transitionId'] as String?,
    replaceWith: j['replaceWith'] == null
        ? null
        : wireIdRefFromJson(
            _jsonObject(j['replaceWith'], '$path.replaceWith'),
            '$path.replaceWith',
          ),
  );
}

CompatRule _compatRuleFromJson(Map<String, dynamic> j, String path) {
  if (j['fromVersion'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: fromVersion',
    );
  }
  if (j['toVersion'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: toVersion',
    );
  }
  if (j['kind'] is! String) {
    throw CatalogSchemaException('$path: missing required string field: kind');
  }
  if (j['affectedRef'] is! Map) {
    throw CatalogSchemaException(
      '$path: missing required map field: affectedRef',
    );
  }
  return CompatRule(
    fromVersion: j['fromVersion'] as String,
    toVersion: j['toVersion'] as String,
    kind: _enumFromName(
      CompatKind.values,
      _requiredString(j, 'kind', path),
      'kind',
      path,
    ),
    affectedRef: wireIdRefFromJson(
      _jsonObject(j['affectedRef'], '$path.affectedRef'),
      '$path.affectedRef',
    ),
    successorRef: j['successorRef'] == null
        ? null
        : wireIdRefFromJson(
            _jsonObject(j['successorRef'], '$path.successorRef'),
            '$path.successorRef',
          ),
    transitionId: j['transitionId'] as String?,
    note: j['note'] as String?,
  );
}

T _enumFromName<T extends Enum>(
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
T? _tryEnumFromName<T extends Enum>(List<T> values, String name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// Reads a widget's `sinceVersion`, defaulting only an **absent** key to
/// [kBaselineCatalogVersion] so a catalog emitted before the field existed
/// (or a baseline widget that omits it) decodes unchanged. A present key
/// (including an explicit `null`) must be a valid integer — a malformed
/// `"sinceVersion": null` fails loud rather than silently normalizing to the
/// baseline.
int _sinceVersionFromJson(Map<String, dynamic> j, String key, String path) {
  if (!j.containsKey(key)) return kBaselineCatalogVersion;
  final raw = j[key];
  if (raw is! int) {
    throw CatalogSchemaException(
      '$path: sinceVersion must be an integer; '
      'got ${raw == null ? 'null' : raw.runtimeType}',
    );
  }
  _validateSinceVersion(raw, path);
  return raw;
}

Stability _stabilityFromJson(Object? raw, String path) {
  if (raw == null) return Stability.volatile;
  if (raw is! String) {
    throw CatalogSchemaException(
      '$path: stability must be a string; got ${raw.runtimeType}',
    );
  }
  try {
    return Stability.values.byName(raw);
    // ArgumentError carries the unknown-enum-name detail we surface
    // through CatalogSchemaException's contract.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    throw CatalogSchemaException(
      "$path: unknown stability '$raw'; expected one of "
      '${Stability.values.map((s) => s.name).join(', ')}',
    );
  }
}

/// Encode a [ValidationExpr] as a JSON object. Exposed so downstream
/// consumers can round-trip the type when persisted independently of a
/// catalog.
Map<String, dynamic> validationExprToJson(ValidationExpr v) => {
      'expression': v.expression,
      'message': v.message,
    };

/// Parse a [ValidationExpr] from a JSON object.
ValidationExpr validationExprFromJson(Map<String, dynamic> j, String path) {
  if (j['expression'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: expression',
    );
  }
  if (j['message'] is! String) {
    throw CatalogSchemaException(
      '$path: missing required string field: message',
    );
  }
  return ValidationExpr(
    expression: j['expression'] as String,
    message: j['message'] as String,
  );
}
