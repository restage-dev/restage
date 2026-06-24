import 'package:rfw_catalog_compiler/src/factory_variant_fields.dart';
import 'package:rfw_catalog_compiler/src/link/cross_ref_resolution_index.dart';
import 'package:rfw_catalog_compiler/src/wire_ids/union_source_key.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Thrown when a cross-reference cannot be resolved from the supplied index.
final class CrossRefLinkException implements Exception {
  /// Creates a cross-reference link exception.
  const CrossRefLinkException(this.message);

  /// Human-readable description of the unresolved or ambiguous cross-reference.
  final String message;

  @override
  String toString() => 'CrossRefLinkException: $message';
}

/// Applies allocated wire IDs to post-allocation cross-reference sites.
Catalog linkCrossReferences(Catalog catalog, CrossRefResolutionIndex index) {
  // ID maps from the catalog's resolved primaries. Built with explicit
  // duplicate-key detection (not map literals): a duplicate key with a
  // *differing* target would otherwise silently last-win and resolve a
  // cross-reference to the wrong wire ID. Built-in libraries are walked
  // per-library with sourceType-deduped entries, so no collision is expected;
  // the guard makes a future merged/multi-library catalog fail loud instead.
  final structuredIdBySourceType = <String, WireId>{};
  for (final structured in catalog.structuredTypes) {
    _putUnique(
      structuredIdBySourceType,
      structured.sourceType,
      structured.wireId,
      () => 'structured sourceType "${structured.sourceType}"',
    );
  }
  final unionIdBySourceKey = <String, WireId>{};
  for (final union in catalog.unions) {
    _putUnique(
      unionIdBySourceKey,
      unionSourceKey(union),
      union.wireId,
      () => 'union source key "${unionSourceKey(union)}"',
    );
  }
  final fieldIdByOwnerAndName = <(String, String), WireId>{};
  final variantByRef = <(String, WireId), (WireIdRef, FactoryVariant)>{};
  final variantBySourceAndIdentity =
      <(String, String), (WireIdRef, FactoryVariant)>{};
  final parameterOwnerByRef = <(String, WireId), WireIdRef>{};
  final parameterByVariantAndLabel = <(String, WireId, String), WireId>{};
  for (final structured in catalog.structuredTypes) {
    final structuredRef = WireIdRef(
      library: structured.library.namespace,
      wireId: structured.wireId,
    );
    for (final field in structured.fields) {
      _putUnique(
        fieldIdByOwnerAndName,
        (structured.sourceType, field.name),
        field.wireId,
        () => 'field "${structured.sourceType}.${field.name}"',
      );
    }
    for (final variant in structured.variants) {
      final variantRef = WireIdRef(
        library: structured.library.namespace,
        wireId: variant.wireId,
      );
      _putUniqueRef(
        variantByRef,
        (variantRef.library, variantRef.wireId),
        (structuredRef, variant),
        () => 'variant ref $variantRef',
      );
      _putUniqueRef(
        variantBySourceAndIdentity,
        (structured.sourceType, variantIdentity(variant)),
        (structuredRef, variant),
        () => 'variant "${structured.sourceType}.${variantIdentity(variant)}"',
      );
      for (final parameter in factoryVariantFields(variant).parameters) {
        final parameterRef = WireIdRef(
          library: structured.library.namespace,
          wireId: parameter.wireId,
        );
        _putUniqueRef(
          parameterOwnerByRef,
          (parameterRef.library, parameterRef.wireId),
          variantRef,
          () => 'parameter ref $parameterRef',
        );
        _putUnique(
          parameterByVariantAndLabel,
          (variantRef.library, variantRef.wireId, _parameterLabel(parameter)),
          parameter.wireId,
          () => 'parameter $variantRef.${_parameterLabel(parameter)}',
        );
      }
    }
  }

  final linkedStructuredTypes = [
    for (final structured in catalog.structuredTypes)
      _linkStructured(
        structured,
        index,
        structuredIdBySourceType,
        unionIdBySourceKey,
        fieldIdByOwnerAndName,
      ),
  ];
  final linkedStructuredByRef = <(String, WireId), StructuredEntry>{};
  for (final structured in linkedStructuredTypes) {
    final structuredRef = WireIdRef(
      library: structured.library.namespace,
      wireId: structured.wireId,
    );
    _putUniqueRef(
      linkedStructuredByRef,
      (structured.library.namespace, structured.wireId),
      structured,
      () => 'structured ref $structuredRef',
    );
  }

  final linked = Catalog(
    schemaVersion: catalog.schemaVersion,
    generatedAt: catalog.generatedAt,
    libraries: catalog.libraries,
    widgets: [
      for (final widget in catalog.widgets)
        _linkWidget(
          widget,
          index,
          structuredIdBySourceType,
          fieldIdByOwnerAndName,
          linkedStructuredByRef,
          variantByRef,
          variantBySourceAndIdentity,
          parameterOwnerByRef,
          parameterByVariantAndLabel,
        ),
    ],
    structuredTypes: linkedStructuredTypes,
    unions: [
      for (final union in catalog.unions)
        _linkUnion(union, structuredIdBySourceType),
    ],
    designTokens: catalog.designTokens,
    flutterVersion: catalog.flutterVersion,
    compatRules: catalog.compatRules,
  );

  // Totality: this pass must leave the catalog free of cross-reference
  // sentinels in every bucket — including decomposition recipes, which are
  // resolved upstream and passed through here untouched. Assert it directly so
  // a surviving sentinel fails loud here (with its site) rather than relying on
  // a downstream encodeCatalog rejection.
  _assertRefsResolve(linked);
  _assertSentinelFree(linked);
  return linked;
}

/// Inserts [key] -> [value], throwing when [key] is already mapped to a
/// *different* wire ID (an identical re-insert is allowed). A differing
/// duplicate means the resolution map is ambiguous and a cross-reference could
/// resolve to the wrong target.
void _putUnique<K>(
  Map<K, WireId> map,
  K key,
  WireId value,
  String Function() describeKey,
) {
  final existing = map[key];
  if (existing != null && existing != value) {
    throw CrossRefLinkException(
      'ambiguous cross-reference resolution map: ${describeKey()} maps to both '
      '${existing.value} and ${value.value}',
    );
  }
  map[key] = value;
}

void _putUniqueRef<K, V>(
  Map<K, V> map,
  K key,
  V value,
  String Function() describeKey,
) {
  if (map.containsKey(key)) {
    throw CrossRefLinkException(
      'ambiguous cross-reference resolution map: duplicate ${describeKey()}',
    );
  }
  map[key] = value;
}

