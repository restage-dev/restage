import 'package:restage_codegen/src/emit_utils.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Emits a `user_catalog.g.dart` source string declaring
/// `final Catalog kUserCatalog`. Output is run through `dart format`
/// so regenerated source passes `dart format --set-exit-if-changed`.
String emitUserCatalogDart(Catalog catalog) {
  // `final` (not `const`) on `kUserCatalog` because `WidgetLibrary` overrides
  // `==`/`hashCode`, which Dart rejects for keys of a const map.
  final buf = StringBuffer();
  writeGeneratedHeader(buf);
  buf
    ..writeln()
    ..writeln("import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';")
    ..writeln()
    ..writeln('final Catalog kUserCatalog = Catalog(')
    ..writeln('  schemaVersion: ${catalog.schemaVersion},')
    ..writeln('  generatedAt: ${_escapeDart(catalog.generatedAt)},')
    ..writeln('  libraries: {');
  for (final entry in _sortedLibraries(catalog.libraries).entries) {
    buf.writeln(
      '    ${_libraryFieldRef(entry.key)}: '
      '${_libraryInfoLiteral(entry.value)},',
    );
  }
  buf
    ..writeln('  },')
    ..writeln('  widgets: [');
  for (final w in catalog.widgets) {
    _writeWidgetEntry(buf, w, indent: '    ');
  }
  buf.writeln('  ],');
  if (catalog.structuredTypes.isNotEmpty) {
    buf.writeln('  structuredTypes: [');
    for (final entry in catalog.structuredTypes) {
      _writeStructuredEntry(buf, entry, indent: '    ');
    }
    buf.writeln('  ],');
  }
  if (catalog.unions.isNotEmpty) {
    buf.writeln('  unions: [');
    for (final entry in catalog.unions) {
      _writeUnionEntry(buf, entry, indent: '    ');
    }
    buf.writeln('  ],');
  }
  if (catalog.designTokens.isNotEmpty) {
    buf.writeln('  designTokens: [');
    for (final entry in catalog.designTokens) {
      _writeDesignTokenEntry(buf, entry, indent: '    ');
    }
    buf.writeln('  ],');
  }
  if (catalog.flutterVersion != null) {
    buf.writeln(
      '  flutterVersion: ${_escapeDart(catalog.flutterVersion!)},',
    );
  }
  if (catalog.compatRules != null) {
    buf.writeln('  compatRules: [');
    for (final rule in catalog.compatRules!) {
      _writeCompatRule(buf, rule, indent: '    ');
    }
    buf.writeln('  ],');
  }
  buf.writeln(');');
  return formatGeneratedDart(buf.toString());
}

/// Builds the catalog shape supported by the customer annotation pipeline.
///
/// The current annotation walker produces widget/property metadata only. If a
/// future caller hands this builder path native decompose graph references,
/// fail here rather than emitting a catalog whose graph sections are silently
/// empty.
Catalog userCatalogFromWidgets(List<WidgetEntry> widgets) {
  _rejectUnsupportedWidgetOnlyGraph(widgets);
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: _generatedAt,
    libraries: _aggregateLibraryInfo(widgets),
    widgets: widgets,
  );
}

/// `generatedAt` is intentionally fixed (not a real timestamp) so emitter
/// output is byte-deterministic across runs — emitting wall-clock time
/// would dirty source control on every build.
const String _generatedAt = '1970-01-01T00:00:00Z';

Map<WidgetLibrary, LibraryInfo> _aggregateLibraryInfo(
  List<WidgetEntry> widgets,
) {
  // One envelope entry per distinct contributing library. Per-kind counts are
  // computed off the catalog's entry lists, not stored here.
  // `version` is a deterministic placeholder until builder configuration
  // or consuming-package metadata supplies customer library versions.
  return {
    for (final library in {for (final w in widgets) w.library})
      library: const LibraryInfo(version: '0.0.0'),
  };
}

Map<WidgetLibrary, LibraryInfo> _sortedLibraries(
  Map<WidgetLibrary, LibraryInfo> libraries,
) {
  final entries = libraries.entries.toList()
    ..sort((a, b) => a.key.namespace.compareTo(b.key.namespace));
  return {for (final entry in entries) entry.key: entry.value};
}

