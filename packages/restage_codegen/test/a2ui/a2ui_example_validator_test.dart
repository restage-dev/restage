import 'package:build/build.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_example_loader.dart';
import 'package:restage_codegen/src/a2ui/a2ui_example_validator.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const _library = WidgetLibrary.custom('acme.widgets');

PropertyEntry _property(
  String name,
  PropertyType type, {
  bool required = false,
  String description = '',
  RestageConstraints constraints = RestageConstraints.empty,
}) =>
    PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: name,
      type: type,
      description: description,
      required: required,
      constraints: constraints,
    );

WidgetEntry _widget(
  String name,
  List<PropertyEntry> properties, {
  WidgetLibrary library = _library,
}) =>
    WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: name,
      library: library,
      category: WidgetCategory.layout,
      description: '',
      flutterType: 'package:fixture/$name.dart#$name',
      childrenSlot: ChildrenSlot.none,
      fires: const [],
      properties: properties,
    );

A2uiDartCatalogPlan _plan(
  List<WidgetEntry> widgets, {
  A2uiRichShapes? richShapes,
  A2uiEventSeam? eventSeam,
  A2uiPairingSeam? pairingSeam,
}) =>
    classifyA2uiCatalogDart(
      Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          for (final widget in widgets)
            widget.library:
                const LibraryInfo(version: '0.0.0', capabilityVersion: 1),
        },
        widgets: widgets,
      ),
      richShapes: richShapes,
      eventSeam: eventSeam,
      pairingSeam: pairingSeam,
    );

LoadedA2uiExample _example(
  String widgetName,
  List<Map<String, Object?>> components,
) =>
    LoadedA2uiExample(
      anchor: A2uiExampleSourceAnchor(
        sourceClass: '${widgetName}Source',
        widgetName: widgetName,
        exampleName: 'Boundary',
        asset: 'lib/a2ui_examples/$widgetName/boundary.json',
      ),
      assetId: AssetId(
        'customer_app',
        'lib/a2ui_examples/$widgetName/boundary.json',
      ),
      components: components,
    );

ValidatedA2uiExample _validate(
  A2uiDartCatalogPlan plan,
  String widgetName,
  List<Map<String, Object?>> components,
) =>
    validateA2uiExamples(
      plan: plan,
      examples: [_example(widgetName, components)],
    ).single;

void _expectFailure(
  A2uiDartCatalogPlan plan,
  String widgetName,
  List<Map<String, Object?>> components,
  List<String> fragments,
) {
  expect(
    () => _validate(plan, widgetName, components),
    throwsA(
      isA<A2uiExampleException>().having(
        (error) => error.toString(),
        'diagnostic',
        predicate<String>(
          (message) => fragments.every(message.contains),
          'contains ${fragments.join(', ')}',
        ),
      ),
    ),
  );
}

A2uiDartCatalogPlan _graphPlan() => _plan([
      _widget('RootCard', [
        _property('label', PropertyType.string),
        _property('child', PropertyType.widget, required: true),
        _property('children', PropertyType.widgetList),
      ]),
      _widget('Branch', [_property('child', PropertyType.widget)]),
      _widget('Leaf', [_property('label', PropertyType.string)]),
    ]);

List<Map<String, Object?>> _validGraph() => [
      {
        'id': 'root',
        'component': 'RootCard',
        'label': 'not-an-edge',
        'child': 'leaf',
      },
      {'id': 'leaf', 'component': 'Leaf', 'label': 'Leaf'},
    ];

const _recursiveId = 'package:fixture/schema.dart#RecursiveValue';

