import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:test/test.dart';

/// Unit tests for the rich-shape `A2uiSchemaNode` → `json_schema_builder`
/// projection. The projection preserves the governing invariant PAST the
/// reflector: an unhandled node fails loud, never a permissive schema.
void main() {
  group('a2uiDataSchemaExpression — scalars + enums', () {
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