void _rejectUnsupportedWidgetOnlyGraph(List<WidgetEntry> widgets) {
  for (final widget in widgets) {
    if (widget.decomposes.isNotEmpty) {
      throw UnsupportedError(
        'Customer catalog builder for ${widget.library.namespace}#'
        '${widget.name} cannot preserve a native decompose graph because the '
        'customer annotation pipeline cannot preserve structuredTypes/unions. '
        'Pass a full Catalog directly to emitUserCatalogDart instead.',
      );
    }
    for (final property in widget.properties) {
      if (property.structuredRef != null ||
          _valueShapeNeedsGraph(property.valueShape)) {
        throw UnsupportedError(
          'Customer catalog builder for ${widget.library.namespace}#'
          '${widget.name}.${property.name} cannot preserve structured/union '
          'graph references because the customer annotation pipeline cannot '
          'preserve structuredTypes/unions. Pass a full Catalog directly to '
          'emitUserCatalogDart instead.',
        );
      }
      if (property.defaultSource is TokenRefDefault) {
        throw UnsupportedError(
          'Customer catalog builder for ${widget.library.namespace}#'
          '${widget.name}.${property.name} cannot preserve a design-token '
          'default because the customer annotation pipeline cannot preserve '
          'designTokens. Pass a full Catalog directly to emitUserCatalogDart '
          'instead.',
        );
      }
    }
  }
}

bool _valueShapeNeedsGraph(CatalogValueShape? shape) {
  if (shape == null) return false;
  return switch (shape) {
    StructuredShape() || UnionShape() => true,
    ListShape(:final itemShape) => _valueShapeNeedsGraph(itemShape),
    ScalarShape() || EnumShape() => false,
  };
}

void _writeWidgetEntry(
  StringBuffer buf,
  WidgetEntry w, {
  required String indent,
}) {
  buf
    ..writeln('${indent}WidgetEntry(')
    ..writeln('$indent  wireId: ${_wireIdLiteral(w.wireId)},')
    ..writeln('$indent  name: ${_escapeDart(w.name)},')
    ..writeln('$indent  library: ${_libraryFieldRef(w.library)},')
    ..writeln('$indent  category: WidgetCategory.${w.category.name},')
    ..writeln('$indent  description: ${_escapeDart(w.description)},')
    ..writeln('$indent  flutterType: ${_escapeDart(w.flutterType)},')
    ..writeln('$indent  childrenSlot: ChildrenSlot.${w.childrenSlot.name},')
    ..writeln(
      '$indent  fires: ['
      '${w.fires.map((e) => 'WidgetEventName.${e.name}').join(', ')}],',
    )
    ..writeln('$indent  properties: [');
  for (final p in w.properties) {
    _writePropertyEntry(buf, p, indent: '$indent    ');
  }
  buf.writeln('$indent  ],');
  if (w.decomposes.isNotEmpty) {
    buf.writeln('$indent  decomposes: [');
    for (final recipe in w.decomposes) {
      _writeDecomposes(buf, recipe, indent: '$indent    ');
    }
    buf.writeln('$indent  ],');
  }
  if (w.sinceVersion != kBaselineCatalogVersion) {
    buf.writeln('$indent  sinceVersion: ${w.sinceVersion},');
  }
  if (w.deprecatedSince != null) {
    buf.writeln(
      '$indent  deprecatedSince: ${_escapeDart(w.deprecatedSince!)},',
    );
  }
  if (w.stability != Stability.volatile) {
    buf.writeln('$indent  stability: Stability.${w.stability.name},');
  }
  if (w.deprecated != null) {
    buf.writeln('$indent  deprecated: ${_deprecationLiteral(w.deprecated!)},');
  }
  buf.writeln('$indent),');
}