/// Asserts [catalog] carries no unallocated cross-reference (or primary)
/// sentinel after linking, across all 13 sentinel buckets. Throws
/// [CrossRefLinkException] with the offending site on the first sentinel found.
void _assertSentinelFree(Catalog catalog) {
  void check(WireId id, String site) {
    if (id.isUnallocated) {
      throw CrossRefLinkException(
        'unresolved sentinel ${id.value} after linking at $site',
      );
    }
  }

  void checkInvocation(FactoryInvocation? invocation, String site) {
    if (invocation == null) return;
    check(invocation.variantRef.wireId, '$site.variantRef');
  }

  void checkTransform(DecompositionValueTransform transform, String site) {
    switch (transform) {
      case IdentityTransform():
      case CoerceScalarTransform():
        return;
      case ConstructVariantTransform(
          :final resultStructuredRef,
          :final invocation,
          :final argumentBindings,
        ):
        check(resultStructuredRef.wireId, '$site.resultStructuredRef');
        checkInvocation(invocation, '$site.invocation');
        for (var i = 0; i < argumentBindings.length; i++) {
          final binding = argumentBindings[i];
          final bindingSite = '$site.argumentBindings[$i]';
          check(binding.parameterRef, '$bindingSite.parameterRef');
          if (binding is NestedTransformArgumentBinding) {
            checkTransform(
              binding.nestedTransform,
              '$bindingSite.nestedTransform',
            );
          }
        }
      case ProjectListTransform(:final itemTransform):
        checkTransform(itemTransform, '$site.itemTransform');
    }
  }

  void checkValueShape(CatalogValueShape? shape, String site) {
    if (shape == null) return;
    switch (shape) {
      case ScalarShape():
      case EnumShape():
        break;
      case StructuredShape(:final structuredRef):
        check(structuredRef.wireId, '$site.structuredRef');
      case UnionShape(:final unionRef):
        check(unionRef.wireId, '$site.unionRef');
      case ListShape(:final itemShape):
        checkValueShape(itemShape, '$site.itemShape');
    }
  }

  for (final widget in catalog.widgets) {
    check(widget.wireId, 'widget "${widget.name}".wireId');
    for (final property in widget.properties) {
      check(
        property.wireId,
        'widget "${widget.name}".property "${property.name}"',
      );
      checkValueShape(
        property.valueShape,
        'widget "${widget.name}".property "${property.name}".valueShape',
      );
    }
    for (var i = 0; i < widget.decomposes.length; i++) {
      final recipe = widget.decomposes[i];
      final recipeSite = 'widget "${widget.name}".decomposes[$i]';
      check(
        recipe.structuredRef.wireId,
        '$recipeSite.structuredRef',
      );
      checkInvocation(recipe.construction, '$recipeSite.construction');
      for (final entry in recipe.flatProperties.entries) {
        check(
          entry.key,
          '$recipeSite.flatProperties.key',
        );
        check(
          entry.value,
          '$recipeSite.flatProperties.value',
        );
      }
      for (var j = 0; j < recipe.fieldMappings.length; j++) {
        final mapping = recipe.fieldMappings[j];
        final mappingSite = '$recipeSite.fieldMappings[$j]';
        check(mapping.fieldRef, '$mappingSite.fieldRef');
        check(mapping.propertyRef, '$mappingSite.propertyRef');
        checkTransform(mapping.transform, '$mappingSite.transform');
      }
      for (var j = 0; j < recipe.parameterMappings.length; j++) {
        final mapping = recipe.parameterMappings[j];
        final mappingSite = '$recipeSite.parameterMappings[$j]';
        check(mapping.parameterRef, '$mappingSite.parameterRef');
        check(mapping.propertyRef, '$mappingSite.propertyRef');
        checkTransform(mapping.transform, '$mappingSite.transform');
      }
    }
  }
  for (final structured in catalog.structuredTypes) {
    final structuredSite = 'structured "${structured.sourceType}"';
    check(structured.wireId, '$structuredSite.wireId');
    for (final field in structured.fields) {
      final fieldSite = '$structuredSite.field "${field.name}"';
      check(field.wireId, fieldSite);
      final structuredRef = field.structuredRef;
      if (structuredRef != null) {
        check(structuredRef.wireId, '$fieldSite.structuredRef');
      }
      final unionRef = field.unionRef;
      if (unionRef != null) {
        check(unionRef.wireId, '$fieldSite.unionRef');
      }
      checkValueShape(field.valueShape, '$fieldSite.valueShape');
    }
    for (final variant in structured.variants) {
      final variantSite =
          '$structuredSite.variant "${variantIdentity(variant)}"';
      check(variant.wireId, variantSite);
      final variantFields = factoryVariantFields(variant);
      for (final entry in variantFields.argMappings.entries) {
        for (final target in entry.value.targetFields) {
          check(target, '$variantSite.argMappings["${entry.key}"]');
        }
      }
      for (var i = 0; i < variantFields.parameters.length; i++) {
        final parameter = variantFields.parameters[i];
        final parameterSite = '$variantSite.parameters[$i]';
        check(parameter.wireId, '$parameterSite.wireId');
        checkValueShape(parameter.valueShape, '$parameterSite.valueShape');
      }
    }
  }
  for (final union in catalog.unions) {
    check(union.wireId, 'union "${union.sourceType}".wireId');
    for (var i = 0; i < union.members.length; i++) {
      check(union.members[i].wireId, 'union "${union.sourceType}".members[$i]');
    }
    for (var i = 0; i < union.discriminator.values.length; i++) {
      check(
        union.discriminator.values[i].wireId,
        'union "${union.sourceType}".discriminator.values[$i]',
      );
    }
  }
  for (final token in catalog.designTokens) {
    check(token.wireId, 'designToken "${token.name}".wireId');
  }
}

/// Asserts catalog refs that are not otherwise source-resolved point at entries
/// present in the linked graph.
void _assertRefsResolve(Catalog catalog) {
  final structuredRefs = {
    for (final structured in catalog.structuredTypes)
      (structured.library.namespace, structured.wireId),
  };
  final unionRefs = {
    for (final union in catalog.unions) (union.library.namespace, union.wireId),
  };

  void requireStructured(WireIdRef ref, String site) {
    if (structuredRefs.contains((ref.library, ref.wireId))) return;
    throw CrossRefLinkException(
      '$site does not resolve: ${ref.wireId}',
    );
  }

  void requireUnion(WireIdRef ref, String site) {
    if (unionRefs.contains((ref.library, ref.wireId))) return;
    throw CrossRefLinkException(
      '$site does not resolve: ${ref.wireId}',
    );
  }

  void checkValueShape(CatalogValueShape? shape, String site) {
    if (shape == null) return;
    switch (shape) {
      case ScalarShape():
      case EnumShape():
        return;
      case StructuredShape(:final structuredRef):
        requireStructured(structuredRef, '$site.structuredRef');
      case UnionShape(:final unionRef):
        requireUnion(unionRef, '$site.unionRef');
      case ListShape(:final itemShape):
        checkValueShape(itemShape, '$site.itemShape');
    }
  }

  for (final widget in catalog.widgets) {
    for (var i = 0; i < widget.properties.length; i++) {
      final property = widget.properties[i];
      final propertySite = 'widget "${widget.name}".properties[$i]';
      final structuredRef = property.structuredRef;
      if (structuredRef != null) {
        requireStructured(structuredRef, '$propertySite.structuredRef');
      }
      checkValueShape(property.valueShape, '$propertySite.valueShape');
    }
    for (var i = 0; i < widget.decomposes.length; i++) {
      final recipe = widget.decomposes[i];
      requireStructured(
        recipe.structuredRef,
        'widget "${widget.name}".decomposes[$i].structuredRef',
      );
    }
  }

  for (final structured in catalog.structuredTypes) {
    final structuredSite = 'structured "${structured.sourceType}"';
    for (var i = 0; i < structured.fields.length; i++) {
      final field = structured.fields[i];
      final fieldSite = '$structuredSite.fields[$i]';
      final structuredRef = field.structuredRef;
      if (structuredRef != null) {
        requireStructured(structuredRef, '$fieldSite.structuredRef');
      }
      final unionRef = field.unionRef;
      if (unionRef != null) requireUnion(unionRef, '$fieldSite.unionRef');
      checkValueShape(field.valueShape, '$fieldSite.valueShape');
    }
    for (var i = 0; i < structured.variants.length; i++) {
      final variant = structured.variants[i];
      final parameters = factoryVariantFields(variant).parameters;
      for (var j = 0; j < parameters.length; j++) {
        checkValueShape(
          parameters[j].valueShape,
          '$structuredSite.variants[$i].parameters[$j].valueShape',
        );
      }
    }
  }

  for (final union in catalog.unions) {
    for (var i = 0; i < union.members.length; i++) {
      requireStructured(union.members[i], 'union "${union.name}".members[$i]');
    }
    for (var i = 0; i < union.discriminator.values.length; i++) {
      requireStructured(
        union.discriminator.values[i],
        'union "${union.name}".discriminator.values[$i]',
      );
    }
  }
}

