/// Protocol constants and constructor-to-wire mapping for A2UI 1.0.
library;

import 'package:a2ui_core/a2ui_core.dart' as core;
import 'package:json_schema_builder/json_schema_builder.dart';

/// The A2UI protocol version the emitted catalogs declare.
const String kA2uiProtocolVersion = '1.0';

/// The emitted catalog JSON Schema dialect.
const String kA2uiSchemaDialect =
    'https://json-schema.org/draft/2020-12/schema';

/// Injective constructor mapping into upstream component-property identifiers.
/// Ordinary names retain their prefix. Invalid identifiers and the reserved
/// `encoded_` source namespace use fixed-width lowercase UTF-16 code-unit hex.
/// Nested rich-data names are outside this component-property boundary.
String a2uiPropertyName(String constructorName) {
  final direct = 'props_$constructorName';
  if (!constructorName.startsWith('encoded_') &&
      core.isValidUax31Identifier(direct)) {
    return direct;
  }
  final encoded = constructorName.codeUnits
      .map((unit) => unit.toRadixString(16).padLeft(4, '0'))
      .join();
  return 'props_encoded_$encoded';
}

/// Catalog `$defs` reference prefix for one component's definitions. A `.`
/// never occurs in a component name or a definition key, so `<Component>.<Key>`
/// names are injective and never shadow a common type.
String a2uiComponentReferencePrefix(String componentName) =>
    '#/\$defs/$componentName.';

/// Removes projection-local definitions after they are moved to catalog scope.
Map<String, Object?> a2uiComponentPropertySchema(Map<String, Object?> schema) {
  final result = Map<String, Object?>.of(schema)..remove(r'$defs');
  // Core discovers component properties through allOf references. A bare root
  // reference is valid JSON Schema but is not flattened as a component shape.
  if (result.remove(r'$ref') case final String reference) {
    result['allOf'] = [
      {r'$ref': reference},
    ];
  }
  return result;
}

/// Hoists each component's definitions into flat catalog `$defs`.
Map<String, Object?> a2uiCatalogDefinitions(
  Map<String, Map<String, Object?>> componentSchemas,
) {
  // Catalog.toJson normalizes CommonSchemas markers in component schemas,
  // while root definitions are copied verbatim. Normalize before hoisting so
  // the producer document contains standard references at every depth.
  final normalized =
      core.Catalog<core.ComponentApi, core.FunctionApi>(
            id: 'restage:schema-projection',
            protocolVersion: core.A2uiProtocolVersion.v1_0,
            components: [
              for (final entry in componentSchemas.entries)
                core.ComponentApi(
                  name: entry.key,
                  schema: Schema.fromMap(entry.value),
                ),
            ],
          ).toJson()['components']!
          as Map<String, Object?>;
  return {
    for (final entry in normalized.entries)
      if ((entry.value! as Map<String, Object?>)[r'$defs']
          case final Map<String, Object?> definitions)
        for (final definition in definitions.entries)
          '${entry.key}.${definition.key}': definition.value,
  };
}

/// The upstream v1 component ID schema, held here so catalog identity does not
/// depend on the upstream package's copy.
const Map<String, Object?> a2uiComponentIdSchema = {
  'type': 'string',
  'description': 'The unique identifier for a component.',
  'commonTypesRef': r'common_types.json#/$defs/ComponentId',
};