A2uiDartCatalogPlan _schemaPlan() {
  final recursive = ObjectNode(
    defId: _recursiveId,
    fields: const {
      'label': ScalarNode(A2uiScalarType.string),
      'next': RefNode(_recursiveId, nullable: true),
    },
    required: const {'label', 'next'},
  );
  return _plan(
    [
      _widget('SchemaCard', [
        _property('integer', PropertyType.integer, required: true),
        _property('number', PropertyType.real, required: true),
        _property('enabled', PropertyType.boolean, required: true),
        _property('mode', PropertyType.enumValue, required: true),
        _property('details', PropertyType.structured, required: true),
        _property('rows', PropertyType.structured, required: true),
        _property('metrics', PropertyType.structured, required: true),
        _property('recursive', PropertyType.structured, required: true),
        _property('nullableText', PropertyType.string, required: true),
        _property('optionalText', PropertyType.string),
      ]),
    ],
    richShapes: {
      ('SchemaCard', 'integer'): const ScalarNode(A2uiScalarType.integer),
      ('SchemaCard', 'mode'): EnumNode(
        members: const ['compact', 'expanded'],
        dartTypeName: 'DisplayMode',
      ),
      ('SchemaCard', 'details'): ObjectNode(
        fields: const {
          'name': ScalarNode(A2uiScalarType.string),
          'note': ScalarNode(A2uiScalarType.string, nullable: true),
        },
        required: const {'name'},
      ),
      ('SchemaCard', 'rows'): ListNode(
        element: ObjectNode(
          fields: const {'value': ScalarNode(A2uiScalarType.integer)},
          required: const {'value'},
        ),
      ),
      ('SchemaCard', 'metrics'):
          const MapNode(valueType: ScalarNode(A2uiScalarType.integer)),
      ('SchemaCard', 'recursive'): recursive,
      ('SchemaCard', 'nullableText'):
          const ScalarNode(A2uiScalarType.string, nullable: true),
    },
  );
}

List<Map<String, Object?>> _validSchemaPayload() => [
      {
        'id': 'root',
        'component': 'SchemaCard',
        'integer': 2,
        'number': 2.5,
        'enabled': true,
        'mode': 'compact',
        'details': {'name': 'Plan', 'note': null},
        'rows': [
          {'value': 1},
        ],
        'metrics': {'first': 1, 'second': 2},
        'recursive': {
          'label': 'first',
          'next': {'label': 'second', 'next': null},
        },
        'nullableText': null,
      },
    ];

A2uiDartCatalogPlan _constraintPlan() => _plan(
      [
        _widget('ConstraintCard', [
          _property(
            'minimum',
            PropertyType.real,
            required: true,
            constraints: const RestageConstraints(minimum: 1),
          ),
          _property(
            'exclusiveMinimum',
            PropertyType.real,
            required: true,
            constraints: const RestageConstraints(exclusiveMinimum: 1),
          ),
          _property(
            'maximum',
            PropertyType.real,
            required: true,
            constraints: const RestageConstraints(maximum: 10),
          ),
          _property(
            'exclusiveMaximum',
            PropertyType.real,
            required: true,
            constraints: const RestageConstraints(exclusiveMaximum: 10),
          ),
          _property(
            'allowedNumber',
            PropertyType.real,
            required: true,
            constraints: const RestageConstraints(allowedValues: [1]),
          ),
          _property(
            'pattern',
            PropertyType.string,
            required: true,
            constraints: const RestageConstraints(pattern: r'^[A-Z]+$'),
          ),
          _property(
            'unicodeLength',
            PropertyType.string,
            required: true,
            constraints: const RestageConstraints(minLength: 2, maxLength: 2),
          ),
          _property(
            'items',
            PropertyType.structured,
            required: true,
            constraints: const RestageConstraints(minItems: 1, maxItems: 2),
          ),
          _property(
            'nullableConstrained',
            PropertyType.string,
            required: true,
            constraints: const RestageConstraints(minLength: 2),
          ),
        ]),
      ],
      richShapes: const {
        ('ConstraintCard', 'items'):
            ListNode(element: ScalarNode(A2uiScalarType.integer)),
        ('ConstraintCard', 'nullableConstrained'):
            ScalarNode(A2uiScalarType.string, nullable: true),
      },
    );

Map<String, Object?> _validConstraints() => {
      'id': 'root',
      'component': 'ConstraintCard',
      'minimum': 1,
      'exclusiveMinimum': 1.1,
      'maximum': 10,
      'exclusiveMaximum': 9.9,
      'allowedNumber': 1.0,
      'pattern': 'ABC',
      'unicodeLength': '😀a',
      'items': [1, 2],
      'nullableConstrained': null,
    };