UnionEntry _linkUnion(
  UnionEntry union,
  Map<String, WireId> structuredIdBySourceType,
) {
  if (union.members.length != union.memberSourceTypes.length ||
      union.discriminator.values.length != union.memberSourceTypes.length) {
    throw CrossRefLinkException(
      'union ${union.sourceType} has mismatched member/discriminator '
      'lengths: members=${union.members.length}, '
      'memberSourceTypes=${union.memberSourceTypes.length}, '
      'discriminator.values=${union.discriminator.values.length}',
    );
  }

  final members = <WireIdRef>[];
  for (var i = 0; i < union.members.length; i++) {
    final member = union.members[i];
    if (!member.wireId.isUnallocated) {
      members.add(member);
      continue;
    }
    final sourceType = union.memberSourceTypes[i];
    final wireId = structuredIdBySourceType[sourceType];
    if (wireId == null) {
      throw CrossRefLinkException(
        "structuredIdBySourceType has no entry for '$sourceType' "
        "referenced by union '${union.sourceType}'.members[$i]",
      );
    }
    members.add(WireIdRef(library: union.library.namespace, wireId: wireId));
  }

  final discriminatorValues = <WireIdRef>[];
  for (var i = 0; i < union.discriminator.values.length; i++) {
    final value = union.discriminator.values[i];
    discriminatorValues.add(
      value.wireId.isUnallocated ? members[i] : value,
    );
  }

  return UnionEntry(
    wireId: union.wireId,
    name: union.name,
    library: union.library,
    description: union.description,
    sourceType: union.sourceType,
    memberSourceTypes: union.memberSourceTypes,
    discriminator: DiscriminatorSpec(
      field: union.discriminator.field,
      values: List.unmodifiable(discriminatorValues),
    ),
    members: List.unmodifiable(members),
    stability: union.stability,
    deprecated: union.deprecated,
  );
}

WidgetEntry _linkWidget(
  WidgetEntry widget,
  CrossRefResolutionIndex index,
  Map<String, WireId> structuredIdBySourceType,
  Map<(String, String), WireId> fieldIdByOwnerAndName,
  Map<(String, WireId), StructuredEntry> structuredByRef,
  Map<(String, WireId), (WireIdRef, FactoryVariant)> variantByRef,
  Map<(String, String), (WireIdRef, FactoryVariant)> variantBySourceAndIdentity,
  Map<(String, WireId), WireIdRef> parameterOwnerByRef,
  Map<(String, WireId, String), WireId> parameterByVariantAndLabel,
) {
  final properties = _linkWidgetPropertyValueShapes(
    widget: widget,
    index: index,
    structuredIdBySourceType: structuredIdBySourceType,
    fieldIdByOwnerAndName: fieldIdByOwnerAndName,
    structuredByRef: structuredByRef,
    variantBySourceAndIdentity: variantBySourceAndIdentity,
    parameterByVariantAndLabel: parameterByVariantAndLabel,
  );
  final recipeWidget = WidgetEntry(
    wireId: widget.wireId,
    name: widget.name,
    library: widget.library,
    category: widget.category,
    description: widget.description,
    flutterType: widget.flutterType,
    childrenSlot: widget.childrenSlot,
    fires: widget.fires,
    properties: properties,
    decomposes: widget.decomposes,
    sinceVersion: widget.sinceVersion,
    deprecatedSince: widget.deprecatedSince,
    stability: widget.stability,
    deprecated: widget.deprecated,
  );
  return WidgetEntry(
    wireId: widget.wireId,
    name: widget.name,
    library: widget.library,
    category: widget.category,
    description: widget.description,
    flutterType: widget.flutterType,
    childrenSlot: widget.childrenSlot,
    fires: widget.fires,
    properties: properties,
    decomposes: [
      for (var i = 0; i < widget.decomposes.length; i++)
        _linkDecomposition(
          widget: recipeWidget,
          recipe: widget.decomposes[i],
          recipeIndex: i,
          index: index,
          structuredIdBySourceType: structuredIdBySourceType,
          fieldIdByOwnerAndName: fieldIdByOwnerAndName,
          structuredByRef: structuredByRef,
          variantByRef: variantByRef,
          variantBySourceAndIdentity: variantBySourceAndIdentity,
          parameterOwnerByRef: parameterOwnerByRef,
          parameterByVariantAndLabel: parameterByVariantAndLabel,
        ),
    ],
    sinceVersion: widget.sinceVersion,
    deprecatedSince: widget.deprecatedSince,
    stability: widget.stability,
    deprecated: widget.deprecated,
  );
}

List<PropertyEntry> _linkWidgetPropertyValueShapes({
  required WidgetEntry widget,
  required CrossRefResolutionIndex index,
  required Map<String, WireId> structuredIdBySourceType,
  required Map<(String, String), WireId> fieldIdByOwnerAndName,
  required Map<(String, WireId), StructuredEntry> structuredByRef,
  required Map<(String, String), (WireIdRef, FactoryVariant)>
      variantBySourceAndIdentity,
  required Map<(String, WireId, String), WireId> parameterByVariantAndLabel,
}) {
  final properties = List<PropertyEntry>.of(widget.properties);
  for (var recipeIndex = 0;
      recipeIndex < widget.decomposes.length;
      recipeIndex++) {
    final recipe = widget.decomposes[recipeIndex];
    final linkedRecipe = _linkDecompositionRefs(
      widget: widget,
      recipe: recipe,
      recipeIndex: recipeIndex,
      index: index,
      structuredIdBySourceType: structuredIdBySourceType,
      fieldIdByOwnerAndName: fieldIdByOwnerAndName,
      variantBySourceAndIdentity: variantBySourceAndIdentity,
      parameterByVariantAndLabel: parameterByVariantAndLabel,
      path: 'widget "${widget.name}".decomposes[$recipeIndex]',
    );
    final structured = structuredByRef[(
      linkedRecipe.structuredRef.library,
      linkedRecipe.structuredRef.wireId,
    )];
    if (structured == null) continue;
    final fieldsById = {
      for (final field in structured.fields) field.wireId: field,
    };
    for (final mapping in linkedRecipe.fieldMappings) {
      switch (mapping.transform) {
        case IdentityTransform():
        case ProjectListTransform():
          break;
        case ConstructVariantTransform():
        case CoerceScalarTransform():
          continue;
      }
      final fieldShape = fieldsById[mapping.fieldRef]?.valueShape;
      if (fieldShape == null) continue;
      final propertyIndex = properties.indexWhere(
        (property) => property.wireId == mapping.propertyRef,
      );
      if (propertyIndex == -1) continue;
      final propertyShape = properties[propertyIndex].valueShape;
      if (propertyShape != null &&
          !_valueShapeHasUnallocatedRef(propertyShape)) {
        continue;
      }
      properties[propertyIndex] = _copyPropertyWithValueShape(
        properties[propertyIndex],
        fieldShape,
      );
    }
  }
  return List.unmodifiable(properties);
}

