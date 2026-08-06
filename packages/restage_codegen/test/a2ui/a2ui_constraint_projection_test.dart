import 'dart:convert';

import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'a2ui_safe_pattern_corpus.dart';

void main() {
  test('constraint IR has an empty default and value equality/hash semantics',
      () {
    const node = ScalarNode(A2uiScalarType.integer);
    const empty = A2uiDataField(node);
    final first = A2uiDataField(
      node,
      constraints: A2uiConstraintSet.fromTyped(
        const RestageConstraints(minimum: 0.5, allowedValues: [1, 2]),
      ),
    );
    final equal = A2uiDataField(
      node,
      constraints: A2uiConstraintSet.fromTyped(
        const RestageConstraints(minimum: 0.5, allowedValues: [1, 2]),
      ),
    );

    expect(empty.constraints, A2uiConstraintSet.empty);
    expect(first, equal);
    expect(first.hashCode, equal.hashCode);
    expect(first, isNot(empty));
  });

  test(
    'nullable constrained write-back scalar decorates only the literal arm',
    () {
      final property = _property(
        'count',
        PropertyType.integer,
        required: true,
        defaultSource: const LiteralDefault(1),
        constraints: const RestageConstraints(
          minimum: 0.5,
          maximum: 9.5,
          allowedValues: [1, 2],
        ),
      );
      final catalog = _catalog(
        'BoundedStepper',
        [property, _property('onChanged', PropertyType.event, required: true)],
      );
      const richShapes = <(String, String), A2uiSchemaNode>{
        ('BoundedStepper', 'count'):
            ScalarNode(A2uiScalarType.integer, nullable: true),
      };
      const eventSeam = <(String, String), A2uiCallbackSignature>{
        ('BoundedStepper', 'onChanged'): A2uiCallbackWriteBack(
          A2uiScalarType.integer,
          nullable: true,
          isList: false,
        ),
      };
      const pairingSeam = <(String, String), String>{
        ('BoundedStepper', 'onChanged'): 'count',
      };

      final plan = classifyA2uiCatalogDart(
        catalog,
        richShapes: richShapes,
        eventSeam: eventSeam,
        pairingSeam: pairingSeam,
      ).widgets.single;
      final schema = a2uiWidgetDataSchemaMapForPlan(plan);
      final count = (schema['properties']! as Map)['count']! as Map;
      final arms = count['oneOf']! as List;

      expect(
        arms.first,
        {
          'anyOf': [
            {
              'type': 'integer',
              'minimum': 0.5,
              'maximum': 9.5,
              'enum': [1, 2],
            },
            {'type': 'null'},
          ],
        },
      );
      expect(arms[1], isNot(contains('minimum')));
      expect(arms[1], isNot(contains('enum')));
      expect(arms[2], isNot(contains('maximum')));
      expect(arms[2], isNot(contains('enum')));
      expect(count.toString(), isNot(contains('default')));

      final source = emitA2uiCatalogDart(
        catalog,
        richShapes: richShapes,
        eventSeam: eventSeam,
        pairingSeam: pairingSeam,
      );
      expect(
        source,
        allOf(
          contains('S.fromMap(<String, Object?>{'),
          contains('...S.integer().value,'),
          contains("'minimum': 0.5,"),
          contains("'maximum': 9.5,"),
          contains("'enum': <Object?>[1, 2]"),
        ),
      );
      expect(source, isNot(contains("'default':")));
    },
  );

  test(
    'nullable constrained scalar list projects item counts on its literal arm',
    () {
      final catalog = _catalog(
        'TagPicker',
        [
          _property(
            'tags',
            PropertyType.structured,
            required: true,
            constraints: const RestageConstraints(minItems: 1, maxItems: 3),
          ),
        ],
      );
      final richShapes = <(String, String), A2uiSchemaNode>{
        ('TagPicker', 'tags'): const ListNode(
          element: ScalarNode(A2uiScalarType.string),
          nullable: true,
        ),
      };

      final plan = classifyA2uiCatalogDart(
        catalog,
        richShapes: richShapes,
      ).widgets.single;
      final schema = a2uiWidgetDataSchemaMapForPlan(plan);
      final tags = (schema['properties']! as Map)['tags']! as Map;
      final arms = tags['oneOf']! as List;

      expect(
        arms.first,
        {
          'anyOf': [
            {
              'type': 'array',
              'items': {'type': 'string'},
              'minItems': 1,
              'maxItems': 3,
            },
            {'type': 'null'},
          ],
        },
      );
      expect(arms[1], isNot(contains('minItems')));
      expect(arms[2], isNot(contains('maxItems')));

      final source = emitA2uiCatalogDart(catalog, richShapes: richShapes);
      expect(
        source,
        allOf(
          contains('S.fromMap(<String, Object?>{'),
          contains('...S.list(items: S.string()).value,'),
          contains("'minItems': 1,"),
          contains("'maxItems': 3"),
        ),
      );
    },
  );

  test(
    r'constrained nullable recursive rich list keeps root $defs/$ref twins',
    () {
      const recursiveId = 'package:fixture/recursive.dart#RecursiveItem';
      final recursiveItem = ObjectNode(
        defId: recursiveId,
        construction: A2uiClassConstruction(
          dartTypeName: 'RecursiveItem',
          libraryUri: 'package:fixture/recursive.dart',
          parameters: const [
            A2uiConstructorParameter(name: 'label', named: true),
            A2uiConstructorParameter(name: 'children', named: true),
          ],
        ),
        fields: const {
          'label': ScalarNode(A2uiScalarType.string),
          'children': ListNode(element: RefNode(recursiveId)),
        },
        required: const {'label', 'children'},
      );
      final richList = ListNode(element: recursiveItem, nullable: true);
      final catalog = _catalog(
        'RecursiveList',
        [
          _property(
            'items',
            PropertyType.unknown,
            required: true,
            constraints: const RestageConstraints(minItems: 1, maxItems: 4),
          ),
        ],
      );
      final richShapes = <(String, String), A2uiSchemaNode>{
        ('RecursiveList', 'items'): richList,
      };

      final plan = classifyA2uiCatalogDart(
        catalog,
        richShapes: richShapes,
      ).widgets.single;
      final schema = a2uiWidgetDataSchemaMapForPlan(plan);
      final defs = schema[r'$defs']! as Map;
      final rootKey = (schema[r'$ref']! as String).split('/').last;
      final root = defs[rootKey]! as Map;
      final items = (root['properties']! as Map)['items']! as Map;
      final nonNull = (items['anyOf']! as List).first as Map;

      expect(nonNull['type'], 'array');
      expect(nonNull['minItems'], 1);
      expect(nonNull['maxItems'], 4);
      expect((nonNull['items']! as Map)[r'$ref'], r'#/$defs/RecursiveItem');
      expect(defs, contains('RecursiveItem'));

      final source = emitA2uiCatalogDart(catalog, richShapes: richShapes);
      expect(
        source,
        allOf(
          contains(r'$defs: {'),
          contains("'__a2ui_root__': S.object"),
          contains(r"$ref: '#/\$defs/RecursiveItem'"),
          contains("'minItems': 1"),
          contains("'maxItems': 4"),
        ),
      );
    },
  );

  group('constraint metadata cannot disappear through coverage omissions', () {
    test('optional theme-default omission rejects typed and legacy metadata',
        () {
      final variants = <PropertyEntry>[
        _property(
          'label',
          PropertyType.string,
          defaultSource: const ThemeBindingDefault(
            ThemeBindingPath.path('textTheme.bodyMedium'),
          ),
          constraints: const RestageConstraints(minLength: 1),
        ),
        _property(
          'label',
          PropertyType.string,
          defaultSource: const ThemeBindingDefault(
            ThemeBindingPath.path('textTheme.bodyMedium'),
          ),
          validationRule: const ValidationExpr(
            expression: 'matches(".+")',
            message: 'Label is required.',
          ),
        ),
      ];

      for (final property in variants) {
        expect(
          () => classifyA2uiCatalogDart(_catalog('ThemedLabel', [property])),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('widget "ThemedLabel"'),
                contains('property "label"'),
                contains('theme default'),
              ),
            ),
          ),
        );
      }
    });

    test('optional non-null rich omission rejects typed metadata', () {
      final property = _property(
        'configuration',
        PropertyType.structured,
        constraints: const RestageConstraints(minItems: 1),
      );
      final richShapes = <(String, String), A2uiSchemaNode>{
        ('ConfiguredCard', 'configuration'): ListNode(
          element: ObjectNode(fields: const {}, required: const {}),
        ),
      };

      expect(
        () => classifyA2uiCatalogDart(
          _catalog('ConfiguredCard', [property]),
          richShapes: richShapes,
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('widget "ConfiguredCard"'),
              contains('property "configuration"'),
              contains('optional non-null rich field'),
            ),
          ),
        ),
      );
    });

    test('optional reserved builder identifier rejects typed metadata', () {
      final property = _property(
        'data',
        PropertyType.string,
        constraints: const RestageConstraints(minLength: 1),
      );

      expect(
        () => classifyA2uiCatalogDart(_catalog('ReservedValue', [property])),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('widget "ReservedValue"'),
              contains('property "data"'),
            ),
          ),
        ),
      );
    });

    test('decompose-consumed property rejects legacy metadata', () {
      final propertyId = WireId('p0001');
      final fieldId = WireId('p0501');
      final property = _property(
        'fontSize',
        PropertyType.real,
        wireId: propertyId,
        validationRule: const ValidationExpr(
          expression: 'range(8, 72)',
          message: 'Use a readable font size.',
        ),
      );
      final widget = entry(
        name: 'DecomposedText',
        properties: [property],
        decomposes: [
          DecompositionRecipe(
            structuredRef: const WireIdRef(
              library: 'restage.core',
              wireId: WireId.unallocatedStructured,
            ),
            flatProperties: {fieldId: propertyId},
            fieldMappings: [
              DecompositionFieldMapping(
                fieldRef: fieldId,
                propertyRef: propertyId,
                transform: const IdentityTransform(),
              ),
            ],
          ),
        ],
      );

      expect(
        () => classifyA2uiCatalogDart(catalogWith([widget])),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('widget "DecomposedText"'),
              contains('property "fontSize"'),
              contains('native decompose'),
            ),
          ),
        ),
      );
    });

    test('early whole-widget drop rejects metadata on any property', () {
      final widget = entry(
        name: 'MissingChild',
        childrenSlot: ChildrenSlot.single,
        properties: [
          _property(
            'label',
            PropertyType.string,
            constraints: const RestageConstraints(minLength: 1),
          ),
        ],
      );

      expect(
        () => classifyA2uiCatalogDart(catalogWith([widget])),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('widget "MissingChild"'),
              contains('property "label"'),
              contains('widget is dropped'),
            ),
          ),
        ),
      );
    });

    test('late whole-widget drop rejects metadata already classified', () {
      final catalog = _catalog(
        'LateDrop',
        [
          _property(
            'label',
            PropertyType.string,
            constraints: const RestageConstraints(minLength: 1),
          ),
          _property('unsupported', PropertyType.unknown, required: true),
        ],
      );

      expect(
        () => classifyA2uiCatalogDart(catalog),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('widget "LateDrop"'),
              contains('property "label"'),
              contains('widget is dropped'),
            ),
          ),
        ),
      );
    });
  });

  group('final-node constraint validation', () {
    test('rejects mixed typed and legacy authoring', () {
      _expectInvalidConstraint(
        type: PropertyType.integer,
        constraints: const RestageConstraints(minimum: 0),
        validationRule: const ValidationExpr(
          expression: 'range(0, 10)',
          message: 'Use the range.',
        ),
        expected: 'mutually exclusive',
      );
    });

    test('rejects incompatible constraint families', () {
      _expectInvalidConstraint(
        type: PropertyType.string,
        constraints: const RestageConstraints(minimum: 0),
        expected: 'numeric constraints require a number or integer node',
      );
      _expectInvalidConstraint(
        type: PropertyType.integer,
        constraints: const RestageConstraints(minLength: 1),
        expected: 'string constraints require a string or enum node',
      );
      _expectInvalidConstraint(
        type: PropertyType.integer,
        constraints: const RestageConstraints(minItems: 1),
        expected: 'item constraints require a list node',
      );
      _expectInvalidConstraint(
        type: PropertyType.integer,
        constraints: const RestageConstraints(allowedValues: [true]),
        expected: 'allowedValues[0]',
      );
    });

    test('rejects invalid numeric bounds', () {
      _expectInvalidConstraint(
        type: PropertyType.integer,
        constraints: const RestageConstraints(
          minimum: 0,
          exclusiveMinimum: 1,
        ),
        expected: 'minimum and exclusiveMinimum are mutually exclusive',
      );
      _expectInvalidConstraint(
        type: PropertyType.integer,
        constraints: const RestageConstraints(
          maximum: 10,
          exclusiveMaximum: 9,
        ),
        expected: 'maximum and exclusiveMaximum are mutually exclusive',
      );
      _expectInvalidConstraint(
        type: PropertyType.real,
        constraints: const RestageConstraints(minimum: double.nan),
        expected: 'minimum must be finite',
      );
      _expectInvalidConstraint(
        type: PropertyType.real,
        constraints: const RestageConstraints(
          exclusiveMinimum: 5,
          maximum: 5,
        ),
        expected: 'contradictory numeric lower and upper bounds',
      );
    });

    test('rejects negative or inverted length and item counts', () {
      _expectInvalidConstraint(
        type: PropertyType.string,
        constraints: const RestageConstraints(minLength: -1),
        expected: 'minLength must be non-negative',
      );
      _expectInvalidConstraint(
        type: PropertyType.stringList,
        constraints: const RestageConstraints(minItems: 3, maxItems: 2),
        expected: 'minItems must not exceed maxItems',
      );
    });

    test('rejects malformed or incompatible scalar enums', () {
      _expectInvalidConstraint(
        type: PropertyType.boolean,
        constraints: const RestageConstraints(allowedValues: []),
        expected: 'allowedValues must not be empty',
      );
      _expectInvalidConstraint(
        type: PropertyType.integer,
        constraints: const RestageConstraints(allowedValues: [1, 1.0]),
        expected: 'duplicate allowedValues[1]',
      );
      _expectInvalidConstraint(
        type: PropertyType.real,
        constraints: const RestageConstraints(allowedValues: [double.infinity]),
        expected: 'allowedValues[0] numeric value must be finite',
      );
      _expectInvalidConstraint(
        type: PropertyType.string,
        constraints: const RestageConstraints(allowedValues: [<String>[]]),
        expected: 'allowedValues[0] must be a JSON scalar',
      );
      _expectInvalidConstraint(
        type: PropertyType.enumValue,
        constraints: const RestageConstraints(
          allowedValues: ['small', 'ghost'],
        ),
        node: EnumNode(
          members: const ['small', 'large'],
          dartTypeName: 'Size',
        ),
        expected: 'allowedValues[1] "ghost" is not a resolved enum member',
      );
    });

    test('catalog-only enum subsets require analyzer-resolved members', () {
      _expectInvalidConstraint(
        type: PropertyType.enumValue,
        enumType: 'Size',
        flutterType: 'package:flutter/widgets.dart#EnumProbe',
        constraints: const RestageConstraints(allowedValues: ['small']),
        expected: 'analyzer-resolved enum member set',
      );
      _expectInvalidConstraint(
        type: PropertyType.enumValue,
        enumType: 'Size',
        flutterType: 'package:flutter/widgets.dart#EnumProbe',
        constraints: RestageConstraints.empty,
        validationRule: const ValidationExpr(
          expression: 'oneOf("small")',
          message: 'Choose a size.',
        ),
        expected: 'analyzer-resolved enum member set',
      );

      final unconstrained = classifyA2uiCatalogDart(
        _catalog(
          'CatalogEnum',
          [_property('value', PropertyType.enumValue, enumType: 'Size')],
          flutterType: 'package:flutter/widgets.dart#EnumProbe',
        ),
      ).widgets.single;
      final value =
          (a2uiWidgetDataSchemaMapForPlan(unconstrained)['properties']!
              as Map)['value'];
      expect(value, {'type': 'string'});
    });

    test('rejects null-only allowed values on list and object nodes', () {
      final nodes = <A2uiSchemaNode>[
        const ListNode(element: ScalarNode(A2uiScalarType.string)),
        ObjectNode(fields: const {}, required: const {}),
      ];

      for (final node in nodes) {
        _expectInvalidConstraint(
          type: PropertyType.structured,
          constraints: const RestageConstraints(allowedValues: [null]),
          node: node,
          expected: 'allowedValues require a scalar node',
        );
      }
    });

    test('retains null as an allowed value on a scalar node', () {
      final plan = classifyA2uiCatalogDart(
        _catalog(
          'NullableEnum',
          [
            _property(
              'value',
              PropertyType.string,
              required: true,
              constraints: const RestageConstraints(allowedValues: [null]),
            ),
          ],
        ),
      ).widgets.single;
      final schema = a2uiWidgetDataSchemaMapForPlan(plan);
      final value = (schema['properties']! as Map)['value']! as Map;

      expect(value['enum'], [null]);
    });
  });

  test('typed projection covers every admitted keyword in both projectors', () {
    final cases = <({
      PropertyType type,
      RestageConstraints constraints,
      Map<String, Object?> expectedLiteral,
    })>[
      (
        type: PropertyType.integer,
        constraints: const RestageConstraints(
          minimum: -2,
          maximum: 8,
          allowedValues: [-2, 0, 8],
        ),
        expectedLiteral: {
          'type': 'integer',
          'minimum': -2,
          'maximum': 8,
          'enum': [-2, 0, 8],
        },
      ),
      (
        type: PropertyType.real,
        constraints: const RestageConstraints(
          exclusiveMinimum: 0.25,
          exclusiveMaximum: 0.75,
        ),
        expectedLiteral: {
          'type': 'number',
          'exclusiveMinimum': 0.25,
          'exclusiveMaximum': 0.75,
        },
      ),
      (
        type: PropertyType.string,
        constraints: const RestageConstraints(
          pattern: r'^[A-Z]{2}[0-9]+$',
          minLength: 3,
          maxLength: 8,
        ),
        expectedLiteral: {
          'type': 'string',
          'pattern': r'^[A-Z]{2}[0-9]+$',
          'minLength': 3,
          'maxLength': 8,
        },
      ),
      (
        type: PropertyType.stringList,
        constraints: const RestageConstraints(minItems: 1, maxItems: 3),
        expectedLiteral: {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 1,
          'maxItems': 3,
        },
      ),
    ];

    for (final testCase in cases) {
      final plan = classifyA2uiCatalogDart(
        _catalog(
          'TypedFamilies',
          [
            _property(
              'value',
              testCase.type,
              required: true,
              constraints: testCase.constraints,
            ),
          ],
        ),
      ).widgets.single;
      final projected = _projectedValue(plan);
      final literal = projected['oneOf'] is List
          ? ((projected['oneOf']! as List).first as Map).cast<String, Object?>()
          : projected;
      final expression = _projectedExpression(plan);

      expect(literal, testCase.expectedLiteral);
      for (final keyword in testCase.expectedLiteral.keys.where(
        (key) => key != 'type' && key != 'items',
      )) {
        expect(expression, contains("'$keyword':"));
      }
      expect(projected.toString(), isNot(contains('default')));
      expect(projected.toString(), isNot(contains(r'$comment')));
    }
  });

  group('exact legacy constraint grammar', () {
    test('translates each admitted family without projecting its message', () {
      final cases = <({
        PropertyType type,
        String expression,
        Map<String, Object?> expected,
      })>[
        (
          type: PropertyType.real,
          expression: ' range ( -1.5e2 , 20 ) ',
          expected: {'minimum': -150.0, 'maximum': 20},
        ),
        (
          type: PropertyType.real,
          expression: 'oneOf(1, -2.5, 3e2, null)',
          expected: {
            'enum': [1, -2.5, 300.0, null],
          },
        ),
        (
          type: PropertyType.boolean,
          expression: 'oneOf(true, false, null)',
          expected: {
            'enum': [true, false, null],
          },
        ),
        (
          type: PropertyType.string,
          expression: 'oneOf("small", "large", null)',
          expected: {
            'enum': ['small', 'large', null],
          },
        ),
        (
          type: PropertyType.string,
          expression: r'matches("^[A-Z]{2}[0-9]+$")',
          expected: {'pattern': r'^[A-Z]{2}[0-9]+$'},
        ),
      ];

      for (final testCase in cases) {
        final property = _property(
          'value',
          testCase.type,
          required: true,
          validationRule: ValidationExpr(
            expression: testCase.expression,
            message: 'Catalog-only diagnostic message.',
          ),
        );
        final plan = classifyA2uiCatalogDart(
          _catalog('LegacyFamilies', [property]),
        ).widgets.single;
        final value = _projectedValue(plan);
        final expression = _projectedExpression(plan);

        expect(value, containsPair('type', isNotNull));
        for (final entry in testCase.expected.entries) {
          expect(value[entry.key], entry.value, reason: testCase.expression);
          expect(
            expression,
            contains("'${entry.key}':"),
            reason: testCase.expression,
          );
        }
        expect(value, isNot(contains('default')));
        expect(value, isNot(contains(r'$comment')));
        expect(value.toString(), isNot(contains('Catalog-only diagnostic')));
        expect(expression, isNot(contains('Catalog-only diagnostic')));
        expect(
          plan.entry.properties.single.validationRule?.message,
          'Catalog-only diagnostic message.',
        );
      }
    });

    test('rejects malformed, ambiguous, and unfaithful forms with context', () {
      const malformed = <({String expression, PropertyType type})>[
        (expression: 'range(1)', type: PropertyType.real),
        (expression: 'range(1, 2, 3)', type: PropertyType.real),
        (expression: 'range(+1, 2)', type: PropertyType.real),
        (expression: 'range(01, 2)', type: PropertyType.real),
        (expression: 'range(1e9999, 2)', type: PropertyType.real),
        (expression: 'range(2, 1)', type: PropertyType.real),
        (expression: 'oneOf()', type: PropertyType.real),
        (expression: 'oneOf([1])', type: PropertyType.real),
        (expression: 'oneOf({"value": 1})', type: PropertyType.real),
        (expression: 'oneOf("a",)', type: PropertyType.string),
        (expression: 'oneOf(true, true)', type: PropertyType.boolean),
        (expression: 'matches(a+)', type: PropertyType.string),
        (expression: r'matches("\q")', type: PropertyType.string),
        (expression: 'matches("a", "b")', type: PropertyType.string),
        (expression: 'matches("a") trailing', type: PropertyType.string),
        (expression: 'greaterThan(0)', type: PropertyType.real),
      ];

      for (final testCase in malformed) {
        _expectInvalidLegacy(testCase.expression, type: testCase.type);
      }
    });
  });

  group('shared ASCII safe-pattern corpus', () {
    test('typed and legacy patterns admit the same corpus in both projectors',
        () {
      for (final testCase in acceptedA2uiPatternCases) {
        final authorings = <PropertyEntry>[
          _property(
            'value',
            PropertyType.string,
            required: true,
            constraints: RestageConstraints(pattern: testCase.pattern),
          ),
          _property(
            'value',
            PropertyType.string,
            required: true,
            validationRule: ValidationExpr(
              expression: 'matches(${_jsonString(testCase.pattern)})',
              message: 'Pattern mismatch.',
            ),
          ),
        ];

        for (final property in authorings) {
          final plan = classifyA2uiCatalogDart(
            _catalog('SafePattern', [property]),
          ).widgets.single;
          expect(_projectedValue(plan)['pattern'], testCase.pattern);
          expect(_projectedExpression(plan), contains("'pattern':"));
        }
      }
    });

    test('typed and legacy patterns reject the same corpus with full context',
        () {
      for (final pattern in rejectedA2uiPatterns) {
        _expectInvalidConstraint(
          type: PropertyType.string,
          constraints: RestageConstraints(pattern: pattern),
          expected: 'safe ASCII pattern grammar',
        );

        _expectInvalidLegacy(
          'matches(${_jsonString(pattern)})',
          type: PropertyType.string,
        );
      }
    });
  });

  test('unsupported legacy syntax fails loud with complete source context', () {
    final property = _property(
      'count',
      PropertyType.integer,
      validationRule: const ValidationExpr(
        expression: 'greaterThan(0)',
        message: 'Count must be positive.',
      ),
    );
    final catalog = _catalog('LegacyCounter', [property]);
    expect(
      property.validationRule?.message,
      'Count must be positive.',
      reason: 'the authored message remains diagnostic/catalog metadata',
    );

    expect(
      () => classifyA2uiCatalogDart(catalog),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('widget "LegacyCounter"'),
            contains('property "count"'),
            contains('greaterThan(0)'),
            contains('range(<finite number>, <finite number>)'),
            contains('oneOf(<JSON scalar>, ...)'),
            contains('matches(<JSON string>)'),
          ),
        ),
      ),
    );
  });
}