A2uiDartCatalogPlan _referencePlan() => _plan(
      [
        _widget('ReferenceCard', [
          _property('controlled', PropertyType.string, required: true),
          _property('onControlled', PropertyType.event, required: true),
          _property('mode', PropertyType.enumValue, required: true),
          _property('onMode', PropertyType.event, required: true),
          _property('tags', PropertyType.structured, required: true),
          _property('metadata', PropertyType.structured, required: true),
          _property('labels', PropertyType.structured, required: true),
        ]),
      ],
      richShapes: {
        ('ReferenceCard', 'mode'): EnumNode(
          members: const ['compact', 'expanded'],
          dartTypeName: 'DisplayMode',
        ),
        ('ReferenceCard', 'tags'):
            const ListNode(element: ScalarNode(A2uiScalarType.string)),
        ('ReferenceCard', 'metadata'): ObjectNode(
          fields: const {
            'path': ScalarNode(A2uiScalarType.string),
            'call': ScalarNode(A2uiScalarType.string),
          },
          required: const {'path', 'call'},
        ),
        ('ReferenceCard', 'labels'):
            const MapNode(valueType: ScalarNode(A2uiScalarType.string)),
      },
      eventSeam: const {
        ('ReferenceCard', 'onControlled'): A2uiCallbackWriteBack(
          A2uiScalarType.string,
          nullable: false,
          isList: false,
        ),
        ('ReferenceCard', 'onMode'): A2uiCallbackWriteBack(
          A2uiScalarType.string,
          nullable: false,
          isList: false,
        ),
      },
      pairingSeam: const {
        ('ReferenceCard', 'onControlled'): 'controlled',
        ('ReferenceCard', 'onMode'): 'mode',
      },
    );

Map<String, Object?> _validReferences() => {
      'id': 'root',
      'component': 'ReferenceCard',
      'controlled': 'literal',
      'mode': 'compact',
      'tags': ['one', 'two'],
      'metadata': {'path': 'literal path', 'call': 'literal call'},
      'labels': {'path': 'literal path', 'call': 'literal call'},
    };

A2uiDartCatalogPlan _completeIrPlan(A2uiSchemaNode node) => _plan(
      [
        _widget('CompleteIrCard', [
          _property('value', PropertyType.structured),
        ]),
      ],
      richShapes: {('CompleteIrCard', 'value'): node},
    );

A2uiDartCatalogPlan _definitionKeyCollisionPlan() {
  const aId = 'package:a/a.dart#Node';
  const bId = 'package:b/b.dart#Node';
  final a = ObjectNode(
    defId: aId,
    fields: const {
      'value': ScalarNode(A2uiScalarType.string),
      'self': RefNode(aId, nullable: true),
    },
    required: const {'value', 'self'},
  );
  final b = ObjectNode(
    defId: bId,
    fields: const {
      'value': ScalarNode(A2uiScalarType.integer),
      'self': RefNode(bId, nullable: true),
    },
    required: const {'value', 'self'},
  );
  return _plan(
    [
      _widget('DefinitionCollisionCard', [
        _property('a', PropertyType.structured, required: true),
        _property('b', PropertyType.structured, required: true),
      ]),
    ],
    richShapes: {
      ('DefinitionCollisionCard', 'a'): a,
      ('DefinitionCollisionCard', 'b'): b,
    },
  );
}

A2uiDartCatalogPlan _descriptionSeparationPlan() => _plan(
      [
        _widget('DescriptionSeparationCard', [
          _property(
            'details',
            PropertyType.structured,
            required: true,
            description: 'Details for this component.',
          ),
        ]),
      ],
      richShapes: {
        ('DescriptionSeparationCard', 'details'): ObjectNode(
          defId: 'package:fixture/details.dart#Details',
          definitionDescription: 'Canonical details.',
          fields: const {
            'count': ScalarNode(A2uiScalarType.integer),
          },
          required: const {'count'},
        ),
      },
    );