void _writePropertyEntry(
  StringBuffer buf,
  PropertyEntry p, {
  required String indent,
}) {
  buf
    ..writeln('${indent}PropertyEntry(')
    ..writeln('$indent  wireId: ${_wireIdLiteral(p.wireId)},')
    ..writeln('$indent  name: ${_escapeDart(p.name)},')
    ..writeln('$indent  type: PropertyType.${p.type.name},')
    ..writeln('$indent  description: ${_escapeDart(p.description)},');
  if (p.required) buf.writeln('$indent  required: true,');
  if (p.defaultBrandToken != null) {
    buf.writeln(
      '$indent  defaultBrandToken: ${_escapeDart(p.defaultBrandToken!)},',
    );
  }
  if (p.synthetic != null) {
    buf.writeln('$indent  synthetic: ${_escapeDart(p.synthetic!)},');
  }
  if (p.positional) buf.writeln('$indent  positional: true,');
  if (p.enumType != null) {
    buf.writeln('$indent  enumType: ${_escapeDart(p.enumType!)},');
  }
  if (p.widgetType != null) {
    buf.writeln('$indent  widgetType: ${_escapeDart(p.widgetType!)},');
  }
  if (p.callbackSignature != null) {
    buf.writeln(
      '$indent  callbackSignature: ${_escapeDart(p.callbackSignature!)},',
    );
  }
  if (p.firesAs != null) {
    buf.writeln('$indent  firesAs: ${_escapeDart(p.firesAs!)},');
  }
  if (p.defaultSource != null) {
    buf.writeln(
      '$indent  defaultSource: ${_defaultSourceLiteral(p.defaultSource!)},',
    );
  }
  if (p.mutuallyExclusiveWith != null) {
    buf.writeln(
      '$indent  mutuallyExclusiveWith: '
      '${_wireIdListLiteral(p.mutuallyExclusiveWith!)},',
    );
  }
  if (p.requiresAncestor != null) {
    buf.writeln(
      '$indent  requiresAncestor: ${_escapeDart(p.requiresAncestor!)},',
    );
  }
  if (p.category != null) {
    buf.writeln('$indent  category: PropertyCategory.${p.category!.name},');
  }
  if (p.priority != null) {
    buf.writeln('$indent  priority: PropertyPriority.${p.priority!.name},');
  }
  if (p.validationRule != null) {
    buf.writeln(
      '$indent  validationRule: ${_validationExprLiteral(p.validationRule!)},',
    );
  }
  if (p.deprecated != null) {
    buf.writeln('$indent  deprecated: ${_deprecationLiteral(p.deprecated!)},');
  }
  if (p.structuredRef != null) {
    buf.writeln(
      '$indent  structuredRef: ${_wireIdRefLiteral(p.structuredRef!)},',
    );
  }
  if (p.valueShape != null) {
    buf.writeln('$indent  valueShape: ${_valueShapeLiteral(p.valueShape!)},');
  }
  buf.writeln('$indent),');
}

void _writeDecomposes(
  StringBuffer buf,
  DecompositionRecipe recipe, {
  required String indent,
}) {
  buf
    ..writeln('${indent}DecompositionRecipe(')
    ..writeln(
      '$indent  structuredRef: ${_wireIdRefLiteral(recipe.structuredRef)},',
    )
    ..writeln(
      '$indent  flatProperties: ${_wireIdMapLiteral(recipe.flatProperties)},',
    );
  if (recipe.targetArg != null) {
    buf.writeln('$indent  targetArg: ${_escapeDart(recipe.targetArg!)},');
  }
  if (recipe.construction != null) {
    buf.writeln(
      '$indent  construction: '
      '${_factoryInvocationLiteral(recipe.construction!)},',
    );
  }
  if (recipe.fieldMappings.isNotEmpty) {
    buf.writeln('$indent  fieldMappings: [');
    for (final mapping in recipe.fieldMappings) {
      _writeFieldMapping(buf, mapping, indent: '$indent    ');
    }
    buf.writeln('$indent  ],');
  }
  if (recipe.parameterMappings.isNotEmpty) {
    buf.writeln('$indent  parameterMappings: [');
    for (final mapping in recipe.parameterMappings) {
      _writeParameterMapping(buf, mapping, indent: '$indent    ');
    }
    buf.writeln('$indent  ],');
  }
  if (recipe.discriminator != null) {
    buf.writeln(
      '$indent  discriminator: '
      '${_discriminatorSpecLiteral(recipe.discriminator!)},',
    );
  }
  buf.writeln('$indent),');
}

void _writeStructuredEntry(
  StringBuffer buf,
  StructuredEntry entry, {
  required String indent,
}) {
  buf
    ..writeln('${indent}StructuredEntry(')
    ..writeln('$indent  wireId: ${_wireIdLiteral(entry.wireId)},')
    ..writeln('$indent  name: ${_escapeDart(entry.name)},')
    ..writeln('$indent  library: ${_libraryFieldRef(entry.library)},')
    ..writeln('$indent  description: ${_escapeDart(entry.description)},')
    ..writeln('$indent  sourceType: ${_escapeDart(entry.sourceType)},')
    ..writeln('$indent  fields: [');
  for (final field in entry.fields) {
    _writeStructuredField(buf, field, indent: '$indent    ');
  }
  buf
    ..writeln('$indent  ],')
    ..writeln('$indent  variants: [');
  for (final variant in entry.variants) {
    _writeFactoryVariant(buf, variant, indent: '$indent    ');
  }
  buf.writeln('$indent  ],');
  if (entry.stability != Stability.volatile) {
    buf.writeln('$indent  stability: Stability.${entry.stability.name},');
  }
  if (entry.deprecated != null) {
    buf.writeln(
      '$indent  deprecated: ${_deprecationLiteral(entry.deprecated!)},',
    );
  }
  buf.writeln('$indent),');
}