PropertyEntry _copyPropertyWithValueShape(
  PropertyEntry base,
  CatalogValueShape valueShape,
) {
  return PropertyEntry(
    wireId: base.wireId,
    name: base.name,
    type: base.type,
    description: base.description,
    required: base.required,
    defaultBrandToken: base.defaultBrandToken,
    synthetic: base.synthetic,
    positional: base.positional,
    enumType: base.enumType,
    widgetType: base.widgetType,
    callbackSignature: base.callbackSignature,
    firesAs: base.firesAs,
    defaultSource: base.defaultSource,
    mutuallyExclusiveWith: base.mutuallyExclusiveWith,
    requiresAncestor: base.requiresAncestor,
    category: base.category,
    priority: base.priority,
    validationRule: base.validationRule,
    deprecated: base.deprecated,
    structuredRef: base.structuredRef,
    valueShape: valueShape,
  );
}

bool _valueShapeHasUnallocatedRef(CatalogValueShape shape) {
  switch (shape) {
    case ScalarShape():
    case EnumShape():
      return false;
    case StructuredShape(:final structuredRef):
      return structuredRef.wireId.isUnallocated;
    case UnionShape(:final unionRef):
      return unionRef.wireId.isUnallocated;
    case ListShape(:final itemShape):
      return _valueShapeHasUnallocatedRef(itemShape);
  }
}

DecompositionRecipe _linkDecompositionRefs({
  required WidgetEntry widget,
  required DecompositionRecipe recipe,
  required int recipeIndex,
  required CrossRefResolutionIndex index,
  required Map<String, WireId> structuredIdBySourceType,
  required Map<(String, String), WireId> fieldIdByOwnerAndName,
  required Map<(String, String), (WireIdRef, FactoryVariant)>
      variantBySourceAndIdentity,
  required Map<(String, WireId, String), WireId> parameterByVariantAndLabel,
  required String path,
}) {
  final recipeKey = (widget.flutterType, recipeIndex);
  final structuredSource =
      index.decompositionStructuredSourceByWidget[recipeKey];
  var structuredRef = recipe.structuredRef;
  if (structuredRef.wireId.isUnallocated) {
    if (structuredSource == null) {
      throw CrossRefLinkException(
        'CrossRefResolutionIndex.decompositionStructuredSourceByWidget has '
        "no entry for '$recipeKey'",
      );
    }
    final structuredId = structuredIdBySourceType[structuredSource];
    if (structuredId == null) {
      throw CrossRefLinkException(
        "structuredIdBySourceType has no entry for '$structuredSource' "
        'referenced by $path.structuredRef',
      );
    }
    structuredRef =
        WireIdRef(library: structuredRef.library, wireId: structuredId);
  }

  final construction = recipe.construction == null
      ? null
      : _linkRecipeInvocation(
          invocation: recipe.construction!,
          structuredSource: structuredSource,
          variantIdentity:
              index.decompositionConstructionVariantByWidget[recipeKey],
          variantBySourceAndIdentity: variantBySourceAndIdentity,
          path: '$path.construction',
        );

  final propertiesByName = {
    for (final property in widget.properties) property.name: property,
  };
  final linkedMappings = <DecompositionFieldMapping>[];
  for (var i = 0; i < recipe.fieldMappings.length; i++) {
    final mapping = recipe.fieldMappings[i];
    final mappingKey = (widget.flutterType, recipeIndex, i);
    final names = index.decompositionFieldMappingNames[mappingKey];
    var fieldRef = mapping.fieldRef;
    if (fieldRef.isUnallocated) {
      if (structuredSource == null || names == null) {
        throw CrossRefLinkException(
          'CrossRefResolutionIndex.decompositionFieldMappingNames has no '
          "entry for '$mappingKey'",
        );
      }
      final linked = fieldIdByOwnerAndName[(structuredSource, names.$1)];
      if (linked == null) {
        throw CrossRefLinkException(
          "fieldIdByOwnerAndName has no entry for '$structuredSource."
          "${names.$1}' referenced by $path.fieldMappings[$i].fieldRef",
        );
      }
      fieldRef = linked;
    }
    var propertyRef = mapping.propertyRef;
    if (propertyRef.isUnallocated) {
      if (names == null) {
        throw CrossRefLinkException(
          'CrossRefResolutionIndex.decompositionFieldMappingNames has no '
          "entry for '$mappingKey'",
        );
      }
      final property = propertiesByName[names.$2];
      if (property == null) {
        throw CrossRefLinkException(
          '${widget.name}.${names.$2} referenced by '
          '$path.fieldMappings[$i].propertyRef does not exist',
        );
      }
      propertyRef = property.wireId;
    }
    linkedMappings.add(
      DecompositionFieldMapping(
        fieldRef: fieldRef,
        propertyRef: propertyRef,
        transform: _linkRecipeTransform(
          transform: mapping.transform,
          widgetFlutterType: widget.flutterType,
          recipeIndex: recipeIndex,
          mappingIndex: i,
          index: index,
          structuredIdBySourceType: structuredIdBySourceType,
          variantBySourceAndIdentity: variantBySourceAndIdentity,
          parameterByVariantAndLabel: parameterByVariantAndLabel,
          path: '$path.fieldMappings[$i].transform',
          transformPath: '',
        ),
      ),
    );
  }
  final linkedParameterMappings = <DecompositionParameterMapping>[];
  for (var i = 0; i < recipe.parameterMappings.length; i++) {
    final mapping = recipe.parameterMappings[i];
    final mappingKey = (widget.flutterType, recipeIndex, i);
    final names = index.decompositionParameterMappingNames[mappingKey];
    var parameterRef = mapping.parameterRef;
    if (parameterRef.isUnallocated) {
      final constructionRef = construction?.variantRef;
      if (constructionRef == null || names == null) {
        throw CrossRefLinkException(
          'CrossRefResolutionIndex.decompositionParameterMappingNames has no '
          "entry for '$mappingKey'",
        );
      }
      final linked = parameterByVariantAndLabel[(
        constructionRef.library,
        constructionRef.wireId,
        names.$1,
      )];
      if (linked == null) {
        throw CrossRefLinkException(
          'parameterByVariantAndLabel has no entry for '
          "'$constructionRef.${names.$1}' referenced by "
          '$path.parameterMappings[$i].parameterRef',
        );
      }
      parameterRef = linked;
    }
    var propertyRef = mapping.propertyRef;
    if (propertyRef.isUnallocated) {
      if (names == null) {
        throw CrossRefLinkException(
          'CrossRefResolutionIndex.decompositionParameterMappingNames has no '
          "entry for '$mappingKey'",
        );
      }
      final property = propertiesByName[names.$2];
      if (property == null) {
        throw CrossRefLinkException(
          '${widget.name}.${names.$2} referenced by '
          '$path.parameterMappings[$i].propertyRef does not exist',
        );
      }
      propertyRef = property.wireId;
    }
    linkedParameterMappings.add(
      DecompositionParameterMapping(
        parameterRef: parameterRef,
        propertyRef: propertyRef,
        transform: mapping.transform,
      ),
    );
  }

  return DecompositionRecipe(
    structuredRef: structuredRef,
    flatProperties: recipe.flatProperties,
    targetArg: recipe.targetArg,
    construction: construction,
    fieldMappings: List.unmodifiable(linkedMappings),
    parameterMappings: List.unmodifiable(linkedParameterMappings),
    discriminator: recipe.discriminator,
  );
}