Map<String, Object?> _projectedValue(A2uiDartWidgetPlan plan) =>
    ((a2uiWidgetDataSchemaMapForPlan(plan)['properties']! as Map)['value']!
            as Map)
        .cast<String, Object?>();

String _projectedExpression(A2uiDartWidgetPlan plan) =>
    a2uiWidgetDataSchemaExpression([
      (
        name: 'value',
        required: true,
        emission: plan.fields.single.emission,
      ),
    ]);

String _jsonString(String value) => const JsonEncoder().convert(value);

void _expectInvalidLegacy(
  String expression, {
  required PropertyType type,
}) {
  final property = _property(
    'value',
    type,
    required: true,
    validationRule: ValidationExpr(
      expression: expression,
      message: 'Keep this message.',
    ),
  );

  expect(
    () => classifyA2uiCatalogDart(_catalog('InvalidLegacy', [property])),
    throwsA(
      isA<UnsupportedError>().having(
        (error) => error.message,
        'message',
        allOf(
          contains('widget "InvalidLegacy"'),
          contains('property "value"'),
          contains(expression),
          contains('range(<finite number>, <finite number>)'),
          contains('oneOf(<JSON scalar>, ...)'),
          contains('matches(<JSON string>)'),
          contains('Keep this message.'),
        ),
      ),
    ),
  );
}