void _writeStructuredField(
  StringBuffer buf,
  StructuredField field, {
  required String indent,
}) {
  buf
    ..writeln('${indent}StructuredField(')
    ..writeln('$indent  wireId: ${_wireIdLiteral(field.wireId)},')
    ..writeln('$indent  name: ${_escapeDart(field.name)},')
    ..writeln('$indent  type: PropertyType.${field.type.name},')
    ..writeln('$indent  description: ${_escapeDart(field.description)},');
  if (field.required) buf.writeln('$indent  required: true,');
  if (field.defaultSource != null) {
    buf.writeln(
      '$indent  defaultSource: ${_defaultSourceLiteral(field.defaultSource!)},',
    );
  }
  if (field.category != null) {
    buf.writeln('$indent  category: PropertyCategory.${field.category!.name},');
  }
  if (field.priority != null) {
    buf.writeln('$indent  priority: PropertyPriority.${field.priority!.name},');
  }
  if (field.deprecated != null) {
    buf.writeln(
      '$indent  deprecated: ${_deprecationLiteral(field.deprecated!)},',
    );
  }
  if (field.structuredRef != null) {
    buf.writeln(
      '$indent  structuredRef: ${_wireIdRefLiteral(field.structuredRef!)},',
    );
  }
  if (field.unionRef != null) {
    buf.writeln('$indent  unionRef: ${_wireIdRefLiteral(field.unionRef!)},');
  }
  if (field.valueShape != null) {
    buf.writeln(
      '$indent  valueShape: ${_valueShapeLiteral(field.valueShape!)},',
    );
  }
  buf.writeln('$indent),');
}

void _writeFactoryVariant(
  StringBuffer buf,
  FactoryVariant variant, {
  required String indent,
}) {
  final typeName = switch (variant) {
    ConstructorVariant() => 'ConstructorVariant',
    StaticMethodVariant() => 'StaticMethodVariant',
    StaticGetterVariant() => 'StaticGetterVariant',
    ConstValueVariant() => 'ConstValueVariant',
  };
  buf
    ..writeln('$indent$typeName(')
    ..writeln('$indent  wireId: ${_wireIdLiteral(variant.wireId)},');
  switch (variant) {
    case ConstructorVariant(
        :final namedConstructor,
        :final argMappings,
        :final parameters,
      ):
      if (namedConstructor != null) {
        buf.writeln(
          '$indent  namedConstructor: ${_escapeDart(namedConstructor)},',
        );
      }
      _writeArgMappings(buf, argMappings, indent: indent);
      _writeVariantParameters(buf, parameters, indent: indent);
    case StaticMethodVariant(
        :final staticAccessor,
        :final argMappings,
        :final parameters,
      ):
      buf.writeln('$indent  staticAccessor: ${_escapeDart(staticAccessor)},');
      _writeArgMappings(buf, argMappings, indent: indent);
      _writeVariantParameters(buf, parameters, indent: indent);
    case StaticGetterVariant(:final staticAccessor):
      buf.writeln('$indent  staticAccessor: ${_escapeDart(staticAccessor)},');
    case ConstValueVariant(:final staticAccessor):
      buf.writeln('$indent  staticAccessor: ${_escapeDart(staticAccessor)},');
  }
  if (variant.description != null) {
    buf.writeln('$indent  description: ${_escapeDart(variant.description!)},');
  }
  if (variant.deprecated != null) {
    buf.writeln(
      '$indent  deprecated: ${_deprecationLiteral(variant.deprecated!)},',
    );
  }
  buf.writeln('$indent),');
}

void _writeArgMappings(
  StringBuffer buf,
  Map<String, ArgMapping> argMappings, {
  required String indent,
}) {
  if (argMappings.isEmpty) return;
  buf.writeln('$indent  argMappings: {');
  for (final entry in _sortedStringEntries(argMappings).entries) {
    final targetFields = _wireIdListLiteral(entry.value.targetFields);
    buf.writeln(
      '$indent    ${_escapeDart(entry.key)}: '
      'ArgMapping(targetFields: $targetFields),',
    );
  }
  buf.writeln('$indent  },');
}