FactoryInvocation _linkRecipeInvocation({
  required FactoryInvocation invocation,
  required String? structuredSource,
  required String? variantIdentity,
  required Map<(String, String), (WireIdRef, FactoryVariant)>
      variantBySourceAndIdentity,
  required String path,
}) {
  if (!invocation.variantRef.wireId.isUnallocated) return invocation;
  if (structuredSource == null || variantIdentity == null) {
    throw CrossRefLinkException(
      'CrossRefResolutionIndex has no variant entry for $path',
    );
  }
  final variant =
      variantBySourceAndIdentity[(structuredSource, variantIdentity)];
  if (variant == null) {
    throw CrossRefLinkException(
      "variantBySourceAndIdentity has no entry for '$structuredSource."
      "$variantIdentity' referenced by $path.variantRef",
    );
  }
  return FactoryInvocation(
    variantRef: WireIdRef(
      library: variant.$1.library,
      wireId: variant.$2.wireId,
    ),
    receiver: invocation.receiver,
    memberName: invocation.memberName,
  );
}

DecompositionValueTransform _linkRecipeTransform({
  required DecompositionValueTransform transform,
  required String widgetFlutterType,
  required int recipeIndex,
  required int mappingIndex,
  required CrossRefResolutionIndex index,
  required Map<String, WireId> structuredIdBySourceType,
  required Map<(String, String), (WireIdRef, FactoryVariant)>
      variantBySourceAndIdentity,
  required Map<(String, WireId, String), WireId> parameterByVariantAndLabel,
  required String path,
  required String transformPath,
}) {
  switch (transform) {
    case IdentityTransform():
    case CoerceScalarTransform():
      return transform;
    case ProjectListTransform(:final itemTransform):
      return ProjectListTransform(
        itemTransform: _linkRecipeTransform(
          transform: itemTransform,
          widgetFlutterType: widgetFlutterType,
          recipeIndex: recipeIndex,
          mappingIndex: mappingIndex,
          index: index,
          structuredIdBySourceType: structuredIdBySourceType,
          variantBySourceAndIdentity: variantBySourceAndIdentity,
          parameterByVariantAndLabel: parameterByVariantAndLabel,
          path: '$path.itemTransform',
          transformPath: '$transformPath.itemTransform',
        ),
      );
    case ConstructVariantTransform(
        resultStructuredRef: final transformResultStructuredRef,
        invocation: final transformInvocation,
        argumentBindings: final transformArgumentBindings,
      ):
      final mappingKey = (widgetFlutterType, recipeIndex, mappingIndex);
      final pathKey = (
        widgetFlutterType,
        recipeIndex,
        mappingIndex,
        transformPath,
      );
      final structuredSourceByMapping =
          index.decompositionTransformStructuredSourceByMapping;
      final structuredSource =
          index.decompositionTransformStructuredSourceByPath[pathKey] ??
              (transformPath.isEmpty
                  ? structuredSourceByMapping[mappingKey]
                  : null);
      var resultStructuredRef = transformResultStructuredRef;
      if (resultStructuredRef.wireId.isUnallocated) {
        if (structuredSource == null) {
          throw CrossRefLinkException(
            'CrossRefResolutionIndex.'
            'decompositionTransformStructuredSourceByMapping has no entry '
            "for '$mappingKey'",
          );
        }
        final structuredId = structuredIdBySourceType[structuredSource];
        if (structuredId == null) {
          throw CrossRefLinkException(
            "structuredIdBySourceType has no entry for '$structuredSource' "
            'referenced by $path.resultStructuredRef',
          );
        }
        resultStructuredRef = WireIdRef(
          library: resultStructuredRef.library,
          wireId: structuredId,
        );
      }
      final transformVariantByMapping =
          index.decompositionTransformVariantByMapping;
      final invocation = _linkRecipeInvocation(
        invocation: transformInvocation,
        structuredSource: structuredSource,
        variantIdentity: index.decompositionTransformVariantByPath[pathKey] ??
            (transformPath.isEmpty
                ? transformVariantByMapping[mappingKey]
                : null),
        variantBySourceAndIdentity: variantBySourceAndIdentity,
        path: '$path.invocation',
      );
      return ConstructVariantTransform(
        resultStructuredRef: resultStructuredRef,
        invocation: invocation,
        argumentBindings: [
          for (var i = 0; i < transformArgumentBindings.length; i++)
            _linkRecipeArgumentBinding(
              binding: transformArgumentBindings[i],
              invocation: invocation,
              widgetFlutterType: widgetFlutterType,
              recipeIndex: recipeIndex,
              mappingIndex: mappingIndex,
              bindingIndex: i,
              index: index,
              structuredIdBySourceType: structuredIdBySourceType,
              variantBySourceAndIdentity: variantBySourceAndIdentity,
              parameterByVariantAndLabel: parameterByVariantAndLabel,
              path: '$path.argumentBindings[$i]',
              transformPath: transformPath,
            ),
        ],
      );
  }
}

TransformArgumentBinding _linkRecipeArgumentBinding({
  required TransformArgumentBinding binding,
  required FactoryInvocation? invocation,
  required String widgetFlutterType,
  required int recipeIndex,
  required int mappingIndex,
  required int bindingIndex,
  required CrossRefResolutionIndex index,
  required Map<String, WireId> structuredIdBySourceType,
  required Map<(String, String), (WireIdRef, FactoryVariant)>
      variantBySourceAndIdentity,
  required Map<(String, WireId, String), WireId> parameterByVariantAndLabel,
  required String path,
  required String transformPath,
}) {
  var parameterRef = binding.parameterRef;
  if (parameterRef.isUnallocated) {
    if (invocation == null) {
      throw CrossRefLinkException(
        '$path.parameterRef cannot resolve without an invocation',
      );
    }
    final label = index.decompositionTransformParameterLabelsByPath[(
          widgetFlutterType,
          recipeIndex,
          mappingIndex,
          transformPath,
          bindingIndex,
        )] ??
        (transformPath.isEmpty
            ? index.decompositionTransformParameterLabels[(
                widgetFlutterType,
                recipeIndex,
                mappingIndex,
                bindingIndex,
              )]
            : null);
    if (label == null) {
      throw CrossRefLinkException(
        'CrossRefResolutionIndex.decompositionTransformParameterLabels has no '
        "entry for '($widgetFlutterType, $recipeIndex, $mappingIndex, "
        "$bindingIndex)'",
      );
    }
    final linked = parameterByVariantAndLabel[(
      invocation.variantRef.library,
      invocation.variantRef.wireId,
      label,
    )];
    if (linked == null) {
      throw CrossRefLinkException(
        'parameterByVariantAndLabel has no entry for '
        '${invocation.variantRef}.$label referenced by $path.parameterRef',
      );
    }
    parameterRef = linked;
  }
  switch (binding) {
    case PropertyValueArgumentBinding():
      return PropertyValueArgumentBinding(
        parameterRef: parameterRef,
        nullPolicy: binding.nullPolicy,
        missingPolicy: binding.missingPolicy,
      );
    case LiteralArgumentBinding():
      return LiteralArgumentBinding(
        literal: binding.literal,
        parameterRef: parameterRef,
        nullPolicy: binding.nullPolicy,
        missingPolicy: binding.missingPolicy,
      );
    case NestedTransformArgumentBinding():
      return NestedTransformArgumentBinding(
        nestedTransform: _linkRecipeTransform(
          transform: binding.nestedTransform,
          widgetFlutterType: widgetFlutterType,
          recipeIndex: recipeIndex,
          mappingIndex: mappingIndex,
          index: index,
          structuredIdBySourceType: structuredIdBySourceType,
          variantBySourceAndIdentity: variantBySourceAndIdentity,
          parameterByVariantAndLabel: parameterByVariantAndLabel,
          path: '$path.nestedTransform',
          transformPath: _nestedTransformPath(transformPath, bindingIndex),
        ),
        parameterRef: parameterRef,
        nullPolicy: binding.nullPolicy,
        missingPolicy: binding.missingPolicy,
      );
  }
}