void main() {
  group('component envelope and custom-only membership', () {
    test('accepts one exact custom-only root graph', () {
      expect(_validate(_graphPlan(), 'RootCard', _validGraph()), isNotNull);
    });

    test('rejects duplicate component IDs including duplicate root forms', () {
      _expectFailure(
        _graphPlan(),
        'RootCard',
        [
          ..._validGraph(),
          {'id': 'root', 'component': 'Leaf'},
        ],
        ['duplicate component ID "root"', '/2/id', '/componentGraph/ids'],
      );
    });

    test('rejects an empty component ID as a graph invariant', () {
      _expectFailure(
        _graphPlan(),
        'RootCard',
        [
          ..._validGraph(),
          {'id': '', 'component': 'Leaf'},
        ],
        ['component ID must be non-empty', '/2/id', '/componentGraph/ids'],
      );
    });

    test('rejects a graph with no root', () {
      _expectFailure(
        _graphPlan(),
        'RootCard',
        [
          {'id': 'other', 'component': 'Leaf'},
        ],
        ['exactly one component ID "root"', '/componentGraph/root'],
      );
    });

    test('rejects a root whose component differs from the annotation', () {
      _expectFailure(
        _graphPlan(),
        'RootCard',
        [
          {'id': 'root', 'component': 'Leaf'},
        ],
        ['component "root"', 'RootCard', 'Leaf', '/0/component'],
      );
    });

    for (final type in const ['UnknownCard', 'Text']) {
      test('rejects non-custom component type $type', () {
        final components = _validGraph();
        components[1] = {'id': 'leaf', 'component': type};
        _expectFailure(
          _graphPlan(),
          'RootCard',
          components,
          ['component "leaf"', type, 'generated custom-only catalog'],
        );
      });
    }

    test('rejects duplicate flat component names before building the lookup',
        () {
      const otherLibrary = WidgetLibrary.custom('other.widgets');
      final plan = _plan([
        _widget('DuplicateCard', const []),
        _widget(
          'DuplicateCard',
          [_property('count', PropertyType.integer, required: true)],
          library: otherLibrary,
        ),
      ]);

      _expectFailure(
        plan,
        'DuplicateCard',
        [
          {'id': 'root', 'component': 'DuplicateCard', 'count': 1},
        ],
        [
          'duplicate catalog plan component name "DuplicateCard"',
          'acme.widgets',
          'other.widgets',
          'schema path "/components/DuplicateCard"',
        ],
      );
    });
  });

  group('complete schema IR preflight', () {
    final nullableUnion = UnionNode(
      variants: const [ScalarNode(A2uiScalarType.string)],
      discriminatorField: 'type',
      nullable: true,
    );

    test('rejects an absent optional UnionNode before payload validation', () {
      _expectFailure(
        _completeIrPlan(nullableUnion),
        'CompleteIrCard',
        [
          {'id': 'root', 'component': 'CompleteIrCard'},
        ],
        ['UnionNode has no emitted A2UI schema projection', '/value'],
      );
    });

    test('rejects a null nullable UnionNode before its null branch', () {
      _expectFailure(
        _completeIrPlan(nullableUnion),
        'CompleteIrCard',
        [
          {'id': 'root', 'component': 'CompleteIrCard', 'value': null},
        ],
        ['UnionNode has no emitted A2UI schema projection', '/value'],
      );
    });

    for (final payload in <Map<String, Object?>>[
      {'id': 'root', 'component': 'CompleteIrCard'},
      {'id': 'root', 'component': 'CompleteIrCard', 'value': null},
    ]) {
      test('rejects an unresolved optional/nullable RefNode for $payload', () {
        _expectFailure(
          _completeIrPlan(
            const RefNode(
              'package:missing/missing.dart#MissingValue',
              nullable: true,
            ),
          ),
          'CompleteIrCard',
          [payload],
          [
            'has no canonical definition',
            r'/components/CompleteIrCard/$defs/MissingValue',
          ],
        );
      });
    }
  });

  group('schema IR validation', () {
    test('accepts scalar/enum/object/list/map/ref/nullable and optional fields',
        () {
      expect(
        _validate(_schemaPlan(), 'SchemaCard', _validSchemaPayload()),
        isNotNull,
      );
    });

    test('accepts an integral double for an integer schema', () {
      final payload = _validSchemaPayload();
      payload.single['integer'] = 2.0;
      expect(_validate(_schemaPlan(), 'SchemaCard', payload), isNotNull);
    });

    final failures = <String, (String field, Object? value, String message)>{
      'fractional integer': ('integer', 2.5, 'expected JSON integer'),
      'number type': ('number', '2.5', 'expected finite JSON number'),
      'boolean type': ('enabled', 1, 'expected JSON boolean'),
      'enum member': ('mode', 'unknown', 'resolved enum member'),
      'object type': ('details', <Object?>[], 'expected JSON object'),
      'list type': ('rows', <String, Object?>{}, 'expected JSON array'),
      'map type': ('metrics', <Object?>[], 'expected JSON object'),
      'nullable non-null type': ('nullableText', 3, 'expected JSON string'),
    };
    for (final entry in failures.entries) {
      test('rejects ${entry.key}', () {
        final payload = _validSchemaPayload();
        payload.single[entry.value.$1] = entry.value.$2;
        _expectFailure(
          _schemaPlan(),
          'SchemaCard',
          payload,
          [entry.value.$3, '/0/${entry.value.$1}'],
        );
      });
    }

    test('rejects a missing required component property', () {
      final payload = _validSchemaPayload();
      payload.single.remove('integer');
      _expectFailure(
        _schemaPlan(),
        'SchemaCard',
        payload,
        ['required property is missing', '/0/integer', '/integer'],
      );
    });

    test('rejects a missing required nested object property', () {
      final payload = _validSchemaPayload();
      payload.single['details'] = <String, Object?>{'note': 'optional'};
      _expectFailure(
        _schemaPlan(),
        'SchemaCard',
        payload,
        ['required property is missing', '/0/details/name', '/details/name'],
      );
    });

    test('accepts unknown ObjectNode keys because emitted objects stay open',
        () {
      final payload = _validSchemaPayload();
      payload.single['details'] = {
        'name': 'Plan',
        'unknown': {'anything': true},
      };
      expect(_validate(_schemaPlan(), 'SchemaCard', payload), isNotNull);
    });

    test('validates every MapNode additional property value', () {
      final payload = _validSchemaPayload();
      payload.single['metrics'] = {'first': 1, 'bad': 1.5};
      _expectFailure(
        _schemaPlan(),
        'SchemaCard',
        payload,
        [
          'expected JSON integer',
          '/0/metrics/bad',
          '/metrics/additionalProperties',
        ],
      );
    });

    test('validates lists and recursive definitions transitively', () {
      final payload = _validSchemaPayload();
      payload.single['recursive'] = {
        'label': 'first',
        'next': {'label': 2, 'next': null},
      };
      _expectFailure(
        _schemaPlan(),
        'SchemaCard',
        payload,
        ['expected JSON string', '/recursive/next/label', r'/$defs/'],
      );
    });
  });

  group('exact normalized constraint semantics', () {
    test('accepts every inclusive boundary, deep numeric enum, and nullable',
        () {
      expect(
        _validate(
          _constraintPlan(),
          'ConstraintCard',
          [_validConstraints()],
        ),
        isNotNull,
      );
    });

    final failures = <String, (String field, Object? value, String keyword)>{
      'minimum': ('minimum', 0.5, 'minimum'),
      'exclusiveMinimum': ('exclusiveMinimum', 1, 'exclusiveMinimum'),
      'maximum': ('maximum', 10.5, 'maximum'),
      'exclusiveMaximum': ('exclusiveMaximum', 10, 'exclusiveMaximum'),
      'allowed-values enum': ('allowedNumber', 2, 'enum'),
      'pattern search': ('pattern', 'Ab', 'pattern'),
      'minLength in Unicode code points': ('unicodeLength', '😀', 'minLength'),
      'maxLength in Unicode code points': (
        'unicodeLength',
        '😀ab',
        'maxLength'
      ),
      'minItems': ('items', <Object?>[], 'minItems'),
      'maxItems': ('items', <Object?>[1, 2, 3], 'maxItems'),
      'constraints on a non-null nullable literal': (
        'nullableConstrained',
        'x',
        'minLength'
      ),
    };
    for (final entry in failures.entries) {
      test('rejects ${entry.key}', () {
        final payload = _validConstraints();
        payload[entry.value.$1] = entry.value.$2;
        _expectFailure(
          _constraintPlan(),
          'ConstraintCard',
          [payload],
          [entry.value.$3, '/0/${entry.value.$1}'],
        );
      });
    }
  });

  group('classified value-reference roots', () {
    for (final field in const ['controlled', 'mode', 'tags']) {
      for (final arm in const ['path', 'call']) {
        test('rejects {$arm} at reference-capable $field root', () {
          final payload = _validReferences();
          payload[field] = {arm: 'deferred'};
          _expectFailure(
            _referencePlan(),
            'ReferenceCard',
            [payload],
            [
              'deferred {$arm} value references are not canonical literals',
              '/0/$field',
            ],
          );
        });
      }
    }

    test('accepts literal path/call keys in non-reference rich object and map',
        () {
      expect(
        _validate(
          _referencePlan(),
          'ReferenceCard',
          [_validReferences()],
        ),
        isNotNull,
      );
    });
  });

  group('child graph integrity', () {
    test('random data strings are not graph edges', () {
      final components = _validGraph();
      components.first['label'] = 'missing-component-id';
      expect(_validate(_graphPlan(), 'RootCard', components), isNotNull);
    });

    test('rejects a missing single child target', () {
      final components = _validGraph();
      components.first['child'] = 'missing';
      _expectFailure(
        _graphPlan(),
        'RootCard',
        components,
        ['child target "missing" does not exist', '/0/child'],
      );
    });

    test('rejects a missing child from a children list', () {
      final components = _validGraph();
      components.first['children'] = ['leaf', 'missing'];
      _expectFailure(
        _graphPlan(),
        'RootCard',
        components,
        ['child target "missing" does not exist', '/0/children/1'],
      );
    });

    test('rejects a direct self-cycle', () {
      final components = _validGraph();
      components.first['child'] = 'root';
      _expectFailure(
        _graphPlan(),
        'RootCard',
        components,
        ['component graph cycle', 'root -> root'],
      );
    });

    test('rejects a two-node cycle', () {
      final components = <Map<String, Object?>>[
        {'id': 'root', 'component': 'RootCard', 'child': 'branch'},
        {'id': 'branch', 'component': 'Branch', 'child': 'root'},
      ];
      _expectFailure(
        _graphPlan(),
        'RootCard',
        components,
        ['component graph cycle', 'root -> branch -> root'],
      );
    });

    test('rejects a deeper cycle', () {
      final components = <Map<String, Object?>>[
        {'id': 'root', 'component': 'RootCard', 'child': 'first'},
        {'id': 'first', 'component': 'Branch', 'child': 'second'},
        {'id': 'second', 'component': 'Branch', 'child': 'root'},
      ];
      _expectFailure(
        _graphPlan(),
        'RootCard',
        components,
        ['component graph cycle', 'root -> first -> second -> root'],
      );
    });

    test('rejects an unreachable singleton', () {
      _expectFailure(
        _graphPlan(),
        'RootCard',
        [
          ..._validGraph(),
          {'id': 'orphan', 'component': 'Leaf'},
        ],
        ['unreachable from "root"', 'orphan'],
      );
    });

    test('rejects an unreachable subgraph', () {
      _expectFailure(
        _graphPlan(),
        'RootCard',
        [
          ..._validGraph(),
          {
            'id': 'orphan-branch',
            'component': 'Branch',
            'child': 'orphan-leaf',
          },
          {'id': 'orphan-leaf', 'component': 'Leaf'},
        ],
        ['unreachable from "root"', 'orphan-branch', 'orphan-leaf'],
      );
    });
  });

  group('deterministic canonical JSON', () {
    final openPlan = _plan([_widget('OpenCard', const [])]);

    test('sorts every object key with no whitespace and preserves number kinds',
        () {
      final validated = _validate(openPlan, 'OpenCard', [
        {
          'z': 2.0,
          'id': 'root',
          'metadata': {
            'z': 1,
            'a': [
              {'z': 2, 'a': 1},
            ],
          },
          'component': 'OpenCard',
          'a': 1,
        },
      ]);

      expect(
        validated.canonicalJson,
        '[{"a":1,"component":"OpenCard","id":"root",'
        '"metadata":{"a":[{"a":1,"z":2}],"z":1},"z":2.0}]',
      );
    });

    test('object key order is neutral but numeric kind remains significant',
        () {
      final first = _validate(openPlan, 'OpenCard', [
        {'id': 'root', 'component': 'OpenCard', 'b': 2, 'a': 1},
      ]);
      final reordered = _validate(openPlan, 'OpenCard', [
        {'a': 1, 'component': 'OpenCard', 'id': 'root', 'b': 2},
      ]);
      final doubleKind = _validate(openPlan, 'OpenCard', [
        {'id': 'root', 'component': 'OpenCard', 'b': 2.0, 'a': 1},
      ]);

      expect(reordered.canonicalJson, first.canonicalJson);
      expect(doubleKind.canonicalJson, isNot(first.canonicalJson));
    });

    test('preserves component-array order', () {
      final first = _validate(_graphPlan(), 'RootCard', [
        {
          'id': 'root',
          'component': 'RootCard',
          'child': 'a',
          'children': ['b'],
        },
        {'id': 'a', 'component': 'Leaf'},
        {'id': 'b', 'component': 'Leaf'},
      ]);
      final reordered = _validate(_graphPlan(), 'RootCard', [
        {
          'id': 'root',
          'component': 'RootCard',
          'child': 'a',
          'children': ['b'],
        },
        {'id': 'b', 'component': 'Leaf'},
        {'id': 'a', 'component': 'Leaf'},
      ]);

      expect(reordered.canonicalJson, isNot(first.canonicalJson));
    });
  });

  test('recursive failure uses the exact collision-safe emitted defs key', () {
    _expectFailure(
      _definitionKeyCollisionPlan(),
      'DefinitionCollisionCard',
      [
        {
          'id': 'root',
          'component': 'DefinitionCollisionCard',
          'a': {'value': 'valid', 'self': null},
          'b': {'value': 'wrong', 'self': null},
        },
      ],
      [
        'expected JSON integer',
        r'schema path "/components/DefinitionCollisionCard/$defs/Node_2/properties/value"',
      ],
    );
  });

  test('property description separation uses the exact emitted definition path',
      () {
    final plan = _descriptionSeparationPlan();
    final schema = a2uiWidgetDataSchemaMapForPlan(plan.widgets.single);
    expect(schema[r'$defs'], isA<Map<String, Object?>>());
    expect(
      (schema[r'$defs']! as Map<String, Object?>).keys,
      containsAll(<String>{'__a2ui_root__', 'Details'}),
    );

    _expectFailure(
      plan,
      'DescriptionSeparationCard',
      [
        {
          'id': 'root',
          'component': 'DescriptionSeparationCard',
          'details': {'count': 'wrong'},
        },
      ],
      [
        'expected JSON integer',
        r'schema path "/components/DescriptionSeparationCard/$defs/Details/properties/count"',
      ],
    );
  });

  test('diagnostic includes every stable author and schema anchor', () {
    final payload = _validSchemaPayload();
    payload.single['integer'] = 'wrong';
    _expectFailure(
      _schemaPlan(),
      'SchemaCard',
      payload,
      [
        'SchemaCardSource',
        'Boundary',
        'lib/a2ui_examples/SchemaCard/boundary.json',
        'component "root"',
        'component path "/0/integer"',
        r'schema path "/components/SchemaCard/$defs/__a2ui_root__/properties/integer"',
      ],
    );
  });
}
