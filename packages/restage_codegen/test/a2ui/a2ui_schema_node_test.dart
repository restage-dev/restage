import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:test/test.dart';

void main() {
  group('A2uiSchemaNode', () {
    test('ScalarNode carries its primitive type and is non-nullable by default',
        () {
      const node = ScalarNode(A2uiScalarType.boolean);
      expect(node.type, A2uiScalarType.boolean);
      expect(node.nullable, isFalse);
    });

    test('ScalarNode value-equals an identical node and differs on type', () {
      expect(
        const ScalarNode(A2uiScalarType.number),
        equals(const ScalarNode(A2uiScalarType.number)),
      );
      expect(
        const ScalarNode(A2uiScalarType.number),
        isNot(equals(const ScalarNode(A2uiScalarType.string))),
      );
      expect(
        const ScalarNode(A2uiScalarType.string),
        isNot(equals(const ScalarNode(A2uiScalarType.string, nullable: true))),
      );
    });

    test('EnumNode carries its member set + Dart type identity', () {
      final node = EnumNode(
        members: const ['vertical', 'horizontal'],
        dartTypeName: 'Axis',
        libraryUri: 'package:flutter/rendering.dart',
      );
      expect(node.members, ['vertical', 'horizontal']);
      expect(node.dartTypeName, 'Axis');
      expect(node.libraryUri, 'package:flutter/rendering.dart');
    });

    test('EnumNode defensively copies its members to an unmodifiable list', () {
      final source = ['a', 'b'];
      final node = EnumNode(members: source, dartTypeName: 'E');
      source.add('c'); // mutating the source must not leak into the node
      expect(node.members, ['a', 'b']);
      expect(() => node.members.add('d'), throwsUnsupportedError);
    });

    test('EnumNode value equality is deep over the member set', () {
      expect(
        EnumNode(members: const ['a', 'b'], dartTypeName: 'E'),
        equals(EnumNode(members: const ['a', 'b'], dartTypeName: 'E')),
      );
      expect(
        EnumNode(members: const ['a', 'b'], dartTypeName: 'E'),
        isNot(equals(EnumNode(members: const ['a'], dartTypeName: 'E'))),
      );
    });

    test('ListNode nests an element node and equals deeply', () {
      const stringList = ListNode(element: ScalarNode(A2uiScalarType.string));
      const numberList = ListNode(element: ScalarNode(A2uiScalarType.number));
      expect(stringList.element, const ScalarNode(A2uiScalarType.string));
      expect(
        stringList,
        equals(const ListNode(element: ScalarNode(A2uiScalarType.string))),
      );
      expect(stringList, isNot(equals(numberList)));
    });

    test('ObjectNode carries fields + required and equals deeply', () {
      ObjectNode build() => ObjectNode(
            fields: const {
              'name': ScalarNode(A2uiScalarType.string),
              'count': ScalarNode(A2uiScalarType.number),
            },
            required: const {'name'},
          );
      expect(build().fields.keys, ['name', 'count']);
      expect(build().required, {'name'});
      expect(build(), equals(build()));
      expect(
        build(),
        isNot(
          equals(
            ObjectNode(
              fields: const {'name': ScalarNode(A2uiScalarType.string)},
              required: const {},
            ),
          ),
        ),
      );
    });

    test('ObjectNode defensively copies fields + required', () {
      final fields = <String, A2uiSchemaNode>{
        'a': const ScalarNode(A2uiScalarType.string),
      };
      final required = {'a'};
      final node = ObjectNode(fields: fields, required: required);
      expect(
        () => node.fields['b'] = const ScalarNode(A2uiScalarType.number),
        throwsUnsupportedError,
      );
      expect(() => node.required.add('b'), throwsUnsupportedError);
    });

    test('MapNode carries its value type and equals deeply', () {
      const node = MapNode(valueType: ScalarNode(A2uiScalarType.string));
      expect(node.valueType, const ScalarNode(A2uiScalarType.string));
      expect(
        node,
        equals(const MapNode(valueType: ScalarNode(A2uiScalarType.string))),
      );
      expect(
        node,
        isNot(
          equals(const MapNode(valueType: ScalarNode(A2uiScalarType.number))),
        ),
      );
    });

    test('UnionNode carries variants + discriminator and equals deeply', () {
      UnionNode build() => UnionNode(
            variants: [
              ObjectNode(
                fields: const {'type': ScalarNode(A2uiScalarType.string)},
                required: const {'type'},
              ),
            ],
            discriminatorField: 'type',
          );
      expect(build().discriminatorField, 'type');
      expect(build().variants, hasLength(1));
      expect(build(), equals(build()));
    });

    test('RefNode carries its definition id and equals deeply', () {
      expect(const RefNode('Lesson'), equals(const RefNode('Lesson')));
      expect(const RefNode('Lesson'), isNot(equals(const RefNode('Other'))));
    });

    test('the sealed hierarchy supports an exhaustive switch (no default arm)',
        () {
      String describe(A2uiSchemaNode node) => switch (node) {
            ScalarNode() => 'scalar',
            EnumNode() => 'enum',
            ListNode() => 'list',
            ObjectNode() => 'object',
            MapNode() => 'map',
            UnionNode() => 'union',
            RefNode() => 'ref',
          };
      expect(describe(const ScalarNode(A2uiScalarType.boolean)), 'scalar');
      expect(
        describe(EnumNode(members: const ['x'], dartTypeName: 'E')),
        'enum',
      );
      expect(
        describe(const ListNode(element: ScalarNode(A2uiScalarType.string))),
        'list',
      );
      expect(
        describe(ObjectNode(fields: const {}, required: const {})),
        'object',
      );
      expect(
        describe(const MapNode(valueType: ScalarNode(A2uiScalarType.string))),
        'map',
      );
      expect(
        describe(UnionNode(variants: const [], discriminatorField: 'type')),
        'union',
      );
      expect(describe(const RefNode('X')), 'ref');
    });
  });

  group('A2uiChildSlot', () {
    test('child slots value-equal by kind and are not interchangeable', () {
      // The child slots form their own sealed hierarchy (they do not extend
      // A2uiSchemaNode) — distinctness from the data tree is a compile-time
      // fact, proven by the exhaustive switch below over A2uiChildSlot.
      const single = A2uiChildNode();
      const list = A2uiChildrenNode();
      expect(single, equals(const A2uiChildNode()));
      expect(list, equals(const A2uiChildrenNode()));
      expect(single, isNot(equals(list)));
    });

    test('the child-slot hierarchy supports an exhaustive switch', () {
      String describe(A2uiChildSlot slot) => switch (slot) {
            A2uiChildNode() => 'child',
            A2uiChildrenNode() => 'children',
          };
      expect(describe(const A2uiChildNode()), 'child');
      expect(describe(const A2uiChildrenNode()), 'children');
    });
  });
}