String _nestedTransformPath(String parentPath, int bindingIndex) {
  final segment = 'argumentBindings[$bindingIndex].nestedTransform';
  if (parentPath.isEmpty) return segment;
  return '$parentPath.$segment';
}

DecompositionRecipe _linkDecomposition({
  required WidgetEntry widget,
  required DecompositionRecipe recipe,
  required int recipeIndex,
  required CrossRefResolutionIndex index,
  required Map<String, WireId> structuredIdBySourceType,
  required Map<(String, String), WireId> fieldIdByOwnerAndName,
  required Map<(String, WireId), StructuredEntry> structuredByRef,
  required Map<(String, WireId), (WireIdRef, FactoryVariant)> variantByRef,
  required Map<(String, String), (WireIdRef, FactoryVariant)>
      variantBySourceAndIdentity,
  required Map<(String, WireId), WireIdRef> parameterOwnerByRef,
  required Map<(String, WireId, String), WireId> parameterByVariantAndLabel,
}) {
  final path = 'widget "${widget.name}".decomposes[$recipeIndex]';
  final linkedRecipe = _linkDecompositionRefs(
    widget: widget,
    recipe: recipe,
    recipeIndex: recipeIndex,
    index: index,
    structuredIdBySourceType: structuredIdBySourceType,
    fieldIdByOwnerAndName: fieldIdByOwnerAndName,
    variantBySourceAndIdentity: variantBySourceAndIdentity,
    parameterByVariantAndLabel: parameterByVariantAndLabel,
    path: path,
  );
  final structured = structuredByRef[(
    linkedRecipe.structuredRef.library,
    linkedRecipe.structuredRef.wireId,
  )];
  if (structured == null) {
    throw CrossRefLinkException(
      '$path.structuredRef does not resolve: ${linkedRecipe.structuredRef}',
    );
  }

  final construction = linkedRecipe.construction;
  if (construction != null) {
    _requireVariant(
      construction,
      variantByRef,
      expectedResultStructuredRef: linkedRecipe.structuredRef,
      path: '$path.construction',
    );
  }

  final fieldsById = {
    for (final field in structured.fields) field.wireId: field,
  };
  final propertiesById = {
    for (final property in widget.properties) property.wireId: property,
  };
  for (var i = 0; i < linkedRecipe.fieldMappings.length; i++) {
    final mapping = linkedRecipe.fieldMappings[i];
    final mappingPath = '$path.fieldMappings[$i]';
    final field = fieldsById[mapping.fieldRef];
    if (field == null) {
      throw CrossRefLinkException(
        '$mappingPath.fieldRef does not resolve: ${mapping.fieldRef}',
      );
    }
    final property = propertiesById[mapping.propertyRef];
    if (property == null) {
      throw CrossRefLinkException(
        '$mappingPath.propertyRef does not resolve: ${mapping.propertyRef}',
      );
    }
    _validateMappingShape(mapping, field, property, mappingPath);
    _validateTransformRefs(
      mapping.transform,
      variantByRef,
      parameterOwnerByRef,
      '$mappingPath.transform',
    );
  }
  final constructionVariantEntry = construction == null
      ? null
      : variantByRef[(
          construction.variantRef.library,
          construction.variantRef.wireId,
        )];
  final constructionVariant = constructionVariantEntry?.$2;
  final constructionParameters = constructionVariant == null
      ? const <FactoryParameter>[]
      : factoryVariantFields(constructionVariant).parameters;
  final parametersById = {
    for (final parameter in constructionParameters) parameter.wireId: parameter,
  };
  for (var i = 0; i < linkedRecipe.parameterMappings.length; i++) {
    final mapping = linkedRecipe.parameterMappings[i];
    final mappingPath = '$path.parameterMappings[$i]';
    final parameter = parametersById[mapping.parameterRef];
    if (parameter == null) {
      throw CrossRefLinkException(
        '$mappingPath.parameterRef does not resolve on construction variant: '
        '${mapping.parameterRef}',
      );
    }
    final property = propertiesById[mapping.propertyRef];
    if (property == null) {
      throw CrossRefLinkException(
        '$mappingPath.propertyRef does not resolve: ${mapping.propertyRef}',
      );
    }
    _validateParameterMappingShape(mapping, parameter, property, mappingPath);
    _validateTransformRefs(
      mapping.transform,
      variantByRef,
      parameterOwnerByRef,
      '$mappingPath.transform',
    );
  }

  return linkedRecipe;
}

StructuredEntry _linkStructured(
  StructuredEntry structured,
  CrossRefResolutionIndex index,
  Map<String, WireId> structuredIdBySourceType,
  Map<String, WireId> unionIdBySourceKey,
  Map<(String, String), WireId> fieldIdByOwnerAndName,
) {
  return StructuredEntry(
    wireId: structured.wireId,
    name: structured.name,
    library: structured.library,
    description: structured.description,
    sourceType: structured.sourceType,
    fields: [
      for (final field in structured.fields)
        _linkStructuredField(
          ownerSourceType: structured.sourceType,
          field: field,
          index: index,
          structuredIdBySourceType: structuredIdBySourceType,
          unionIdBySourceKey: unionIdBySourceKey,
        ),
    ],
    variants: [
      for (final variant in structured.variants)
        _linkVariant(
          ownerSourceType: structured.sourceType,
          variant: variant,
          index: index,
          structuredIdBySourceType: structuredIdBySourceType,
          unionIdBySourceKey: unionIdBySourceKey,
          fieldIdByOwnerAndName: fieldIdByOwnerAndName,
        ),
    ],
    stability: structured.stability,
    deprecated: structured.deprecated,
  );
}

StructuredField _linkStructuredField({
  required String ownerSourceType,
  required StructuredField field,
  required CrossRefResolutionIndex index,
  required Map<String, WireId> structuredIdBySourceType,
  required Map<String, WireId> unionIdBySourceKey,
}) {
  final structuredRef = field.structuredRef;
  final linkedStructuredRef =
      structuredRef != null && structuredRef.wireId.isUnallocated
          ? _linkStructuredRef(
              ownerSourceType: ownerSourceType,
              fieldName: field.name,
              ref: structuredRef,
              index: index,
              structuredIdBySourceType: structuredIdBySourceType,
            )
          : structuredRef;
  final unionRef = field.unionRef;
  final linkedUnionRef = unionRef != null && unionRef.wireId.isUnallocated
      ? _linkUnionRef(
          ownerSourceType: ownerSourceType,
          fieldName: field.name,
          ref: unionRef,
          index: index,
          unionIdBySourceKey: unionIdBySourceKey,
        )
      : unionRef;
  final linkedValueShape = _linkStructuredFieldValueShape(
    ownerSourceType: ownerSourceType,
    fieldName: field.name,
    shape: field.valueShape,
    index: index,
    structuredIdBySourceType: structuredIdBySourceType,
    unionIdBySourceKey: unionIdBySourceKey,
  );

  return StructuredField(
    wireId: field.wireId,
    name: field.name,
    type: field.type,
    description: field.description,
    required: field.required,
    defaultSource: field.defaultSource,
    category: field.category,
    priority: field.priority,
    deprecated: field.deprecated,
    structuredRef: linkedStructuredRef,
    unionRef: linkedUnionRef,
    valueShape: linkedValueShape,
  );
}