PropertyEntry _property(
  String name,
  PropertyType type, {
  WireId wireId = WireId.unallocatedProperty,
  bool required = false,
  DefaultValueSource? defaultSource,
  ValidationExpr? validationRule,
  RestageConstraints constraints = RestageConstraints.empty,
  String? enumType,
}) =>
    PropertyEntry(
      wireId: wireId,
      name: name,
      type: type,
      description: '',
      required: required,
      defaultSource: defaultSource,
      validationRule: validationRule,
      constraints: constraints,
      enumType: enumType,
    );

Catalog _catalog(
  String name,
  List<PropertyEntry> properties, {
  String? flutterType,
}) =>
    catalogWith([
      entry(
        name: name,
        flutterType: flutterType ?? 'package:fixture/fixture.dart#$name',
        properties: properties,
      ),
    ]);

void _expectInvalidConstraint({
  required PropertyType type,
  required RestageConstraints constraints,
  required String expected,
  ValidationExpr? validationRule,
  A2uiSchemaNode? node,
  String? enumType,
  String? flutterType,
}) {
  final property = _property(
    'value',
    type,
    required: true,
    validationRule: validationRule,
    constraints: constraints,
    enumType: enumType,
  );
  final catalog = _catalog(
    'InvalidConstraint',
    [property],
    flutterType: flutterType,
  );
  final richShapes = node == null
      ? null
      : <(String, String), A2uiSchemaNode>{
          ('InvalidConstraint', 'value'): node,
        };

  expect(
    () => classifyA2uiCatalogDart(catalog, richShapes: richShapes),
    throwsA(
      isA<UnsupportedError>().having(
        (error) => error.message,
        'message',
        allOf(
          contains('widget "InvalidConstraint"'),
          contains('property "value"'),
          contains(expected),
        ),
      ),
    ),
  );
}