void _writeVariantParameters(
  StringBuffer buf,
  List<FactoryParameter> parameters, {
  required String indent,
}) {
  if (parameters.isEmpty) return;
  buf.writeln('$indent  parameters: [');
  for (final parameter in parameters) {
    _writeFactoryParameter(buf, parameter, indent: '$indent    ');
  }
  buf.writeln('$indent  ],');
}

void _writeFactoryParameter(
  StringBuffer buf,
  FactoryParameter parameter, {
  required String indent,
}) {
  buf
    ..writeln('${indent}FactoryParameter(')
    ..writeln('$indent  wireId: ${_wireIdLiteral(parameter.wireId)},');
  if (parameter.name != null) {
    buf.writeln('$indent  name: ${_escapeDart(parameter.name!)},');
  }
  if (parameter.position != null) {
    buf.writeln('$indent  position: ${parameter.position},');
  }
  buf
    ..writeln('$indent  kind: FactoryParameterKind.${parameter.kind.name},')
    ..writeln('$indent  required: ${parameter.required},')
    ..writeln('$indent  nullable: ${parameter.nullable},')
    ..writeln(
      '$indent  defaultPolicy: '
      'FactoryParameterDefaultPolicy.${parameter.defaultPolicy.name},',
    );
  if (parameter.defaultValue != null) {
    buf.writeln(
      '$indent  defaultValue: '
      '${_parameterDefaultValueLiteral(parameter.defaultValue!)},',
    );
  }
  buf
    ..writeln(
      '$indent  valueShape: ${_valueShapeLiteral(parameter.valueShape)},',
    )
    ..writeln('$indent),');
}

void _writeFieldMapping(
  StringBuffer buf,
  DecompositionFieldMapping mapping, {
  required String indent,
}) {
  buf
    ..writeln('${indent}DecompositionFieldMapping(')
    ..writeln('$indent  fieldRef: ${_wireIdLiteral(mapping.fieldRef)},')
    ..writeln('$indent  propertyRef: ${_wireIdLiteral(mapping.propertyRef)},')
    ..writeln(
      '$indent  transform: ${_valueTransformLiteral(mapping.transform)},',
    )
    ..writeln('$indent),');
}

void _writeParameterMapping(
  StringBuffer buf,
  DecompositionParameterMapping mapping, {
  required String indent,
}) {
  buf
    ..writeln('${indent}DecompositionParameterMapping(')
    ..writeln('$indent  parameterRef: ${_wireIdLiteral(mapping.parameterRef)},')
    ..writeln('$indent  propertyRef: ${_wireIdLiteral(mapping.propertyRef)},')
    ..writeln(
      '$indent  transform: ${_valueTransformLiteral(mapping.transform)},',
    )
    ..writeln('$indent),');
}

void _writeUnionEntry(
  StringBuffer buf,
  UnionEntry entry, {
  required String indent,
}) {
  buf
    ..writeln('${indent}UnionEntry(')
    ..writeln('$indent  wireId: ${_wireIdLiteral(entry.wireId)},')
    ..writeln('$indent  name: ${_escapeDart(entry.name)},')
    ..writeln('$indent  library: ${_libraryFieldRef(entry.library)},')
    ..writeln('$indent  description: ${_escapeDart(entry.description)},')
    ..writeln('$indent  sourceType: ${_escapeDart(entry.sourceType)},')
    ..writeln(
      '$indent  memberSourceTypes: '
      '[${entry.memberSourceTypes.map(_escapeDart).join(', ')}],',
    )
    ..writeln(
      '$indent  discriminator: '
      '${_discriminatorSpecLiteral(entry.discriminator)},',
    )
    ..writeln('$indent  members: ${_wireIdRefListLiteral(entry.members)},');
  if (entry.stability != Stability.volatile) {
    buf.writeln('$indent  stability: Stability.${entry.stability.name},');
  }
  if (entry.deprecated != null) {
    buf.writeln(
      '$indent  deprecated: ${_deprecationLiteral(entry.deprecated!)},',
    );
  }
  buf.writeln('$indent),');
}