CatalogValueShape? _linkStructuredFieldValueShape({
  required String ownerSourceType,
  required String fieldName,
  required CatalogValueShape? shape,
  required CrossRefResolutionIndex index,
  required Map<String, WireId> structuredIdBySourceType,
  required Map<String, WireId> unionIdBySourceKey,
}) {
  if (shape == null) return null;
  switch (shape) {
    case ScalarShape():
    case EnumShape():
      return shape;
    case StructuredShape(:final structuredRef):
      final linkedStructuredRef = structuredRef.wireId.isUnallocated
          ? _linkStructuredRef(
              ownerSourceType: ownerSourceType,
              fieldName: fieldName,
              ref: structuredRef,
              index: index,
              structuredIdBySourceType: structuredIdBySourceType,
            )
          : structuredRef;
      return StructuredShape(
        propertyType: shape.propertyType,
        structuredRef: linkedStructuredRef,
        wireCodec: shape.wireCodec,
      );
    case UnionShape(:final unionRef):
      final linkedUnionRef = unionRef.wireId.isUnallocated
          ? _linkUnionRef(
              ownerSourceType: ownerSourceType,
              fieldName: fieldName,
              ref: unionRef,
              index: index,
              unionIdBySourceKey: unionIdBySourceKey,
            )
          : unionRef;
      return UnionShape(
        propertyType: shape.propertyType,
        unionRef: linkedUnionRef,
        wireCodec: shape.wireCodec,
      );
    case ListShape(:final itemShape):
      final linkedItemShape = _linkStructuredFieldValueShape(
        ownerSourceType: ownerSourceType,
        fieldName: fieldName,
        shape: itemShape,
        index: index,
        structuredIdBySourceType: structuredIdBySourceType,
        unionIdBySourceKey: unionIdBySourceKey,
      )!;
      return ListShape(
        propertyType: shape.propertyType,
        itemShape: linkedItemShape,
        wireCodec: shape.wireCodec,
      );
  }
}

WireIdRef _linkStructuredRef({
  required String ownerSourceType,
  required String fieldName,
  required WireIdRef ref,
  required CrossRefResolutionIndex index,
  required Map<String, WireId> structuredIdBySourceType,
}) {
  final key = (ownerSourceType, fieldName);
  final targetFqn = index.structuredRefFqnByField[key];
  if (targetFqn == null) {
    throw CrossRefLinkException(
      'CrossRefResolutionIndex.structuredRefFqnByField has no entry for '
      "'$ownerSourceType.$fieldName'",
    );
  }
  final wireId = structuredIdBySourceType[targetFqn];
  if (wireId == null) {
    throw CrossRefLinkException(
      "structuredIdBySourceType has no entry for '$targetFqn' referenced by "
      "'$ownerSourceType.$fieldName'",
    );
  }
  return WireIdRef(library: ref.library, wireId: wireId);
}

WireIdRef _linkUnionRef({
  required String ownerSourceType,
  required String fieldName,
  required WireIdRef ref,
  required CrossRefResolutionIndex index,
  required Map<String, WireId> unionIdBySourceKey,
}) {
  final key = (ownerSourceType, fieldName);
  final targetKey = index.unionSourceKeyByField[key];
  if (targetKey == null) {
    throw CrossRefLinkException(
      'CrossRefResolutionIndex.unionSourceKeyByField has no entry for '
      "'$ownerSourceType.$fieldName'",
    );
  }
  final wireId = unionIdBySourceKey[targetKey];
  if (wireId == null) {
    throw CrossRefLinkException(
      "unionIdBySourceKey has no entry for '$targetKey' referenced by "
      "'$ownerSourceType.$fieldName'",
    );
  }
  return WireIdRef(library: ref.library, wireId: wireId);
}

FactoryVariant _linkVariant({
  required String ownerSourceType,
  required FactoryVariant variant,
  required CrossRefResolutionIndex index,
  required Map<String, WireId> structuredIdBySourceType,
  required Map<String, WireId> unionIdBySourceKey,
  required Map<(String, String), WireId> fieldIdByOwnerAndName,
}) {
  final fields = factoryVariantFields(variant);
  final linkedMappings = <String, ArgMapping>{};
  for (final entry in fields.argMappings.entries) {
    final mapping = entry.value;
    if (!mapping.targetFields.any((id) => id.isUnallocated)) {
      linkedMappings[entry.key] = mapping;
      continue;
    }
    final variantId = variantIdentity(variant);
    final names =
        index.argTargetFieldNames[(ownerSourceType, variantId, entry.key)];
    if (names == null) {
      throw CrossRefLinkException(
        'CrossRefResolutionIndex.argTargetFieldNames has no entry for '
        "'$ownerSourceType.$variantId.${entry.key}'",
      );
    }
    if (names.length != mapping.targetFields.length) {
      throw CrossRefLinkException(
        'argTargetFieldNames cardinality mismatch for '
        "'$ownerSourceType.$variantId.${entry.key}': "
        'index=${names.length}, mapping=${mapping.targetFields.length}',
      );
    }
    linkedMappings[entry.key] = ArgMapping(
      targetFields: [
        for (final name in names)
          _requireFieldId(
            ownerSourceType: ownerSourceType,
            argName: entry.key,
            variantId: variantId,
            fieldName: name,
            fieldIdByOwnerAndName: fieldIdByOwnerAndName,
          ),
      ],
    );
  }

  final linkedParameters = [
    for (final parameter in fields.parameters)
      _linkFactoryParameter(
        ownerSourceType: ownerSourceType,
        parameter: parameter,
        index: index,
        structuredIdBySourceType: structuredIdBySourceType,
        unionIdBySourceKey: unionIdBySourceKey,
      ),
  ];

  // Rebuild the same sealed subtype with the linked argument mappings +
  // parameters. The accessor kinds carry neither (both linked collections are
  // empty for them by construction), so their links are no-ops.
  switch (variant) {
    case ConstructorVariant(:final namedConstructor):
      return ConstructorVariant(
        wireId: variant.wireId,
        namedConstructor: namedConstructor,
        argMappings: Map.unmodifiable(linkedMappings),
        parameters: List.unmodifiable(linkedParameters),
        description: variant.description,
        deprecated: variant.deprecated,
      );
    case StaticMethodVariant(:final staticAccessor):
      return StaticMethodVariant(
        wireId: variant.wireId,
        staticAccessor: staticAccessor,
        argMappings: Map.unmodifiable(linkedMappings),
        parameters: List.unmodifiable(linkedParameters),
        description: variant.description,
        deprecated: variant.deprecated,
      );
    case StaticGetterVariant(:final staticAccessor):
      return StaticGetterVariant(
        wireId: variant.wireId,
        staticAccessor: staticAccessor,
        description: variant.description,
        deprecated: variant.deprecated,
      );
    case ConstValueVariant(:final staticAccessor):
      return ConstValueVariant(
        wireId: variant.wireId,
        staticAccessor: staticAccessor,
        description: variant.description,
        deprecated: variant.deprecated,
      );
  }
}

