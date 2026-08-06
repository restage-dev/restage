import 'package:json_schema/json_schema.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'a2ui_safe_pattern_corpus.dart';

void main() {
  test('json_schema 5.2.2 enforces the admitted Draft 2020-12 keywords', () {
    const cases = <({
      Map<String, Object?> schema,
      Object? valid,
      Object? invalid,
    })>[
      (schema: {'type': 'number', 'minimum': 1.5}, valid: 1.5, invalid: 1.49),
      (
        schema: {'type': 'number', 'exclusiveMinimum': 1.5},
        valid: 1.51,
        invalid: 1.5,
      ),
      (schema: {'type': 'number', 'maximum': 2.5}, valid: 2.5, invalid: 2.51),
      (
        schema: {'type': 'number', 'exclusiveMaximum': 2.5},
        valid: 2.49,
        invalid: 2.5,
      ),
      (
        schema: {
          'enum': ['ready', 2, false, null],
        },
        valid: false,
        invalid: true
      ),
      (
        schema: {'type': 'string', 'pattern': 'a+'},
        valid: 'baac',
        invalid: 'bc'
      ),
      (schema: {'type': 'string', 'minLength': 2}, valid: 'ab', invalid: 'a'),
      (schema: {'type': 'string', 'maxLength': 2}, valid: 'ab', invalid: 'abc'),
      (schema: {'type': 'array', 'minItems': 2}, valid: [1, 2], invalid: [1]),
      (
        schema: {'type': 'array', 'maxItems': 2},
        valid: [1, 2],
        invalid: [1, 2, 3],
      ),
    ];

    for (final testCase in cases) {
      final schema = JsonSchema.create(
        {
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          ...testCase.schema,
        },
        schemaVersion: SchemaVersion.draft2020_12,
      );

      expect(schema.schemaVersion, SchemaVersion.draft2020_12);
      expect(
        schema.validate(testCase.valid).isValid,
        isTrue,
        reason: '${testCase.schema} should accept ${testCase.valid}',
      );
      expect(
        schema.validate(testCase.invalid).isValid,
        isFalse,
        reason: '${testCase.schema} should reject ${testCase.invalid}',
      );
    }
  });

  test('projected numeric bounds enforce just-below/at/just-above edges', () {
    final inclusive = _projectedLeaf(
      PropertyType.real,
      constraints: const RestageConstraints(minimum: 1.5, maximum: 2.5),
    );
    _expectValidation(inclusive, const [
      (instance: 1.49, valid: false),
      (instance: 1.5, valid: true),
      (instance: 1.51, valid: true),
      (instance: 2.49, valid: true),
      (instance: 2.5, valid: true),
      (instance: 2.51, valid: false),
    ]);

    final exclusive = _projectedLeaf(
      PropertyType.real,
      constraints: const RestageConstraints(
        exclusiveMinimum: 1.5,
        exclusiveMaximum: 2.5,
      ),
    );
    _expectValidation(exclusive, const [
      (instance: 1.49, valid: false),
      (instance: 1.5, valid: false),
      (instance: 1.51, valid: true),
      (instance: 2.49, valid: true),
      (instance: 2.5, valid: false),
      (instance: 2.51, valid: false),
    ]);
  });

  test('projected string lengths enforce below/at/inside/at/above edges', () {
    final schema = _projectedLeaf(
      PropertyType.string,
      constraints: const RestageConstraints(minLength: 2, maxLength: 4),
    );
    _expectValidation(schema, const [
      (instance: 'a', valid: false),
      (instance: 'ab', valid: true),
      (instance: 'abc', valid: true),
      (instance: 'abcd', valid: true),
      (instance: 'abcde', valid: false),
    ]);
  });

  test('projected item counts enforce below/at/inside/at/above edges', () {
    final schema = _projectedLeaf(
      PropertyType.stringList,
      constraints: const RestageConstraints(minItems: 2, maxItems: 4),
    );
    _expectValidation(schema, const [
      (instance: <String>['a'], valid: false),
      (instance: <String>['a', 'b'], valid: true),
      (instance: <String>['a', 'b', 'c'], valid: true),
      (instance: <String>['a', 'b', 'c', 'd'], valid: true),
      (instance: <String>['a', 'b', 'c', 'd', 'e'], valid: false),
    ]);
  });

  test('projected scalar enum accepts only admitted values', () {
    final schema = _projectedLeaf(
      PropertyType.string,
      constraints: const RestageConstraints(
        allowedValues: ['small', 'large'],
      ),
    );
    _expectValidation(schema, const [
      (instance: 'small', valid: true),
      (instance: 'large', valid: true),
      (instance: 'medium', valid: false),
      (instance: 1, valid: false),
    ]);
  });

  test('the admitted pattern corpus has JSON Schema search semantics', () {
    for (final testCase in acceptedA2uiPatternCases) {
      final schema = _projectedLeaf(
        PropertyType.string,
        constraints: RestageConstraints(pattern: testCase.pattern),
      );
      _expectValidation(schema, [
        (instance: testCase.matching, valid: true),
        if (testCase.nonMatching case final nonMatching?)
          (instance: nonMatching, valid: false),
      ]);
    }
  });
}

Map<String, Object?> _projectedLeaf(
  PropertyType type, {
  RestageConstraints constraints = RestageConstraints.empty,
}) {
  final catalog = catalogWith([
    entry(
      name: 'ConstraintOracle',
      properties: [
        PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: 'value',
          type: type,
          description: '',
          required: true,
          constraints: constraints,
        ),
      ],
    ),
  ]);
  final plan = classifyA2uiCatalogDart(catalog).widgets.single;
  return ((a2uiWidgetDataSchemaMapForPlan(plan)['properties']! as Map)['value']!
          as Map)
      .cast<String, Object?>();
}

void _expectValidation(
  Map<String, Object?> projected,
  List<({Object? instance, bool valid})> cases,
) {
  final schema = JsonSchema.create(
    {
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      ...projected,
    },
    schemaVersion: SchemaVersion.draft2020_12,
  );
  for (final testCase in cases) {
    expect(
      schema.validate(testCase.instance).isValid,
      testCase.valid,
      reason: '$projected on ${testCase.instance}',
    );
  }
}
