import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Unit tests for the rich-shape `A2uiSchemaNode` → `json_schema_builder`
/// projection. The projection preserves the governing invariant PAST the
/// reflector: an unhandled node fails loud, never a permissive schema.
void main() {
  group('a2uiDataSchemaExpression — scalars + enums', () {
    test('scalar occurrence descriptions project and absence stays omitted',
        () {
      expect(
        a2uiDataSchemaExpression(
          const ScalarNode(
            A2uiScalarType.string,
            occurrenceDescription: 'Nested label.',
          ),
        ),
        "S.string(description: 'Nested label.')",
      );
      expect(
        a2uiDataSchemaExpression(const ScalarNode(A2uiScalarType.string)),
        'S.string()',
      );
    });

    test('described scalar is identical in expression and standalone map', () {
      const node = ScalarNode(
        A2uiScalarType.string,
        occurrenceDescription: 'Nested label.',
      );
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'LabelCard',
            properties: [prop('label', PropertyType.structured)],
          ),
        ]),
        richShapes: const {('LabelCard', 'label'): node},
      ).widgets.single;

      expect(
        a2uiWidgetDataSchemaExpression(const [
          (
            name: 'label',
            required: false,
            emission: A2uiDataField(node),
          ),
        ]),
        "S.object(properties: {'label': "
        "S.string(description: 'Nested label.')}, required: <String>[],)",
      );
      expect(
        (a2uiWidgetDataSchemaMapForPlan(plan)['properties']!
            as Map<String, Object?>)['label'],
        const {
          'type': 'string',
          'description': 'Nested label.',
        },
      );
    });

    test('outer property description replaces a plain scalar occurrence once',
        () {
      const node = ScalarNode(
        A2uiScalarType.number,
        preserveNumericRuntimeType: true,
        occurrenceDescription: 'Inner plain scalar.',
      );
      final plan = _scalarPlan(
        node: node,
        propertyType: PropertyType.real,
        outerDescription: 'Outer plain scalar.',
      );

      final expression = _scalarExpression(
        plan,
        outerDescription: 'Outer plain scalar.',
      );
      expect(
        expression,
        "S.object(properties: {'value': S.number(description: "
        "'Outer plain scalar.')}, required: <String>['value'],)",
      );
      _expectSingleOuterDescription(
        expression,
        outer: 'Outer plain scalar.',
        inner: 'Inner plain scalar.',
      );
      expect(_scalarMap(plan), {
        'type': 'number',
        'description': 'Outer plain scalar.',
      });
    });

    test(
        'outer property description replaces a constrained nullable scalar '
        'occurrence once', () {
      const node = ScalarNode(
        A2uiScalarType.string,
        occurrenceDescription: 'Inner constrained scalar.',
        nullable: true,
      );
      final plan = _scalarPlan(
        node: node,
        propertyType: PropertyType.string,
        outerDescription: 'Outer constrained scalar.',
        constraints: const RestageConstraints(minLength: 2, maxLength: 5),
      );

      final expression = _scalarExpression(
        plan,
        outerDescription: 'Outer constrained scalar.',
      );
      expect(
        expression,
        [
          "S.object(properties: {'value': S.combined(",
          "description: 'Outer constrained scalar.', anyOf: [",
          'S.fromMap(<String, Object?>{...S.string().value, ',
          "'minLength': 2, 'maxLength': 5}), S.nil()])}, ",
          "required: <String>['value'],)",
        ].join(),
      );
      _expectSingleOuterDescription(
        expression,
        outer: 'Outer constrained scalar.',
        inner: 'Inner constrained scalar.',
      );
      expect(_scalarMap(plan), {
        'description': 'Outer constrained scalar.',
        'anyOf': [
          {
            'type': 'string',
            'minLength': 2,
            'maxLength': 5,
          },
          {'type': 'null'},
        ],
      });
    });

    test(
        'outer property description replaces a write-back scalar occurrence '
        'once', () {
      const node = ScalarNode(
        A2uiScalarType.boolean,
        occurrenceDescription: 'Inner write-back scalar.',
      );
      final plan = _scalarPlan(
        node: node,
        propertyType: PropertyType.boolean,
        outerDescription: 'Outer write-back scalar.',
        writeBack: true,
      );
      expect((plan.fields.single.emission as A2uiDataField).writeBack, isTrue);

      final expression = _scalarExpression(
        plan,
        outerDescription: 'Outer write-back scalar.',
      );
      expect(
        expression,
        "S.object(properties: {'value': S.combined(description: "
        "'Outer write-back scalar.', oneOf: [S.boolean(), "
        "S.object(properties: {'path': S.string()}, required: "
        "<String>['path']), S.object(properties: {'call': S.string(), "
        "'args': S.object(additionalProperties: true)}, required: "
        "<String>['call'])])}, required: <String>['value'],)",
      );
      _expectSingleOuterDescription(
        expression,
        outer: 'Outer write-back scalar.',
        inner: 'Inner write-back scalar.',
      );
      expect(_scalarMap(plan), {
        'description': 'Outer write-back scalar.',
        'oneOf': [
          {'type': 'boolean'},
          {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
            },
            'required': ['path'],
          },
          {
            'type': 'object',
            'properties': {
              'call': {'type': 'string'},
              'args': {'type': 'object', 'additionalProperties': true},
            },
            'required': ['call'],
          },
        ],
      });
    });

    test('integer → S.integer()', () {
      expect(
        a2uiDataSchemaExpression(const ScalarNode(A2uiScalarType.integer)),
        'S.integer()',
      );
    });

    test('an enum with a resolved member set → S.string(enumValues: [...])',
        () {
      expect(
        a2uiDataSchemaExpression(
          EnumNode(members: const ['small', 'large'], dartTypeName: 'Size'),
        ),
        "S.string(enumValues: <Object?>['small', 'large'])",
      );
    });

    test('an enum with NO member set → S.string() (byte-neutral catalog path)',
        () {
      expect(
        a2uiDataSchemaExpression(
          EnumNode(members: const [], dartTypeName: 'Size'),
        ),
        'S.string()',
      );
    });

    test('enum occurrence descriptions project without changing members', () {
      expect(
        a2uiDataSchemaExpression(
          EnumNode(
            members: const ['small', 'large'],
            dartTypeName: 'Size',
            occurrenceDescription: 'Selected size.',
          ),
        ),
        "S.string(description: 'Selected size.', "
        "enumValues: <Object?>['small', 'large'])",
      );
    });
  });

  group('a2uiDataSchemaExpression — objects', () {
    test('an ObjectNode → S.object(properties, required)', () {
      final node = ObjectNode(
        fields: const {
          'label': ScalarNode(A2uiScalarType.string),
          'count': ScalarNode(A2uiScalarType.integer),
        },
        required: const {'label'},
      );
      expect(
        a2uiDataSchemaExpression(node),
        "S.object(properties: {'label': S.string(), "
        "'count': S.integer()}, required: <String>['label'],)",
      );
    });

    test('a nested object projects recursively', () {
      final node = ObjectNode(
        fields: {
          'inner': ObjectNode(
            fields: const {'x': ScalarNode(A2uiScalarType.number)},
            required: const {'x'},
          ),
        },
        required: const {'inner'},
      );
      expect(
        a2uiDataSchemaExpression(node),
        contains("'inner': S.object(properties: {'x': S.number()}, "
            "required: <String>['x'],)"),
      );
    });
  });

  group('a2uiDataSchemaExpression — maps + lists-of-objects', () {
    test('a MapNode → S.object(additionalProperties: valueSchema)', () {
      expect(
        a2uiDataSchemaExpression(
          const MapNode(valueType: ScalarNode(A2uiScalarType.integer)),
        ),
        'S.object(additionalProperties: S.integer())',
      );
    });

    test('a list-of-objects → S.list(items: S.object(...))', () {
      final node = ListNode(
        element: ObjectNode(
          fields: const {'label': ScalarNode(A2uiScalarType.string)},
          required: const {'label'},
        ),
      );
      expect(
        a2uiDataSchemaExpression(node),
        "S.list(items: S.object(properties: {'label': S.string()}, "
        "required: <String>['label'],))",
      );
    });

    test('list and map descriptions stay on containers, not their members', () {
      const item = ScalarNode(
        A2uiScalarType.string,
        occurrenceDescription: 'One tag.',
      );
      expect(
        a2uiDataSchemaExpression(
          const ListNode(
            element: item,
            occurrenceDescription: 'Visible tags.',
          ),
        ),
        "S.list(description: 'Visible tags.', "
        "items: S.string(description: 'One tag.'))",
      );
      expect(
        a2uiDataSchemaExpression(
          const MapNode(
            valueType: item,
            occurrenceDescription: 'Tags by locale.',
          ),
        ),
        "S.object(description: 'Tags by locale.', "
        "additionalProperties: S.string(description: 'One tag.'))",
      );
    });

    test('described scalar-list composition is identical in expression + map',
        () {
      const node = ListNode(
        element: ScalarNode(
          A2uiScalarType.string,
          occurrenceDescription: 'One tag.',
        ),
        occurrenceDescription: 'Visible tags.',
        nullable: true,
      );
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'TagList',
            properties: [prop('tags', PropertyType.structured)],
          ),
        ]),
        richShapes: const {('TagList', 'tags'): node},
      ).widgets.single;

      final expression = a2uiWidgetDataSchemaExpression(const [
        (
          name: 'tags',
          required: false,
          emission: A2uiDataField(node),
        ),
      ]);
      expect(
        expression,
        [
          "S.object(properties: {'tags': S.combined(description: ",
          "'Visible tags.', oneOf: [S.combined(anyOf: [S.list(",
          "items: S.string(description: 'One tag.')), S.nil()]), ",
          "S.object(properties: {'path': S.string()}, ",
          "required: <String>['path']), S.object(properties: {'call': ",
          "S.string(), 'args': S.object(additionalProperties: true)}, ",
          "required: <String>['call'])])}, required: <String>[],)",
        ].join(),
      );
      expect(
        (a2uiWidgetDataSchemaMapForPlan(plan)['properties']!
            as Map<String, Object?>)['tags'],
        {
          'description': 'Visible tags.',
          'oneOf': [
            {
              'anyOf': [
                {
                  'type': 'array',
                  'items': {
                    'type': 'string',
                    'description': 'One tag.',
                  },
                },
                {'type': 'null'},
              ],
            },
            {
              'type': 'object',
              'properties': {
                'path': {'type': 'string'},
              },
              'required': ['path'],
            },
            {
              'type': 'object',
              'properties': {
                'call': {'type': 'string'},
                'args': {'type': 'object', 'additionalProperties': true},
              },
              'required': ['call'],
            },
          ],
        },
      );
    });

    test('nullable carrier descriptions decorate the outer composed schema',
        () {
      const node = MapNode(
        valueType: ScalarNode(
          A2uiScalarType.string,
          occurrenceDescription: 'One label.',
        ),
        occurrenceDescription: 'Labels by locale.',
        nullable: true,
      );
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'LabelMap',
            properties: [prop('labels', PropertyType.structured)],
          ),
        ]),
        richShapes: const {('LabelMap', 'labels'): node},
      ).widgets.single;

      expect(
        a2uiDataSchemaExpression(node),
        [
          "S.combined(description: 'Labels by locale.', anyOf: [",
          'S.object(additionalProperties: ',
          "S.string(description: 'One label.')), S.nil()])",
        ].join(),
      );
      expect(
        (a2uiWidgetDataSchemaMapForPlan(plan)['properties']!
            as Map<String, Object?>)['labels'],
        {
          'description': 'Labels by locale.',
          'anyOf': [
            {
              'type': 'object',
              'additionalProperties': {
                'type': 'string',
                'description': 'One label.',
              },
            },
            {'type': 'null'},
          ],
        },
      );
    });

    test('outer property descriptions replace enum, map, and list roots once',
        () {
      final enumNode = EnumNode(
        members: const ['soft', 'loud'],
        dartTypeName: 'Tone',
        occurrenceDescription: 'Inner enum.',
      );
      const mapNode = MapNode(
        valueType: ScalarNode(
          A2uiScalarType.string,
          occurrenceDescription: 'One map value.',
        ),
        occurrenceDescription: 'Inner map.',
      );
      final listNode = ListNode(
        occurrenceDescription: 'Inner list.',
        element: ObjectNode(
          occurrenceDescription: 'One item.',
          fields: const {
            'label': ScalarNode(
              A2uiScalarType.string,
              occurrenceDescription: 'Item label.',
            ),
          },
          required: const {'label'},
        ),
      );
      final fields = <A2uiWidgetField>[
        (name: 'tone', required: false, emission: A2uiDataField(enumNode)),
        (
          name: 'labels',
          required: false,
          emission: const A2uiDataField(mapNode),
        ),
        (name: 'items', required: false, emission: A2uiDataField(listNode)),
      ];
      Map<String, Object?> projectedProperty(
        A2uiSchemaNode node,
        String description,
      ) {
        final plan = classifyA2uiCatalogDart(
          catalogWith([
            entry(
              name: 'CarrierCard',
              properties: [
                prop(
                  'value',
                  PropertyType.structured,
                  description: description,
                  required: true,
                ),
              ],
            ),
          ]),
          richShapes: {('CarrierCard', 'value'): node},
        ).widgets.single;
        final properties = a2uiWidgetDataSchemaMapForPlan(plan)['properties']!
            as Map<String, Object?>;
        return properties['value']! as Map<String, Object?>;
      }

      final expression = a2uiWidgetDataSchemaExpression(
        fields,
        fieldDescription: (name) => switch (name) {
          'tone' => 'Outer enum.',
          'labels' => 'Outer map.',
          'items' => 'Outer list.',
          _ => null,
        },
      );
      expect(
        expression,
        "S.object(properties: {'tone': S.string(description: 'Outer enum.', "
        "enumValues: <Object?>['soft', 'loud']), 'labels': "
        "S.object(description: 'Outer map.', additionalProperties: "
        "S.string(description: 'One map value.')), 'items': "
        "S.list(description: 'Outer list.', items: "
        "S.object(description: 'One item.', properties: {'label': "
        "S.string(description: 'Item label.')}, required: "
        "<String>['label'],))}, required: <String>[],)",
      );
      for (final description in const [
        'Outer enum.',
        'Outer map.',
        'Outer list.',
      ]) {
        expect(description.allMatches(expression), hasLength(1));
      }
      for (final replaced in const [
        'Inner enum.',
        'Inner map.',
        'Inner list.',
      ]) {
        expect(expression, isNot(contains(replaced)));
      }

      expect(projectedProperty(enumNode, 'Outer enum.'), {
        'type': 'string',
        'description': 'Outer enum.',
        'enum': ['soft', 'loud'],
      });
      expect(projectedProperty(mapNode, 'Outer map.'), {
        'type': 'object',
        'description': 'Outer map.',
        'additionalProperties': {
          'type': 'string',
          'description': 'One map value.',
        },
      });
      expect(projectedProperty(listNode, 'Outer list.'), {
        'type': 'array',
        'description': 'Outer list.',
        'items': {
          'type': 'object',
          'description': 'One item.',
          'properties': {
            'label': {
              'type': 'string',
              'description': 'Item label.',
            },
          },
          'required': ['label'],
        },
      });
    });
  });

  group('a2uiDataSchemaExpression — fail-closed preservation', () {
    test('a UnionNode (deferred) fails loud, never a permissive schema', () {
      expect(
        () => a2uiDataSchemaExpression(
          UnionNode(variants: const [], discriminatorField: 'type'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group(r'a2uiDataSchemaExpression — $defs/$ref (genuine cycles only)', () {
    test(r'a self-recursive object hoists into $defs with a root $ref', () {
      const treeId = 'package:x/x.dart#TreeNode';
      final node = ObjectNode(
        fields: const {
          'label': ScalarNode(A2uiScalarType.string),
          'children': ListNode(element: RefNode(treeId)),
        },
        required: const {'label', 'children'},
        defId: treeId,
      );
      expect(
        a2uiDataSchemaExpression(node),
        r"S.combined($ref: '#/\$defs/TreeNode', $defs: {'TreeNode': S.object(properties: {'label': S.string(), 'children': S.list(items: S.combined($ref: '#/\$defs/TreeNode'))}, required: <String>['label', 'children'],)})",
      );
    });

    test('cycle-aware enum/list/map descriptions keep their schema locations',
        () {
      const treeId = 'package:x/x.dart#TreeNode';
      final tree = ObjectNode(
        defId: treeId,
        definitionDescription: 'Canonical tree.',
        fields: {
          'tone': EnumNode(
            members: const ['soft', 'loud'],
            dartTypeName: 'Tone',
            occurrenceDescription: 'Tree tone.',
          ),
          'children': const ListNode(
            occurrenceDescription: 'Direct children.',
            element: RefNode(
              treeId,
              occurrenceDescription: 'One child.',
            ),
          ),
          'lookup': const MapNode(
            occurrenceDescription: 'Children by key.',
            nullable: true,
            valueType: RefNode(
              treeId,
              occurrenceDescription: 'One keyed child.',
            ),
          ),
        },
        required: const {'tone', 'children'},
      );
      final expression = a2uiDataSchemaExpression(tree);
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'TreeCard',
            properties: [
              prop('tree', PropertyType.structured, required: true),
            ],
          ),
        ]),
        richShapes: {('TreeCard', 'tree'): tree},
      ).widgets.single;
      final document = a2uiWidgetDataSchemaMapForPlan(plan);
      final defs = document[r'$defs']! as Map<String, Object?>;
      final treeSchema = defs['TreeNode']! as Map<String, Object?>;
      final properties = treeSchema['properties']! as Map<String, Object?>;

      for (final description in const [
        'Canonical tree.',
        'Tree tone.',
        'Direct children.',
        'One child.',
        'Children by key.',
        'One keyed child.',
      ]) {
        expect(description.allMatches(expression), hasLength(1));
      }
      expect(treeSchema['description'], 'Canonical tree.');
      expect(
        (properties['tone']! as Map<String, Object?>)['description'],
        'Tree tone.',
      );
      final children = properties['children']! as Map<String, Object?>;
      expect(children['description'], 'Direct children.');
      expect(
        (children['items']! as Map<String, Object?>)['description'],
        'One child.',
      );
      final lookup = properties['lookup']! as Map<String, Object?>;
      final nonNullLookup =
          (lookup['anyOf']! as List<Object?>).first! as Map<String, Object?>;
      expect(lookup['description'], 'Children by key.');
      expect(nonNullLookup, isNot(contains('description')));
      expect(
        (nonNullLookup['additionalProperties']!
            as Map<String, Object?>)['description'],
        'One keyed child.',
      );
    });

    test(
        'mutual recursion: only the genuine cycle target gets a '
        r'$def; the intermediary is inlined', () {
      const aId = 'package:x/x.dart#A';
      const bId = 'package:x/x.dart#B';
      final node = ObjectNode(
        defId: aId,
        required: const {'b'},
        fields: {
          'b': ObjectNode(
            defId: bId,
            required: const {'a'},
            fields: const {'a': RefNode(aId)},
          ),
        },
      );
      expect(
        a2uiDataSchemaExpression(node),
        r"S.combined($ref: '#/\$defs/A', $defs: {'A': S.object(properties: {'b': S.object(properties: {'a': S.combined($ref: '#/\$defs/A')}, required: <String>['a'],)}, required: <String>['b'],)})",
      );
    });

    test(r'a non-recursive shared subtype is inlined (no $defs)', () {
      const innerId = 'package:x/x.dart#Inner';
      final inner = ObjectNode(
        defId: innerId,
        required: const {'x'},
        fields: const {'x': ScalarNode(A2uiScalarType.number)},
      );
      final node = ObjectNode(
        defId: 'package:x/x.dart#Outer',
        required: const {'a', 'b'},
        fields: {'a': inner, 'b': inner},
      );
      final schema = a2uiDataSchemaExpression(node);
      expect(schema, isNot(contains(r'$defs')));
      expect(schema, isNot(contains(r'$ref')));
      expect(
        schema,
        "S.object(properties: {'a': S.object(properties: {'x': S.number()}, "
        "required: <String>['x'],), 'b': S.object(properties: {'x': "
        "S.number()}, required: <String>['x'],)}, "
        "required: <String>['a', 'b'],)",
      );
    });

    test(
        'two recursive types sharing a symbol name across libraries get '
        r'distinct collision-safe $defs keys', () {
      const aId = 'package:a/a.dart#Node';
      const bId = 'package:b/b.dart#Node';
      final node = ObjectNode(
        defId: 'package:x/x.dart#Root',
        required: const {'a', 'b'},
        fields: {
          'a': ObjectNode(
            defId: aId,
            required: const {'self'},
            fields: const {'self': RefNode(aId)},
          ),
          'b': ObjectNode(
            defId: bId,
            required: const {'self'},
            fields: const {'self': RefNode(bId)},
          ),
        },
      );
      final schema = a2uiDataSchemaExpression(node);
      // sorted-canonical-id disambiguation: aId < bId → 'Node' / 'Node_2'.
      expect(schema, contains("'Node': S.object"));
      expect(schema, contains("'Node_2': S.object"));
      expect(schema, contains(r"'a': S.combined($ref: '#/\$defs/Node')"));
      expect(schema, contains(r"'b': S.combined($ref: '#/\$defs/Node_2')"));
      // each self-ref points to its own def, not the other.
      expect(schema, contains(r"'self': S.combined($ref: '#/\$defs/Node')"));
      expect(schema, contains(r"'self': S.combined($ref: '#/\$defs/Node_2')"));
    });

    test(
        'a non-recursive object carrying a defId still projects bare '
        r'(no $defs — byte-neutral)', () {
      final node = ObjectNode(
        defId: 'package:x/x.dart#Plain',
        required: const {'label'},
        fields: const {'label': ScalarNode(A2uiScalarType.string)},
      );
      expect(
        a2uiDataSchemaExpression(node),
        "S.object(properties: {'label': S.string()}, "
        "required: <String>['label'],)",
      );
    });
  });

  group('a2uiDataSchemaExpression — nullability', () {
    test('a nullable scalar → anyOf[type, nil]', () {
      expect(
        a2uiDataSchemaExpression(
          const ScalarNode(A2uiScalarType.boolean, nullable: true),
        ),
        'S.combined(anyOf: [S.boolean(), S.nil()])',
      );
    });

    test(
        'a required-but-nullable field is present AND null-allowed '
        '(nullability is not presence)', () {
      final node = ObjectNode(
        required: const {'note'},
        fields: const {
          'note': ScalarNode(A2uiScalarType.string, nullable: true),
        },
      );
      expect(
        a2uiDataSchemaExpression(node),
        "S.object(properties: {'note': S.combined(anyOf: [S.string(), "
        "S.nil()])}, required: <String>['note'],)",
      );
    });

    test(
        'a nullable field OF A RECURSIVE TYPE → anyOf[ref, nil] at the '
        r'occurrence while the $def stays non-null', () {
      const aId = 'package:x/x.dart#A';
      final node = ObjectNode(
        defId: aId,
        required: const {},
        fields: const {'next': RefNode(aId, nullable: true)},
      );
      final schema = a2uiDataSchemaExpression(node);
      // The occurrence carries nullability.
      expect(
        schema,
        contains(r"'next': S.combined(anyOf: [S.combined($ref: "
            r"'#/\$defs/A'), S.nil()])"),
      );
      // The $def itself is a bare non-null S.object (no anyOf wrapper).
      expect(
        schema,
        startsWith(r"S.combined($ref: '#/\$defs/A', $defs: {'A': "
            'S.object(properties: {'),
      );
    });
  });

  group('a2uiWidgetDataSchemaExpression — the widget-root two-pass', () {
    test(
        r'non-recursive fields → a bare widget S.object (no $defs, '
        'byte-neutral)', () {
      final schema = a2uiWidgetDataSchemaExpression(const [
        (
          name: 'msg',
          required: true,
          emission: A2uiDataField(ScalarNode(A2uiScalarType.string)),
        ),
        (
          name: 'child',
          required: false,
          emission: A2uiChildField(A2uiChildNode()),
        ),
      ]);
      expect(schema, isNot(contains(r'$defs')));
      expect(
        schema,
        "S.object(properties: {'msg': S.string(), 'child': S.string()}, "
        "required: <String>['msg'],)",
      );
    });

    test(
        r'two fields of the SAME recursive type share ONE $def with two '
        r'$refs (cross-field dedup at the document root)', () {
      const treeId = 'package:x/x.dart#TreeNode';
      final tree = ObjectNode(
        defId: treeId,
        required: const {'children'},
        fields: const {'children': ListNode(element: RefNode(treeId))},
      );
      final schema = a2uiWidgetDataSchemaExpression([
        (name: 'first', required: true, emission: A2uiDataField(tree)),
        (name: 'second', required: false, emission: A2uiDataField(tree)),
      ]);
      // The $defs hoist to the document root.
      expect(schema, startsWith(r"S.combined($ref: '#/\$defs/"));
      expect(schema, contains(r'$defs: {'));
      // Exactly ONE TreeNode definition (cross-field dedup).
      expect("'TreeNode': S.object".allMatches(schema).length, 1);
      // Both fields reference it.
      expect(
        schema,
        contains(r"'first': S.combined($ref: '#/\$defs/TreeNode')"),
      );
      expect(
        schema,
        contains(r"'second': S.combined($ref: '#/\$defs/TreeNode')"),
      );
    });
  });
}

A2uiDartWidgetPlan _scalarPlan({
  required ScalarNode node,
  required PropertyType propertyType,
  required String outerDescription,
  RestageConstraints constraints = RestageConstraints.empty,
  bool writeBack = false,
}) {
  final properties = <PropertyEntry>[
    PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: 'value',
      type: propertyType,
      description: outerDescription,
      required: true,
      constraints: constraints,
    ),
    if (writeBack)
      const PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'onChanged',
        type: PropertyType.event,
        description: '',
        required: true,
      ),
  ];
  final catalog = catalogWith([
    entry(name: 'ScalarCard', properties: properties),
  ]);
  return classifyA2uiCatalogDart(
    catalog,
    richShapes: {('ScalarCard', 'value'): node},
    eventSeam: writeBack
        ? {
            ('ScalarCard', 'onChanged'): A2uiCallbackWriteBack(
              node.type,
              nullable: node.nullable,
              isList: false,
              preserveNumericRuntimeType: node.preserveNumericRuntimeType,
            ),
          }
        : null,
    pairingSeam:
        writeBack ? const {('ScalarCard', 'onChanged'): 'value'} : null,
  ).widgets.single;
}

String _scalarExpression(
  A2uiDartWidgetPlan plan, {
  required String outerDescription,
}) =>
    a2uiWidgetDataSchemaExpression(
      [
        (
          name: 'value',
          required: true,
          emission: plan.fields.single.emission,
        ),
      ],
      fieldDescription: (_) => outerDescription,
    );

Map<String, Object?> _scalarMap(A2uiDartWidgetPlan plan) =>
    ((a2uiWidgetDataSchemaMapForPlan(plan)['properties']! as Map)['value']!
            as Map)
        .cast<String, Object?>();

void _expectSingleOuterDescription(
  String expression, {
  required String outer,
  required String inner,
}) {
  expect(outer.allMatches(expression), hasLength(1));
  expect('description:'.allMatches(expression), hasLength(1));
  expect(expression, isNot(contains(inner)));
}