FactoryParameter _linkFactoryParameter({
  required String ownerSourceType,
  required FactoryParameter parameter,
  required CrossRefResolutionIndex index,
  required Map<String, WireId> structuredIdBySourceType,
  required Map<String, WireId> unionIdBySourceKey,
}) {
  final linkedValueShape = _linkStructuredFieldValueShape(
    ownerSourceType: ownerSourceType,
    fieldName: _parameterLabel(parameter),
    shape: parameter.valueShape,
    index: index,
    structuredIdBySourceType: structuredIdBySourceType,
    unionIdBySourceKey: unionIdBySourceKey,
  );

  return FactoryParameter(
    wireId: parameter.wireId,
    name: parameter.name,
    position: parameter.position,
    kind: parameter.kind,
    required: parameter.required,
    nullable: parameter.nullable,
    defaultPolicy: parameter.defaultPolicy,
    defaultValue: parameter.defaultValue,
    valueShape: linkedValueShape!,
  );
}

void _validateMappingShape(
  DecompositionFieldMapping mapping,
  StructuredField field,
  PropertyEntry property,
  String path,
) {
  if (mapping.transform is! IdentityTransform) {
    return;
  }
  final fieldShape = field.valueShape;
  final propertyShape = property.valueShape;
  if (fieldShape == null || propertyShape == null) {
    throw CrossRefLinkException(
      '$path identity transform requires valueShape on both endpoints: '
      'field=${field.name}, property=${property.name}',
    );
  }
  if (!_valueShapesCompatibleForIdentity(fieldShape, propertyShape)) {
    throw CrossRefLinkException(
      '$path identity transform has incompatible valueShape: '
      'field=${field.name} ${_shapeSummary(fieldShape)}, '
      'property=${property.name} ${_shapeSummary(propertyShape)}',
    );
  }
}

void _validateParameterMappingShape(
  DecompositionParameterMapping mapping,
  FactoryParameter parameter,
  PropertyEntry property,
  String path,
) {
  if (mapping.transform is! IdentityTransform) {
    return;
  }
  final parameterShape = parameter.valueShape;
  final propertyShape = property.valueShape;
  if (propertyShape == null) {
    throw CrossRefLinkException(
      '$path identity transform requires valueShape on property '
      '${property.name}',
    );
  }
  if (!_valueShapesCompatibleForIdentity(parameterShape, propertyShape)) {
    throw CrossRefLinkException(
      '$path identity transform has incompatible valueShape: '
      'parameter=${parameter.name ?? parameter.position}, '
      '${_shapeSummary(parameterShape)}, property=${property.name} '
      '${_shapeSummary(propertyShape)}',
    );
  }
}

(WireIdRef, FactoryVariant) _requireVariant(
  FactoryInvocation invocation,
  Map<(String, WireId), (WireIdRef, FactoryVariant)> variantByRef, {
  required WireIdRef expectedResultStructuredRef,
  required String path,
}) {
  final variantRef = invocation.variantRef;
  final entry = variantByRef[(variantRef.library, variantRef.wireId)];
  if (entry == null) {
    throw CrossRefLinkException(
      '$path.variantRef does not resolve: $variantRef',
    );
  }
  if (entry.$1 != expectedResultStructuredRef) {
    throw CrossRefLinkException(
      '$path.variantRef $variantRef belongs to ${entry.$1}, not '
      '$expectedResultStructuredRef',
    );
  }
  return entry;
}

void _validateTransformRefs(
  DecompositionValueTransform transform,
  Map<(String, WireId), (WireIdRef, FactoryVariant)> variantByRef,
  Map<(String, WireId), WireIdRef> parameterOwnerByRef,
  String path,
) {
  switch (transform) {
    case IdentityTransform():
    case CoerceScalarTransform():
      return;
    case ProjectListTransform(:final itemTransform):
      _validateTransformRefs(
        itemTransform,
        variantByRef,
        parameterOwnerByRef,
        '$path.itemTransform',
      );
    case ConstructVariantTransform(
        :final resultStructuredRef,
        :final invocation,
        :final argumentBindings,
      ):
      _requireVariant(
        invocation,
        variantByRef,
        expectedResultStructuredRef: resultStructuredRef,
        path: '$path.invocation',
      );
      for (var i = 0; i < argumentBindings.length; i++) {
        final binding = argumentBindings[i];
        final bindingPath = '$path.argumentBindings[$i]';
        final parameterRef = WireIdRef(
          library: invocation.variantRef.library,
          wireId: binding.parameterRef,
        );
        final owner = parameterOwnerByRef[(
          parameterRef.library,
          parameterRef.wireId,
        )];
        if (owner == null) {
          throw CrossRefLinkException(
            '$bindingPath.parameterRef does not resolve: '
            '${parameterRef.wireId}',
          );
        }
        if (owner != invocation.variantRef) {
          throw CrossRefLinkException(
            '$bindingPath.parameterRef ${parameterRef.wireId} is owned by '
            '$owner, not ${invocation.variantRef}',
          );
        }
        if (binding is NestedTransformArgumentBinding) {
          _validateTransformRefs(
            binding.nestedTransform,
            variantByRef,
            parameterOwnerByRef,
            '$bindingPath.nestedTransform',
          );
        }
      }
  }
}

bool _valueShapesCompatibleForIdentity(
  CatalogValueShape left,
  CatalogValueShape right,
) {
  if (left.wireCodec != right.wireCodec) {
    return false;
  }
  switch (left) {
    case ScalarShape():
      if (right is! ScalarShape) return false;
      return left.propertyType == right.propertyType ||
          (left.dartTypeRef != null && left.dartTypeRef == right.dartTypeRef);
    case ListShape():
      if (right is! ListShape) return false;
      if (left.propertyType != right.propertyType) return false;
      return _valueShapesCompatibleForIdentity(
        left.itemShape,
        right.itemShape,
      );
    case EnumShape():
      if (right is! EnumShape) return false;
      if (left.propertyType != right.propertyType) return false;
      return left.enumRef == right.enumRef;
    case StructuredShape():
      if (right is! StructuredShape) return false;
      if (left.propertyType != right.propertyType) return false;
      return left.structuredRef == right.structuredRef;
    case UnionShape():
      if (right is! UnionShape) return false;
      if (left.propertyType != right.propertyType) return false;
      return left.unionRef == right.unionRef;
  }
}

String _shapeSummary(CatalogValueShape shape) {
  final kindName = switch (shape) {
    ScalarShape() => 'scalar',
    EnumShape() => 'enumValue',
    StructuredShape() => 'structured',
    UnionShape() => 'union',
    ListShape() => 'list',
  };
  final detail = switch (shape) {
    ScalarShape(:final dartTypeRef) =>
      dartTypeRef == null ? '' : '/dart:$dartTypeRef',
    EnumShape(:final enumRef) => '/enum:$enumRef',
    StructuredShape(:final structuredRef) => '/structured:$structuredRef',
    UnionShape(:final unionRef) => '/union:$unionRef',
    ListShape() => '',
  };
  return '($kindName/${shape.propertyType.name}'
      '$detail'
      '${shape.wireCodec == null ? '' : '/codec:${shape.wireCodec!.name}'})';
}

String _parameterLabel(FactoryParameter parameter) {
  final name = parameter.name;
  if (name != null && name.isNotEmpty) return name;
  final position = parameter.position;
  if (position != null) return position.toString();
  return 'parameter';
}

WireId _requireFieldId({
  required String ownerSourceType,
  required String argName,
  required String variantId,
  required String fieldName,
  required Map<(String, String), WireId> fieldIdByOwnerAndName,
}) {
  final wireId = fieldIdByOwnerAndName[(ownerSourceType, fieldName)];
  if (wireId == null) {
    throw CrossRefLinkException(
      "fieldIdByOwnerAndName has no entry for '$ownerSourceType.$fieldName' "
      "referenced by arg '$ownerSourceType.$variantId.$argName'",
    );
  }
  return wireId;
}