void _writeDesignTokenEntry(
  StringBuffer buf,
  DesignTokenEntry entry, {
  required String indent,
}) {
  buf
    ..writeln('${indent}DesignTokenEntry(')
    ..writeln('$indent  wireId: ${_wireIdLiteral(entry.wireId)},')
    ..writeln('$indent  name: ${_escapeDart(entry.name)},')
    ..writeln('$indent  library: ${_libraryFieldRef(entry.library)},')
    ..writeln('$indent  type: DesignTokenType.${entry.type.name},');
  if (entry.description != null) {
    buf.writeln('$indent  description: ${_escapeDart(entry.description!)},');
  }
  if (entry.resolver != null) {
    buf.writeln(
      '$indent  resolver: ${_themeBindingPathLiteral(entry.resolver!)},',
    );
  }
  if (entry.literalFallback != null) {
    buf.writeln(
      '$indent  literalFallback: ${_dartLiteral(entry.literalFallback)},',
    );
  }
  if (entry.stability != Stability.volatile) {
    buf.writeln('$indent  stability: Stability.${entry.stability.name},');
  }
  if (entry.deprecated != null) {
    buf.writeln(
      '$indent  deprecated: ${_deprecationLiteral(entry.deprecated!)},',
    );
  }
  buf.writeln('$indent),');
}

void _writeCompatRule(
  StringBuffer buf,
  CompatRule rule, {
  required String indent,
}) {
  buf
    ..writeln('${indent}CompatRule(')
    ..writeln('$indent  fromVersion: ${_escapeDart(rule.fromVersion)},')
    ..writeln('$indent  toVersion: ${_escapeDart(rule.toVersion)},')
    ..writeln('$indent  kind: CompatKind.${rule.kind.name},')
    ..writeln('$indent  affectedRef: ${_wireIdRefLiteral(rule.affectedRef)},');
  if (rule.successorRef != null) {
    buf.writeln(
      '$indent  successorRef: ${_wireIdRefLiteral(rule.successorRef!)},',
    );
  }
  if (rule.transitionId != null) {
    buf.writeln('$indent  transitionId: ${_escapeDart(rule.transitionId!)},');
  }
  if (rule.note != null) {
    buf.writeln('$indent  note: ${_escapeDart(rule.note!)},');
  }
  buf.writeln('$indent),');
}

/// Renders a Dart expression that resolves to [lib] when read in code that
/// imports `package:rfw_catalog_schema/rfw_catalog_schema.dart`. Built-in libraries
/// produce a static-field reference (`WidgetLibrary.core`); customer
/// libraries produce a const factory invocation
/// (`WidgetLibrary.custom('acme.design_system')`).
String _libraryFieldRef(WidgetLibrary lib) {
  switch (lib.namespace) {
    case 'restage.core':
      return 'WidgetLibrary.core';
    case 'restage.material':
      return 'WidgetLibrary.material';
    case 'restage.cupertino':
      return 'WidgetLibrary.cupertino';
    default:
      return 'WidgetLibrary.custom(${_escapeDart(lib.namespace)})';
  }
}

String _libraryInfoLiteral(LibraryInfo info) {
  final capabilityVersion = info.capabilityVersion;
  // Emitted only when declared (built-ins omit it) — keeps the literal
  // byte-stable for libraries with no capability version.
  final capability = capabilityVersion == null
      ? ''
      : ', capabilityVersion: $capabilityVersion';
  return 'const LibraryInfo(version: ${_escapeDart(info.version)}$capability)';
}

Map<String, T> _sortedStringEntries<T>(Map<String, T> map) {
  final entries = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  return {for (final entry in entries) entry.key: entry.value};
}

String _wireIdLiteral(WireId id) {
  if (id.isUnallocated) {
    switch (id.kind) {
      case WireIdKind.widget:
        return 'WireId.unallocatedWidget';
      case WireIdKind.property:
        return 'WireId.unallocatedProperty';
      case WireIdKind.structured:
        return 'WireId.unallocatedStructured';
      case WireIdKind.variant:
        return 'WireId.unallocatedVariant';
      case WireIdKind.union:
        return 'WireId.unallocatedUnion';
      case WireIdKind.designToken:
        return 'WireId.unallocatedDesignToken';
      case WireIdKind.parameter:
        return 'WireId.unallocatedParameter';
    }
  }
  return "WireId('${id.value}')";
}

String _wireIdRefLiteral(WireIdRef ref) {
  return 'WireIdRef(library: ${_escapeDart(ref.library)}, '
      'wireId: ${_wireIdLiteral(ref.wireId)})';
}

String _wireIdListLiteral(List<WireId> ids) {
  if (ids.isEmpty) return '<WireId>[]';
  return '[${ids.map(_wireIdLiteral).join(', ')}]';
}

