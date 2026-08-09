import 'dart:convert';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('RestageConstraints public contract', () {
    test('is const-constructible for annotation authoring', () {
      const constraints = RestageConstraints(
        minimum: 1,
        maximum: 5,
        allowedValues: [1, 3, 5],
      );
      const annotation = RestageProperty(
        description: 'Count.',
        constraints: constraints,
      );
      final property = PropertyEntry(
        wireId: WireId('p0001'),
        name: 'count',
        type: PropertyType.integer,
        description: 'Count.',
        constraints: constraints,
      );

      expect(annotation.constraints, same(constraints));
      expect(property.constraints, same(constraints));
      expect(const RestageProperty(description: 'x').constraints, isEmpty);
      expect(
        PropertyEntry(
          wireId: WireId('p0002'),
          name: 'other',
          type: PropertyType.string,
          description: 'Other.',
        ).constraints,
        isEmpty,
      );
    });

    test('compares all known and extension values structurally', () {
      final first = RestageConstraints.withExtensions(
        minimum: 1,
        exclusiveMaximum: 9,
        allowedValues: const [1, 2, null],
        pattern: r'^[a-z]+$',
        minLength: 1,
        maxLength: 8,
        minItems: 1,
        maxItems: 3,
        extensions: const {
          'x-future': {
            'first': 1,
            'ordered': [true, null, 'yes'],
          },
          'x-another': [1, 2],
        },
      );
      final second = RestageConstraints.withExtensions(
        minimum: 1,
        exclusiveMaximum: 9,
        allowedValues: const [1, 2, null],
        pattern: r'^[a-z]+$',
        minLength: 1,
        maxLength: 8,
        minItems: 1,
        maxItems: 3,
        extensions: const {
          'x-another': [1, 2],
          'x-future': {
            'ordered': [true, null, 'yes'],
            'first': 1,
          },
        },
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(isEmpty));
    });

    test('uses JSON numeric equality while preserving list order', () {
      final integerNumbers = RestageConstraints.withExtensions(
        allowedValues: const [1, 'tail'],
        extensions: const {
          'x-json': {
            'number': 1,
            'ordered': [1, 2],
          },
          'x-other': true,
        },
      );
      final doubleNumbers = RestageConstraints.withExtensions(
        allowedValues: const [1.0, 'tail'],
        extensions: const {
          'x-other': true,
          'x-json': {
            'ordered': [1.0, 2.0],
            'number': 1.0,
          },
        },
      );

      expect(integerNumbers, doubleNumbers);
      expect(integerNumbers.hashCode, doubleNumbers.hashCode);
      expect(
        integerNumbers,
        isNot(
          RestageConstraints.withExtensions(
            allowedValues: const ['tail', 1.0],
            extensions: doubleNumbers.extensions,
          ),
        ),
      );
      expect(
        integerNumbers,
        isNot(
          RestageConstraints.withExtensions(
            allowedValues: const [1.0, 'tail'],
            extensions: const {
              'x-json': {
                'number': 1.0,
                'ordered': [2.0, 1.0],
              },
              'x-other': true,
            },
          ),
        ),
      );
    });

    test('deep-freezing constructor severs input and output aliases', () {
      final nestedList = <Object?>[true, null];
      final nestedMap = <String, Object?>{'nested': nestedList};
      final extensions = <String, Object?>{'x-future': nestedMap};
      final allowedValues = <Object?>['first', 'second'];

      final constraints = RestageConstraints.withExtensions(
        allowedValues: allowedValues,
        extensions: extensions,
      );
      allowedValues[0] = 'changed';
      nestedList[0] = false;
      nestedMap['added'] = 1;
      extensions['another'] = 2;

      expect(constraints.allowedValues, ['first', 'second']);
      expect(constraints.extensions, {
        'x-future': {
          'nested': [true, null],
        },
      });
      expect(
        () => constraints.allowedValues!.add('third'),
        throwsUnsupportedError,
      );
      expect(
        () => constraints.extensions['another'] = 2,
        throwsUnsupportedError,
      );
      final frozenMap =
          constraints.extensions['x-future']! as Map<Object?, Object?>;
      final frozenList = frozenMap['nested']! as List<Object?>;
      expect(() => frozenMap['added'] = 1, throwsUnsupportedError);
      expect(() => frozenList.add(false), throwsUnsupportedError);
    });
  });

  group('schema-v4 constraints wire contract', () {
    test('round trips valid exclusive-minimum and maximum bounds', () {
      const constraints = RestageConstraints(
        exclusiveMinimum: 1,
        maximum: 10,
      );
      final source = encodeCatalog(
        _catalog(
          _property(
            type: PropertyType.real,
            constraints: constraints,
          ),
        ),
      );
      final raw = jsonDecode(source) as Map<String, dynamic>;
      final wireConstraints =
          _wireProperties(raw).single['constraints']! as Map<String, dynamic>;

      expect(wireConstraints.keys, ['exclusiveMinimum', 'maximum']);
      final decoded = decodeCatalog(source);
      expect(decoded.widgets.single.properties.single.constraints, constraints);
      expect(encodeCatalog(decoded), source);
    });

    test(
      'encodes each family in deterministic order and preserves unknowns',
      () {
        final numericConstraints = RestageConstraints.withExtensions(
          minimum: 1,
          exclusiveMaximum: 10,
          allowedValues: const [1, 2, null],
          extensions: const {
            'x-future': {
              'nested': [true, null, 'value'],
            },
            'x-order': 2,
          },
        );
        const stringConstraints = RestageConstraints(
          pattern: r'^item-[0-9]+$',
          minLength: 2,
          maxLength: 12,
        );
        const listConstraints = RestageConstraints(
          minItems: 1,
          maxItems: 4,
        );
        final source = encodeCatalog(
          _catalogWithProperties([
            _property(
              name: 'count',
              type: PropertyType.integer,
              constraints: numericConstraints,
            ),
            _property(
              wireId: 'p0002',
              name: 'label',
              type: PropertyType.string,
              constraints: stringConstraints,
            ),
            _property(
              wireId: 'p0003',
              name: 'tags',
              type: PropertyType.stringList,
              constraints: listConstraints,
            ),
          ]),
        );
        final raw = jsonDecode(source) as Map<String, dynamic>;
        final wireProperties = _wireProperties(raw);
        final numericWire =
            wireProperties[0]['constraints']! as Map<String, dynamic>;
        final stringWire =
            wireProperties[1]['constraints']! as Map<String, dynamic>;
        final listWire =
            wireProperties[2]['constraints']! as Map<String, dynamic>;

        expect(numericWire.keys, [
          'minimum',
          'exclusiveMaximum',
          'enum',
          'x-future',
          'x-order',
        ]);
        expect(stringWire.keys, [
          'pattern',
          'minLength',
          'maxLength',
        ]);
        expect(listWire.keys, [
          'minItems',
          'maxItems',
        ]);
        expect(
          <Object?>{
            ...numericWire.keys,
            ...stringWire.keys,
            ...listWire.keys,
          },
          {
            'minimum',
            'exclusiveMaximum',
            'enum',
            'pattern',
            'minLength',
            'maxLength',
            'minItems',
            'maxItems',
            'x-future',
            'x-order',
          },
        );

        final decoded = decodeCatalog(source);
        final decodedProperties = decoded.widgets.single.properties;
        expect(decodedProperties[0].constraints, numericConstraints);
        expect(decodedProperties[1].constraints, stringConstraints);
        expect(decodedProperties[2].constraints, listConstraints);
        expect(encodeCatalog(decoded), source);
        expect(
          () => (decodedProperties[0].constraints.extensions['x-future']!
              as Map<Object?, Object?>)['changed'] = true,
          throwsUnsupportedError,
        );
        expect(
          () => decodedProperties[0].constraints.allowedValues!.add(3),
          throwsUnsupportedError,
        );
      },
    );

    test('empty constraints preserve the exact pre-constraint bytes', () {
      final catalog = _catalog(_property(type: PropertyType.integer));
      final encoded = encodeCatalog(catalog);
      final raw = jsonDecode(encoded) as Map<String, dynamic>;
      final property = _wireProperties(raw).single;

      expect(property, isNot(contains('constraints')));
      expect(encodeCatalog(decodeCatalog(encoded)), encoded);
    });

    test('recognized keys never leak into extensions on decode', () {
      final encoded = encodeCatalog(
        _catalog(
          _property(
            type: PropertyType.integer,
            constraints: const RestageConstraints(minimum: 1),
          ),
        ),
      );
      final decoded = decodeCatalog(encoded);
      final constraints = decoded.widgets.single.properties.single.constraints;

      expect(constraints.minimum, 1);
      expect(constraints.extensions, isEmpty);
    });
  });

  group('constraints validation', () {
    void expectRejected(
      RestageConstraints constraints, {
      PropertyType type = PropertyType.real,
      CatalogValueShape? valueShape,
      String? message,
    }) {
      expect(
        () => encodeCatalog(
          _catalog(
            _property(
              type: type,
              constraints: constraints,
              valueShape: valueShape,
            ),
          ),
        ),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            message == null ? isNotEmpty : contains(message),
          ),
        ),
      );
    }

    Matcher itemConstraintRejection(PropertyType type) =>
        isA<CatalogSchemaException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('item constraints require a proven data-list type'),
            contains('PropertyType.${type.name}'),
          ),
        );

    test('rejects invalid structural values and combinations', () {
      expectRejected(
        const RestageConstraints(minimum: 1, exclusiveMinimum: 2),
        message: 'minimum',
      );
      expectRejected(
        const RestageConstraints(maximum: 1, exclusiveMaximum: 2),
        message: 'maximum',
      );
      expectRejected(
        const RestageConstraints(minimum: 3, maximum: 2),
        message: 'contradictory',
      );
      expectRejected(
        const RestageConstraints(exclusiveMinimum: 2, maximum: 2),
        message: 'contradictory',
      );
      expectRejected(
        const RestageConstraints(minimum: double.nan),
        message: 'finite',
      );
      expectRejected(
        const RestageConstraints(maximum: double.infinity),
        message: 'finite',
      );
      expectRejected(
        const RestageConstraints(allowedValues: [double.infinity]),
        message: 'finite',
      );
      expectRejected(
        const RestageConstraints(allowedValues: []),
        message: 'must not be empty',
      );
      expectRejected(
        const RestageConstraints(allowedValues: [1, 1.0]),
        message: 'duplicate',
      );
      expectRejected(
        const RestageConstraints(allowedValues: [<String, Object?>{}]),
        message: 'JSON scalar',
      );
      expectRejected(
        const RestageConstraints(minLength: -1),
        type: PropertyType.string,
        message: 'non-negative',
      );
      expectRejected(
        const RestageConstraints(minLength: 3, maxLength: 2),
        type: PropertyType.string,
        message: 'minLength',
      );
      expectRejected(
        const RestageConstraints(minItems: 3, maxItems: 2),
        type: PropertyType.stringList,
        message: 'minItems',
      );
    });

    test(
      'rejects extensions that are unsafe or collide with known keywords',
      () {
        expectRejected(
          RestageConstraints.withExtensions(
            extensions: const {'minimum': 1},
          ),
          message: 'collides',
        );
        expectRejected(
          RestageConstraints.withExtensions(
            extensions: const {'x-nonfinite': double.infinity},
          ),
          message: 'finite',
        );
        expectRejected(
          RestageConstraints.withExtensions(
            extensions: const {
              'x-invalid': {1: 'not a JSON object'},
            },
          ),
          message: 'string keys',
        );
        expectRejected(
          RestageConstraints.withExtensions(
            extensions: {'x-invalid': DateTime.utc(2026)},
          ),
          message: 'JSON-safe',
        );
      },
    );

    test('rejects typed constraints outside their proven property family', () {
      expectRejected(
        const RestageConstraints(minimum: 1),
        type: PropertyType.string,
        message: 'numeric constraints',
      );
      expectRejected(
        const RestageConstraints(pattern: r'^[a-z]+$'),
        type: PropertyType.integer,
        message: 'string constraints',
      );
      expectRejected(
        const RestageConstraints(minItems: 1),
        type: PropertyType.widgetList,
        message: 'item constraints',
      );
      expectRejected(
        const RestageConstraints(minItems: 1),
        type: PropertyType.unknown,
        message: 'item constraints',
      );
      expectRejected(
        const RestageConstraints(allowedValues: [1]),
        type: PropertyType.boolean,
        message: 'allowedValues[0]',
      );
      expectRejected(
        const RestageConstraints(allowedValues: [1.5]),
        type: PropertyType.integer,
        message: 'allowedValues[0]',
      );
      expectRejected(
        const RestageConstraints(allowedValues: ['blue']),
        message: 'allowedValues[0]',
      );
      expectRejected(
        const RestageConstraints(allowedValues: [true]),
        type: PropertyType.color,
        message: 'allowedValues[0]',
      );
      expectRejected(
        const RestageConstraints(allowedValues: [null]),
        type: PropertyType.event,
        message: 'allowedValues',
      );
    });

    test('accepts the frozen scalar families', () {
      for (final (type, value) in <(PropertyType, Object?)>[
        (PropertyType.boolean, true),
        (PropertyType.integer, 2),
        (PropertyType.real, 2.5),
        (PropertyType.length, 2),
        (PropertyType.duration, 200),
        (PropertyType.fontWeight, 500),
        (PropertyType.string, 'value'),
        (PropertyType.color, '#FF00FF'),
        (PropertyType.enumValue, 'start'),
      ]) {
        expect(
          () => encodeCatalog(
            _catalog(
              _property(
                type: type,
                constraints: RestageConstraints(allowedValues: [value, null]),
                enumType: type == PropertyType.enumValue ? 'TextAlign' : null,
              ),
            ),
          ),
          returnsNormally,
          reason: 'PropertyType.${type.name}',
        );
      }
    });

    test('round trips every accepted named data-list family and ListShape', () {
      const constraints = RestageConstraints(minItems: 1, maxItems: 3);
      final opaqueStructuredList = ListShape.opaqueStructured(
        WireIdRef(
          library: 'restage.core',
          wireId: WireId('s0001'),
        ),
      );
      expect(opaqueStructuredList.isOpaqueStructuredList, isTrue);

      for (final (type, valueShape) in <(PropertyType, CatalogValueShape?)>[
        (
          PropertyType.stringList,
          const ListShape(
            propertyType: PropertyType.stringList,
            itemShape: ScalarShape(propertyType: PropertyType.string),
          ),
        ),
        (PropertyType.booleanList, null),
        (PropertyType.boxShadowList, null),
        (PropertyType.shadowList, null),
        (PropertyType.fontFeatureList, null),
        (PropertyType.fontVariationList, null),
        (PropertyType.selectionOptionList, null),
        (PropertyType.unknown, opaqueStructuredList),
      ]) {
        final source = encodeCatalog(
          _catalog(
            _property(
              type: type,
              constraints: constraints,
              valueShape: valueShape,
            ),
          ),
        );
        final raw = jsonDecode(source) as Map<String, dynamic>;
        final wireConstraints =
            _wireProperties(raw).single['constraints']! as Map<String, dynamic>;

        expect(
          wireConstraints.keys,
          ['minItems', 'maxItems'],
          reason: 'PropertyType.${type.name}',
        );
        final decoded = decodeCatalog(source);
        final decodedProperty = decoded.widgets.single.properties.single;
        expect(
          decodedProperty.constraints,
          constraints,
          reason: 'PropertyType.${type.name}',
        );
        expect(
          decodedProperty.valueShape,
          valueShape,
          reason: 'PropertyType.${type.name}',
        );
        expect(
          encodeCatalog(decoded),
          source,
          reason: 'PropertyType.${type.name}',
        );
      }
    });

    test('rejects item constraints for unproven outer type and shape pairs',
        () {
      const dataListShape = ListShape(
        propertyType: PropertyType.stringList,
        itemShape: ScalarShape(propertyType: PropertyType.string),
      );
      const widgetListShape = ListShape(
        propertyType: PropertyType.widgetList,
        itemShape: ScalarShape(propertyType: PropertyType.widget),
      );

      for (final (type, valueShape) in <(PropertyType, CatalogValueShape)>[
        (PropertyType.event, dataListShape),
        (PropertyType.string, dataListShape),
        (PropertyType.unknown, widgetListShape),
      ]) {
        expect(
          () => encodeCatalog(
            _catalog(
              _property(
                type: type,
                constraints: const RestageConstraints(minItems: 1),
                valueShape: valueShape,
              ),
            ),
          ),
          throwsA(itemConstraintRejection(type)),
          reason: 'PropertyType.${type.name}',
        );
      }
    });

    test('rejects a simultaneous legacy rule and typed constraints', () {
      expect(
        () => encodeCatalog(
          _catalog(
            _property(
              type: PropertyType.integer,
              constraints: const RestageConstraints(minimum: 1),
              validationRule: const ValidationExpr(
                expression: 'range(1, 10)',
                message: 'Must be between 1 and 10.',
              ),
            ),
          ),
        ),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            allOf(contains('validationRule'), contains('constraints')),
          ),
        ),
      );
    });

    test('malformed wire values fail through CatalogSchemaException', () {
      final source = encodeCatalog(
        _catalog(
          _property(
            type: PropertyType.integer,
            constraints: const RestageConstraints(minimum: 1),
          ),
        ),
      );
      final raw = jsonDecode(source) as Map<String, dynamic>;
      final property = _wireProperties(raw).single;
      property['constraints'] = {
        'minimum': 'not-a-number',
        'enum': 'not-a-list',
      };

      expect(
        () => decodeCatalog(jsonEncode(raw)),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('semantic-invalid wire constraints are rejected during decode', () {
      void expectWireRejected(
        Map<String, Object?> constraints, {
        PropertyType type = PropertyType.real,
        ValidationExpr? validationRule,
        String? message,
      }) {
        final raw = jsonDecode(
          encodeCatalog(
            _catalog(
              _property(
                type: type,
                validationRule: validationRule,
              ),
            ),
          ),
        ) as Map<String, dynamic>;
        final property = _wireProperties(raw).single;
        property['constraints'] = constraints;
        expect(
          () => decodeCatalog(jsonEncode(raw)),
          throwsA(
            isA<CatalogSchemaException>().having(
              (error) => error.message,
              'message',
              message == null ? isNotEmpty : contains(message),
            ),
          ),
        );
      }

      expectWireRejected(
        {'minimum': 1, 'exclusiveMinimum': 2},
        message: 'mutually exclusive',
      );
      expectWireRejected(
        {'minimum': 3, 'maximum': 2},
        message: 'contradictory',
      );
      expectWireRejected(
        {'enum': <Object?>[]},
        message: 'must not be empty',
      );
      expectWireRejected(
        {
          'enum': [1, 1.0],
        },
        message: 'duplicate',
      );
      expectWireRejected(
        {'minimum': 1},
        type: PropertyType.string,
        message: 'numeric constraints',
      );
      expectWireRejected(
        {'minimum': 1},
        validationRule: const ValidationExpr(
          expression: 'range(1, 10)',
          message: 'Must be between 1 and 10.',
        ),
        message: 'mutually exclusive',
      );
    });

    test('crafted wire cannot pair item constraints with an outer scalar', () {
      const type = PropertyType.event;
      final raw = jsonDecode(
        encodeCatalog(
          _catalog(
            _property(
              type: type,
              valueShape: const ListShape(
                propertyType: PropertyType.stringList,
                itemShape: ScalarShape(propertyType: PropertyType.string),
              ),
            ),
          ),
        ),
      ) as Map<String, dynamic>;
      _wireProperties(raw).single['constraints'] = {'minItems': 1};

      expect(
        () => decodeCatalog(jsonEncode(raw)),
        throwsA(itemConstraintRejection(type)),
      );
    });

    test('present-null known wire keywords are malformed, not absent', () {
      for (final keyword in [
        'minimum',
        'pattern',
        'minLength',
        'enum',
      ]) {
        final type = switch (keyword) {
          'minimum' => PropertyType.real,
          'pattern' || 'minLength' => PropertyType.string,
          'enum' => PropertyType.boolean,
          _ => throw StateError('unreachable'),
        };
        final raw = jsonDecode(
          encodeCatalog(_catalog(_property(type: type))),
        ) as Map<String, dynamic>;
        final property = _wireProperties(raw).single;
        property['constraints'] = {keyword: null};

        expect(
          () => decodeCatalog(jsonEncode(raw)),
          throwsA(
            isA<CatalogSchemaException>().having(
              (error) => error.message,
              'message',
              contains(keyword),
            ),
          ),
          reason: keyword,
        );
      }

      final raw = jsonDecode(
        encodeCatalog(_catalog(_property(type: PropertyType.real))),
      ) as Map<String, dynamic>;
      final property = _wireProperties(raw).single;
      property['constraints'] = null;
      expect(
        () => decodeCatalog(jsonEncode(raw)),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('non-finite unknown extension data is rejected during decode', () {
      final raw = jsonDecode(
        encodeCatalog(_catalog(_property(type: PropertyType.real))),
      ) as Map<String, dynamic>;
      final property = _wireProperties(raw).single;
      property['constraints'] = {'x-beyond': 1};
      final source = jsonEncode(raw).replaceFirst(
        '"x-beyond":1',
        '"x-beyond":1e999',
      );

      expect(
        () => decodeCatalog(source),
        throwsA(isA<CatalogSchemaException>()),
      );
    });
  });
}

PropertyEntry _property({
  required PropertyType type,
  String wireId = 'p0001',
  String name = 'value',
  RestageConstraints constraints = RestageConstraints.empty,
  CatalogValueShape? valueShape,
  String? enumType,
  ValidationExpr? validationRule,
}) =>
    PropertyEntry(
      wireId: WireId(wireId),
      name: name,
      type: type,
      description: 'Value.',
      enumType: enumType,
      constraints: constraints,
      valueShape: valueShape,
      validationRule: validationRule,
    );

List<Map<String, dynamic>> _wireProperties(Map<String, dynamic> catalog) {
  final widgets =
      (catalog['widgets']! as List<Object?>).cast<Map<String, dynamic>>();
  return (widgets.single['properties']! as List<Object?>)
      .cast<Map<String, dynamic>>();
}

Catalog _catalog(PropertyEntry property) => _catalogWithProperties([property]);

Catalog _catalogWithProperties(List<PropertyEntry> properties) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-07-19T00:00:00.000Z',
      libraries: {
        WidgetLibrary.core: const LibraryInfo(version: '1.0.0'),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'ConstraintFixture',
          library: WidgetLibrary.core,
          category: WidgetCategory.input,
          description: 'Constraint fixture.',
          flutterType: 'package:fixture/fixture.dart#ConstraintFixture',
          childrenSlot: ChildrenSlot.none,
          properties: properties,
        ),
      ],
    );
