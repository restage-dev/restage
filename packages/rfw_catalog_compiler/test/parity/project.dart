import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const int _legacySchemaVersion = 2;

/// Projects a canonical catalog onto the legacy catalog schema consumed by the
/// current checked-in baselines.
///
/// The projection intentionally keeps only legacy consumer-visible fields.
/// Wire identity, canonical default-source discriminators, editor metadata,
/// structured types, unions, design tokens, and compatibility metadata are
/// omitted from the returned JSON object.
Map<String, Object?> projectCatalogToLegacyJson(Catalog catalog) {
  final tokenNames = _designTokenNames(catalog.designTokens);
  final structuredByRef = {
    for (final entry in catalog.structuredTypes)
      WireIdRef(library: entry.library.namespace, wireId: entry.wireId): entry,
  };
  return {
    'schemaVersion': _legacySchemaVersion,
    'generatedAt': catalog.generatedAt,
    'libraries': {
      for (final entry in catalog.libraries.entries)
        entry.key.namespace: {
          'version': entry.value.version,
          // Legacy envelope carried a per-library widgetCount; compute it
          // from the catalog now that LibraryInfo no longer stores counts.
          'widgetCount': catalog.widgetsIn(entry.key).length,
        },
    },
    'widgets': [
      for (final widget in catalog.widgets)
        _projectWidget(
          widget,
          tokenNames: tokenNames,
          structuredByRef: structuredByRef,
        ),
    ],
  };
}

Map<String, Object?> _projectWidget(
  WidgetEntry widget, {
  required Map<WireIdRef, String> tokenNames,
  required Map<WireIdRef, StructuredEntry> structuredByRef,
}) {
  return {
    'name': widget.name,
    'library': widget.library.namespace,
    'category': widget.category.name,
    'description': widget.description,
    'flutterType': widget.flutterType,
    'childrenSlot': widget.childrenSlot.name,
    'fires': [
      for (final event in widget.fires) event.name,
    ],
    'properties': [
      for (final property in widget.properties)
        if (!_isStructuredOnlyProperty(property))
          _projectProperty(property, tokenNames: tokenNames),
    ],
    if (widget.decomposes.isNotEmpty)
      'decomposes': [
        for (final recipe in widget.decomposes)
          _projectDecomposition(
            widget,
            recipe,
            structuredByRef: structuredByRef,
          ),
      ],
    if (widget.deprecatedSince != null)
      'deprecatedSince': widget.deprecatedSince,
  };
}

/// Whether [property] surfaces as a cross-reference to a structured
/// catalog entry and therefore must be dropped from the legacy
/// projection.
///
/// Properties with a `structured` slot type are an additive surface —
/// the pre-walker baselines never carried this enum member, nor any
/// `structuredRef` cross-reference. Remove this filter when the
/// baselines are regenerated against the post-default-resolution
/// catalogs in a downstream pass.
bool _isStructuredOnlyProperty(PropertyEntry property) {
  return property.type == PropertyType.structured;
}

Map<String, Object?> _projectProperty(
  PropertyEntry property, {
  required Map<WireIdRef, String> tokenNames,
}) {
  final projectedDefault = _projectDefault(property, tokenNames: tokenNames);
  return {
    'name': property.name,
    'type': property.type.name,
    'description': property.description,
    if (property.required) 'required': true,
    if (projectedDefault.defaultValue != null)
      'defaultValue': projectedDefault.defaultValue,
    if (projectedDefault.defaultBrandToken != null)
      'defaultBrandToken': projectedDefault.defaultBrandToken,
    if (property.synthetic != null) 'synthetic': property.synthetic,
    if (property.positional) 'positional': true,
    if (property.enumType != null) 'enumType': property.enumType,
    if (property.widgetType != null) 'widgetType': property.widgetType,
    if (property.callbackSignature != null)
      'callbackSignature': property.callbackSignature,
    if (property.firesAs != null) 'firesAs': property.firesAs,
  };
}

_ProjectedDefault _projectDefault(
  PropertyEntry property, {
  required Map<WireIdRef, String> tokenNames,
}) {
  final defaultSource = property.defaultSource;
  return switch (defaultSource) {
    LiteralDefault(:final value) => _ProjectedDefault(defaultValue: value),
    TokenRefDefault(:final token) => _ProjectedDefault(
        defaultBrandToken: _requireTokenName(tokenNames, token),
      ),
    ThemeBindingDefault() || FlutterCtorDefault() => const _ProjectedDefault(),
    null => _ProjectedDefault(
        defaultValue: property.defaultValue,
        defaultBrandToken: property.defaultBrandToken,
      ),
  };
}

Map<String, Object?> _projectDecomposition(
  WidgetEntry widget,
  DecompositionRecipe recipe, {
  required Map<WireIdRef, StructuredEntry> structuredByRef,
}) {
  final structured = structuredByRef[recipe.structuredRef];
  if (structured == null) {
    throw StateError(
      'Cannot project decomposition for unresolved structured ref '
      '${recipe.structuredRef}.',
    );
  }
  final fieldsById = {
    for (final field in structured.fields) field.wireId: field.name,
  };
  final propertiesById = {
    for (final property in widget.properties) property.wireId: property.name,
  };
  final flatProperties = <String, String>{};
  for (final entry in recipe.flatProperties.entries) {
    final fieldName = fieldsById[entry.key];
    final propertyName = propertiesById[entry.value];
    if (fieldName == null || propertyName == null) {
      throw StateError(
        'Cannot project decomposition on ${widget.name}: '
        'field ${entry.key} or property ${entry.value} did not resolve.',
      );
    }
    flatProperties[fieldName] = propertyName;
  }
  return {
    'structuredType': structured.name,
    'flatProperties': flatProperties,
  };
}

Map<WireIdRef, String> _designTokenNames(List<DesignTokenEntry> tokens) {
  return {
    for (final token in tokens)
      WireIdRef(library: token.library.namespace, wireId: token.wireId):
          token.name,
  };
}

String _requireTokenName(Map<WireIdRef, String> tokenNames, WireIdRef token) {
  final name = tokenNames[token];
  if (name == null) {
    throw StateError('Cannot project unresolved token default: $token.');
  }
  return name;
}

final class _ProjectedDefault {
  const _ProjectedDefault({
    this.defaultValue,
    this.defaultBrandToken,
  });

  final Object? defaultValue;
  final String? defaultBrandToken;
}