String _wireIdRefListLiteral(List<WireIdRef> refs) {
  if (refs.isEmpty) return '<WireIdRef>[]';
  return '[${refs.map(_wireIdRefLiteral).join(', ')}]';
}

String _wireIdMapLiteral(Map<WireId, WireId> map) {
  if (map.isEmpty) return '<WireId, WireId>{}';
  final entries = map.entries.toList()
    ..sort((a, b) => a.key.value.compareTo(b.key.value));
  final pairs = entries.map(
    (entry) => '${_wireIdLiteral(entry.key)}: ${_wireIdLiteral(entry.value)}',
  );
  return '{${pairs.join(', ')}}';
}

String _defaultSourceLiteral(DefaultValueSource source) {
  return switch (source) {
    LiteralDefault(:final value) => 'LiteralDefault(${_dartLiteral(value)})',
    TokenRefDefault(:final token) =>
      'TokenRefDefault(${_wireIdRefLiteral(token)})',
    FlutterCtorDefault() => 'FlutterCtorDefault()',
    ThemeBindingDefault(:final path) =>
      'ThemeBindingDefault(${_themeBindingPathLiteral(path)})',
  };
}

String _valueShapeLiteral(CatalogValueShape shape) {
  final propertyType = 'propertyType: PropertyType.${shape.propertyType.name}';
  final wireCodec = shape.wireCodec != null
      ? 'wireCodec: CatalogWireCodec.${shape.wireCodec!.name}'
      : null;
  String build(String ctor, List<String?> extra) {
    final args = <String>[
      propertyType,
      ...extra.whereType<String>(),
      if (wireCodec != null) wireCodec,
    ];
    return '$ctor(${args.join(', ')})';
  }

  return switch (shape) {
    ScalarShape(:final dartTypeRef) => build('ScalarShape', [
        if (dartTypeRef != null)
          'dartTypeRef: ${_dartTypeRefLiteral(dartTypeRef)}',
      ]),
    EnumShape(:final enumRef) => build('EnumShape', [
        'enumRef: ${_dartTypeRefLiteral(enumRef)}',
      ]),
    StructuredShape(:final structuredRef) => build('StructuredShape', [
        'structuredRef: ${_wireIdRefLiteral(structuredRef)}',
      ]),
    UnionShape(:final unionRef) => build('UnionShape', [
        'unionRef: ${_wireIdRefLiteral(unionRef)}',
      ]),
    ListShape(:final itemShape) => build('ListShape', [
        'itemShape: ${_valueShapeLiteral(itemShape)}',
      ]),
  };
}

String _dartTypeRefLiteral(DartTypeRef ref) {
  return 'DartTypeRef(libraryUri: ${_escapeDart(ref.libraryUri)}, '
      'symbolName: ${_escapeDart(ref.symbolName)})';
}

String _parameterDefaultValueLiteral(FactoryParameterDefaultValue value) {
  switch (value) {
    case LiteralParameterDefault(:final value):
      return 'LiteralParameterDefault(${_dartLiteral(value)})';
    case StaticMemberParameterDefault(:final staticType, :final memberName):
      return 'StaticMemberParameterDefault('
          'staticType: ${_dartTypeRefLiteral(staticType)}, '
          'memberName: ${_escapeDart(memberName)})';
  }
}

String _factoryInvocationLiteral(FactoryInvocation invocation) {
  final args = <String>[
    'variantRef: ${_wireIdRefLiteral(invocation.variantRef)}',
    'receiver: ${_factoryReceiverLiteral(invocation.receiver)}',
    if (invocation.memberName != null)
      'memberName: ${_escapeDart(invocation.memberName!)}',
  ];
  return 'FactoryInvocation(${args.join(', ')})';
}

String _factoryReceiverLiteral(FactoryReceiver receiver) {
  return switch (receiver) {
    ResultStructuredTypeReceiver() => 'ResultStructuredTypeReceiver()',
    OwningWidgetTypeReceiver() => 'OwningWidgetTypeReceiver()',
    ExplicitDartTypeReceiver(:final dartTypeRef) =>
      'ExplicitDartTypeReceiver(${_dartTypeRefLiteral(dartTypeRef)})',
  };
}

String _valueTransformLiteral(DecompositionValueTransform transform) {
  return switch (transform) {
    IdentityTransform() => 'IdentityTransform()',
    ConstructVariantTransform(
      :final resultStructuredRef,
      :final invocation,
      :final argumentBindings,
    ) =>
      'ConstructVariantTransform('
          'resultStructuredRef: '
          '${_wireIdRefLiteral(resultStructuredRef)}, '
          'invocation: ${_factoryInvocationLiteral(invocation)}, '
          'argumentBindings: '
          '${_argumentBindingListLiteral(argumentBindings)})',
    ProjectListTransform(:final itemTransform) =>
      'ProjectListTransform(itemTransform: '
          '${_valueTransformLiteral(itemTransform)})',
    CoerceScalarTransform(:final scalarCoercion) => 'CoerceScalarTransform('
        'scalarCoercion: ${_escapeDart(scalarCoercion)})',
  };
}

String _argumentBindingListLiteral(List<TransformArgumentBinding> bindings) {
  if (bindings.isEmpty) return '<TransformArgumentBinding>[]';
  return '[${bindings.map(_argumentBindingLiteral).join(', ')}]';
}

String _argumentBindingLiteral(TransformArgumentBinding binding) {
  final base = <String>[
    'parameterRef: ${_wireIdLiteral(binding.parameterRef)}',
    'nullPolicy: TransformNullPolicy.${binding.nullPolicy.name}',
    'missingPolicy: TransformMissingPolicy.${binding.missingPolicy.name}',
  ];
  return switch (binding) {
    PropertyValueArgumentBinding() =>
      'PropertyValueArgumentBinding(${base.join(', ')})',
    LiteralArgumentBinding(:final literal) => 'LiteralArgumentBinding('
        'literal: ${_dartLiteral(literal)}, ${base.join(', ')})',
    NestedTransformArgumentBinding(:final nestedTransform) =>
      'NestedTransformArgumentBinding('
          'nestedTransform: ${_valueTransformLiteral(nestedTransform)}, '
          '${base.join(', ')})',
  };
}

String _discriminatorSpecLiteral(DiscriminatorSpec spec) {
  return 'DiscriminatorSpec(field: ${_escapeDart(spec.field)}, '
      'values: ${_wireIdRefListLiteral(spec.values)})';
}

String _validationExprLiteral(ValidationExpr expr) {
  return 'ValidationExpr(expression: ${_escapeDart(expr.expression)}, '
      'message: ${_escapeDart(expr.message)})';
}

String _themeBindingPathLiteral(ThemeBindingPath path) {
  final p = path.path;
  final r = path.resolverName;
  if (p != null && r != null) {
    return 'ThemeBindingPath.both(path: ${_escapeDart(p)}, '
        'resolverName: ${_escapeDart(r)})';
  }
  return p != null
      ? 'ThemeBindingPath.path(${_escapeDart(p)})'
      : 'ThemeBindingPath.resolver(${_escapeDart(r!)})';
}

String _deprecationLiteral(DeprecationInfo info) {
  final parts = <String>[];
  if (info.source != null) {
    final source = info.source!;
    final args = <String>[
      'message: ${_escapeDart(source.message)}',
      if (source.since != null) 'since: ${_escapeDart(source.since!)}',
    ];
    parts.add('source: SourceDeprecationInfo(${args.join(', ')})');
  }
  if (info.catalog != null) {
    final catalog = info.catalog!;
    final args = <String>[
      'reason: ${_escapeDart(catalog.reason)}',
      'at: ${_escapeDart(catalog.at)}',
      if (catalog.transitionId != null)
        'transitionId: ${_escapeDart(catalog.transitionId!)}',
      if (catalog.replaceWith != null)
        'replaceWith: ${_wireIdRefLiteral(catalog.replaceWith!)}',
    ];
    parts.add('catalog: CatalogDeprecationInfo(${args.join(', ')})');
  }
  return 'DeprecationInfo(${parts.join(', ')})';
}

String _escapeDart(String s) {
  // Backslash first — every later replacement adds backslashes that must
  // not themselves get re-escaped. `$` matters because Dart single-quoted
  // strings interpolate `$identifier` / `${...}`; without escaping, a
  // descriptor like `'Price $9.99'` would either fail to compile or
  // execute an arbitrary expression at compile time.
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return "'$escaped'";
}

String _dartLiteral(Object? v) {
  if (v == null) return 'null';
  if (v is bool || v is num) return '$v';
  if (v is String) return _escapeDart(v);
  if (v is List) return '[${v.map(_dartLiteral).join(', ')}]';
  if (v is Map) {
    final entries = v.entries.map(
      (entry) => '${_dartLiteral(entry.key)}: ${_dartLiteral(entry.value)}',
    );
    return '{${entries.join(', ')}}';
  }
  return 'null';
}
