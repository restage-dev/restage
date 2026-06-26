import 'package:restage_codegen/src/a2ui/a2ui_data_builder.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:test/test.dart';

/// Unit tests for the recursive value-builder generator. The builder emits the
/// Dart source that reconstructs a typed value from decoded (untrusted) genui
/// JSON at render time. Its contract is RUNTIME fail-SAFE — graceful
/// degradation, never a thrown cast — distinct from the compile-time
/// fail-closed-LOUD reflector (which has already scoped out unsupported SHAPES
/// before the builder sees a node).
void main() {
  group('valueExpression — scalars', () {
    final builder = A2uiDataBuilder(const [
      ScalarNode(A2uiScalarType.string),
    ]);

    test('string → fail-safe typed cast (single-eval, never a thrown cast)',
        () {
      expect(
        builder.valueExpression(
          const ScalarNode(A2uiScalarType.string),
          "data['x']",
        ),
        "_restageA2uiAs<String>(data['x'])",
      );
    });

    test('integer → num cast then toInt', () {
      expect(
        builder.valueExpression(
          const ScalarNode(A2uiScalarType.integer),
          'raw',
        ),
        '_restageA2uiAs<num>(raw)?.toInt()',
      );
    });

    test('number → num cast then toDouble', () {
      expect(
        builder.valueExpression(const ScalarNode(A2uiScalarType.number), 'raw'),
        '_restageA2uiAs<num>(raw)?.toDouble()',
      );
    });

    test('boolean → bool cast', () {
      expect(
        builder.valueExpression(
          const ScalarNode(A2uiScalarType.boolean),
          'raw',
        ),
        '_restageA2uiAs<bool>(raw)',
      );
    });
  });

  group('valueExpression — enums', () {
    test('enum → fail-safe name lookup (unknown/absent member → null)', () {
      final builder = A2uiDataBuilder([
        EnumNode(members: const ['soft', 'loud'], dartTypeName: 'Tone'),
      ]);
      expect(
        builder.valueExpression(
          EnumNode(members: const ['soft', 'loud'], dartTypeName: 'Tone'),
          "data['tone']",
        ),
        "Tone.values.asNameMap()[_restageA2uiAs<String>(data['tone'])]",
      );
    });
  });

  group('valueExpression — lists', () {
    final builder = A2uiDataBuilder(const [
      ListNode(element: ScalarNode(A2uiScalarType.string)),
    ]);

    test('list of non-null scalars → map + whereType + toList (drops bad)', () {
      expect(
        builder.valueExpression(
          const ListNode(element: ScalarNode(A2uiScalarType.string)),
          "data['tags']",
        ),
        "_restageA2uiAs<List<Object?>>(data['tags'])?.map((e) => "
        '_restageA2uiAs<String>(e)).whereType<String>().toList()',
      );
    });

    test('list of nullable-element scalars → map + toList (keeps nulls)', () {
      expect(
        builder.valueExpression(
          const ListNode(
            element: ScalarNode(A2uiScalarType.string, nullable: true),
          ),
          'raw',
        ),
        '_restageA2uiAs<List<Object?>>(raw)?.map((e) => '
        '_restageA2uiAs<String>(e)).toList()',
      );
    });

    test('list of ints → whereType<int> with toInt element coercion', () {
      expect(
        builder.valueExpression(
          const ListNode(element: ScalarNode(A2uiScalarType.integer)),
          'raw',
        ),
        '_restageA2uiAs<List<Object?>>(raw)?.map((e) => '
        '_restageA2uiAs<num>(e)?.toInt()).whereType<int>().toList()',
      );
    });
  });

  group('valueExpression — maps', () {
    test('Map<String, V> (non-null value) → drop-null map helper', () {
      final builder = A2uiDataBuilder(const [
        MapNode(valueType: ScalarNode(A2uiScalarType.integer)),
      ]);
      expect(
        builder.valueExpression(
          const MapNode(valueType: ScalarNode(A2uiScalarType.integer)),
          "data['counts']",
        ),
        "_restageA2uiMap<int>(data['counts'], "
        '(v) => _restageA2uiAs<num>(v)?.toInt())',
      );
    });

    test('Map<String, V?> (nullable value) → keep-null map helper', () {
      final builder = A2uiDataBuilder(const [
        MapNode(
          valueType: ScalarNode(A2uiScalarType.string, nullable: true),
        ),
      ]);
      expect(
        builder.valueExpression(
          const MapNode(
            valueType: ScalarNode(A2uiScalarType.string, nullable: true),
          ),
          'raw',
        ),
        '_restageA2uiMapNullable<String>(raw, '
        '(v) => _restageA2uiAs<String>(v))',
      );
    });
  });

  group('supportDefinitions — maps', () {
    test('a non-null-value map emits the drop-null helper only', () {
      final builder = A2uiDataBuilder(const [
        MapNode(valueType: ScalarNode(A2uiScalarType.integer)),
      ]);
      final joined = builder.supportDefinitions().join('\n');
      // Returns nullable (null on a non-map) — uniform null-on-failure with
      // scalars/lists, so the field site's guard/default is live.
      expect(joined, contains('Map<String, V>? _restageA2uiMap<V>('));
      expect(joined, isNot(contains('_restageA2uiMapNullable')));
    });

    test('a nullable-value map emits the keep-null helper', () {
      final builder = A2uiDataBuilder(const [
        MapNode(
          valueType: ScalarNode(A2uiScalarType.string, nullable: true),
        ),
      ]);
      final joined = builder.supportDefinitions().join('\n');
      expect(joined, contains('Map<String, V?>? _restageA2uiMapNullable<V>'));
    });
  });

  group('valueExpression + helpers — nested data classes', () {
    ObjectNode classNode({
      required Map<String, A2uiSchemaNode> fields,
      required Set<String> required,
      required List<A2uiConstructorParameter> parameters,
      String dartTypeName = 'Inner',
      String defId = 'package:demo/inner.dart#Inner',
      String? constructorName,
    }) =>
        ObjectNode(
          fields: fields,
          required: required,
          defId: defId,
          construction: A2uiClassConstruction(
            dartTypeName: dartTypeName,
            libraryUri: 'package:demo/inner.dart',
            constructorName: constructorName,
            parameters: parameters,
          ),
        );

    test('a class object → a depth-bounded helper call (depth 0 at the root)',
        () {
      final node = classNode(
        fields: const {
          'label': ScalarNode(A2uiScalarType.string),
          'value': ScalarNode(A2uiScalarType.integer),
        },
        required: const {'label', 'value'},
        parameters: const [
          A2uiConstructorParameter(name: 'label', named: false),
          A2uiConstructorParameter(name: 'value', named: false),
        ],
      );
      final builder = A2uiDataBuilder([node]);
      expect(
        builder.valueExpression(node, "data['item']"),
        "_restageA2uiBuild_Inner(data['item'], 0)",
      );
    });

    test('positional class helper: depth + map guards, required guards, ctor',
        () {
      final node = classNode(
        fields: const {
          'label': ScalarNode(A2uiScalarType.string),
          'value': ScalarNode(A2uiScalarType.integer),
        },
        required: const {'label', 'value'},
        parameters: const [
          A2uiConstructorParameter(name: 'label', named: false),
          A2uiConstructorParameter(name: 'value', named: false),
        ],
      );
      final defs = A2uiDataBuilder([node]).supportDefinitions().join('\n');
      expect(defs, contains('const int _kA2uiMaxBuildDepth = 64;'));
      expect(
        defs,
        contains('Inner? _restageA2uiBuild_Inner(Object? _raw, int _depth) {'),
      );
      expect(defs, contains('if (_depth > _kA2uiMaxBuildDepth) return null;'));
      expect(defs, contains('if (_raw is! Map<String, Object?>) return null;'));
      expect(
        defs,
        contains("final label = _restageA2uiAs<String>(_raw['label']);"),
      );
      expect(defs, contains('if (label == null) return null;'));
      expect(
        defs,
        contains(
          "final value = _restageA2uiAs<num>(_raw['value'])?.toInt();",
        ),
      );
      expect(defs, contains('return Inner(label, value);'));
    });

    test('named params construct as name: local; a named ctor is honored', () {
      final node = classNode(
        dartTypeName: 'Callout',
        defId: 'package:demo/callout.dart#Callout',
        constructorName: 'soft',
        fields: const {
          'title': ScalarNode(A2uiScalarType.string),
          'count': ScalarNode(A2uiScalarType.integer),
        },
        required: const {'title'},
        parameters: const [
          A2uiConstructorParameter(name: 'title', named: true),
          A2uiConstructorParameter(name: 'count', named: true),
        ],
      );
      final defs = A2uiDataBuilder([node]).supportDefinitions().join('\n');
      // `count` is optional + non-null → generic fallback (ruling #1 spine).
      expect(
        defs,
        contains(
          "final count = _restageA2uiAs<num>(_raw['count'])?.toInt() ?? 0;",
        ),
      );
      expect(
        defs,
        contains('return Callout.soft(title: title, count: count);'),
      );
    });

    test('an optional NULLABLE field passes the coercion through (null OK)',
        () {
      final node = classNode(
        fields: const {
          'label': ScalarNode(A2uiScalarType.string),
          'note': ScalarNode(A2uiScalarType.string, nullable: true),
        },
        required: const {'label'},
        parameters: const [
          A2uiConstructorParameter(name: 'label', named: false),
          A2uiConstructorParameter(name: 'note', named: true),
        ],
      );
      final defs = A2uiDataBuilder([node]).supportDefinitions().join('\n');
      // No `?? fallback`, no `== null return`: a nullable optional just passes.
      expect(
        defs,
        contains("final note = _restageA2uiAs<String>(_raw['note']);"),
      );
      expect(defs, isNot(contains('if (note == null) return null;')));
      expect(defs, contains('return Inner(label, note: note);'));
    });

    test('a list-of-objects field calls the element helper at the same depth',
        () {
      final inner = classNode(
        fields: const {'label': ScalarNode(A2uiScalarType.string)},
        required: const {'label'},
        parameters: const [
          A2uiConstructorParameter(name: 'label', named: false),
        ],
      );
      final outer = ObjectNode(
        fields: {'items': ListNode(element: inner)},
        required: const {'items'},
        defId: 'package:demo/outer.dart#Outer',
        construction: A2uiClassConstruction(
          dartTypeName: 'Outer',
          libraryUri: 'package:demo/outer.dart',
          parameters: const [
            A2uiConstructorParameter(name: 'items', named: false),
          ],
        ),
      );
      final defs = A2uiDataBuilder([outer]).supportDefinitions().join('\n');
      // Both helpers are emitted; the list field coerces each element through
      // the Inner helper at the outer field's depth (`_depth + 1`).
      expect(
        defs,
        contains('Inner? _restageA2uiBuild_Inner('),
      );
      expect(
        defs,
        contains('Outer? _restageA2uiBuild_Outer('),
      );
      expect(defs, contains("_restageA2uiAs<List<Object?>>(_raw['items'])"));
      // Each element is coerced through the Inner helper at the field's depth.
      expect(defs, contains('_restageA2uiBuild_Inner(e, _depth + 1)'));
      expect(defs, contains('.whereType<Inner>().toList()'));
    });
  });

  group('valueExpression — records (null-capable, inline when present)', () {
    test(
        'a record reconstructs to null when raw is not a map; inline with '
        'per-field fallbacks when present', () {
      final record = ObjectNode(
        fields: {
          'title': const ScalarNode(A2uiScalarType.string),
          'tone': EnumNode(
            members: const ['soft', 'loud'],
            dartTypeName: 'Tone',
          ),
        },
        required: const {'title', 'tone'},
        construction: const A2uiRecordConstruction(),
      );
      final builder = A2uiDataBuilder([record]);
      final expr = builder.valueExpression(record, "data['header']");
      // The WHOLE record reconstructs to null when its raw is not a map (so a
      // required record fails the enclosing object safe, never fabricated).
      // When present, an inline record literal: every field reads through a
      // map-safe access and degrades to its per-field fallback (record internal
      // fields cannot be null).
      expect(
        expr,
        contains(
          "_restageA2uiAs<Map<String, Object?>>(data['header']) == null",
        ),
      );
      expect(expr, contains('? null :'));
      expect(expr, contains('(title: '));
      expect(
        expr,
        contains(
          "_restageA2uiAs<Map<String, Object?>>(data['header'])?['title']",
        ),
      );
      expect(expr, contains("?['title']) ?? ''"));
      expect(expr, contains('tone: Tone.values.asNameMap()'));
      expect(expr, contains('?? Tone.values.first'));
    });
  });

  group('valueExpression + helpers — recursion', () {
    test('a self-recursive class yields ONE depth-bounded helper that recurses',
        () {
      // TreeNode { String label; List<TreeNode> children; } — the recursive
      // child is a RefNode to the node's own defId.
      const treeId = 'package:demo/tree.dart#TreeNode';
      final tree = ObjectNode(
        fields: const {
          'label': ScalarNode(A2uiScalarType.string),
          'children': ListNode(element: RefNode(treeId)),
        },
        required: const {'label', 'children'},
        defId: treeId,
        construction: A2uiClassConstruction(
          dartTypeName: 'TreeNode',
          libraryUri: 'package:demo/tree.dart',
          parameters: const [
            A2uiConstructorParameter(name: 'label', named: false),
            A2uiConstructorParameter(name: 'children', named: false),
          ],
        ),
      );
      final defs = A2uiDataBuilder([tree]).supportDefinitions();
      // Exactly one TreeNode helper (deduped by defId).
      final treeHelpers =
          defs.where((d) => d.contains('_restageA2uiBuild_TreeNode(')).length;
      expect(treeHelpers, 1);
      final joined = defs.join('\n');
      // The recursive child list calls the SAME helper with depth + 1.
      expect(joined, contains('_restageA2uiBuild_TreeNode(e, _depth + 1)'));
      expect(joined, contains('.whereType<TreeNode>().toList()'));
      expect(
        joined,
        contains('if (_depth > _kA2uiMaxBuildDepth) return null;'),
      );
    });
  });

  group('valueExpression — optional non-null fallbacks (the generic spine)',
      () {
    String helperFor(A2uiSchemaNode field, String name) {
      final node = ObjectNode(
        fields: {name: field},
        required: const <String>{},
        defId: 'package:demo/h.dart#H',
        construction: A2uiClassConstruction(
          dartTypeName: 'H',
          libraryUri: 'package:demo/h.dart',
          parameters: [A2uiConstructorParameter(name: name, named: true)],
        ),
      );
      return A2uiDataBuilder([node]).supportDefinitions().join('\n');
    }

    test('optional non-null enum → ?? Type.values.first', () {
      final defs = helperFor(
        EnumNode(members: const ['a', 'b'], dartTypeName: 'Tone'),
        'tone',
      );
      expect(defs, contains('?? Tone.values.first;'));
    });

    test('optional non-null list → ?? const <String>[]', () {
      final defs = helperFor(
        const ListNode(element: ScalarNode(A2uiScalarType.string)),
        'tags',
      );
      expect(defs, contains('?? const <String>[];'));
    });

    test('optional non-null map → ?? const <String, int>{}', () {
      final defs = helperFor(
        const MapNode(valueType: ScalarNode(A2uiScalarType.integer)),
        'counts',
      );
      expect(defs, contains('?? const <String, int>{};'));
    });
  });

  group('helper bodies — null-guard only where the coercion can be null', () {
    String helperFor({
      required Map<String, A2uiSchemaNode> fields,
      required Set<String> required,
      required List<A2uiConstructorParameter> parameters,
    }) {
      final node = ObjectNode(
        fields: fields,
        required: required,
        defId: 'package:demo/h.dart#H',
        construction: A2uiClassConstruction(
          dartTypeName: 'H',
          libraryUri: 'package:demo/h.dart',
          parameters: parameters,
        ),
      );
      return A2uiDataBuilder([node]).supportDefinitions().join('\n');
    }

    test(
        'a REQUIRED record field gets a null-guard (a missing required record '
        'fails the object safe, never fabricated)', () {
      final defs = helperFor(
        fields: {
          'header': ObjectNode(
            fields: const {'a': ScalarNode(A2uiScalarType.string)},
            required: const {'a'},
            construction: const A2uiRecordConstruction(),
          ),
        },
        required: const {'header'},
        parameters: const [
          A2uiConstructorParameter(name: 'header', named: false),
        ],
      );
      // A required non-null record reconstructs to null when its raw is not a
      // map, so the whole object fails safe — it is NEVER fabricated from
      // per-field fallbacks (the never-fabricate-a-required-value contract).
      expect(defs, contains('if (header == null) return null;'));
      expect(defs, contains('return H(header);'));
    });

    test('a REQUIRED map field gets a live null-guard (null on a non-map)', () {
      final defs = helperFor(
        fields: const {
          'labels': MapNode(valueType: ScalarNode(A2uiScalarType.string)),
        },
        required: const {'labels'},
        parameters: const [
          A2uiConstructorParameter(name: 'labels', named: false),
        ],
      );
      expect(defs, contains('if (labels == null) return null;'));
    });

    test(
        'a REQUIRED NULLABLE field passes null through (null is a valid value)',
        () {
      // A required nullable param (e.g. `Data(this.note)` with `String? note`):
      // the field accepts null, so an explicit/absent null must NOT null the
      // whole object — pass the coercion through, no guard.
      final defs = helperFor(
        fields: const {
          'note': ScalarNode(A2uiScalarType.string, nullable: true),
        },
        required: const {'note'},
        parameters: const [
          A2uiConstructorParameter(name: 'note', named: false),
        ],
      );
      expect(
        defs,
        contains("final note = _restageA2uiAs<String>(_raw['note']);"),
      );
      expect(defs, isNot(contains('if (note == null) return null;')));
      expect(defs, contains('return H(note);'));
    });
  });

  group('valueExpression — records reconstruct to null when raw is not a map',
      () {
    test('a nullable record → null when raw is not a map (never fabricated)',
        () {
      final record = ObjectNode(
        fields: const {'title': ScalarNode(A2uiScalarType.string)},
        required: const {'title'},
        construction: const A2uiRecordConstruction(),
        nullable: true,
      );
      final builder = A2uiDataBuilder([record]);
      final expr = builder.valueExpression(record, "data['header']");
      // null-capable: a non-map / absent raw → null, not a fabricated record.
      expect(
        expr,
        contains(
          "_restageA2uiAs<Map<String, Object?>>(data['header']) == null",
        ),
      );
      expect(expr, contains('? null :'));
      // The else branch is still the always-constructible inline record.
      expect(expr, contains("?['title']) ?? ''"));
    });

    test('a non-null record also reconstructs to null when raw is not a map',
        () {
      final record = ObjectNode(
        fields: const {'title': ScalarNode(A2uiScalarType.string)},
        required: const {'title'},
        construction: const A2uiRecordConstruction(),
      );
      final builder = A2uiDataBuilder([record]);
      final expr = builder.valueExpression(record, "data['header']");
      // Like a nullable record: a non-null record fails safe to null on a
      // non-map raw (so a required record fails the enclosing object safe),
      // rather than fabricating a record from per-field fallbacks.
      expect(
        expr,
        contains(
          "_restageA2uiAs<Map<String, Object?>>(data['header']) == null",
        ),
      );
      expect(expr, contains('? null :'));
      expect(expr, contains('(title: '));
    });
  });

  group('nullability — one field-value funnel (a nullable node anywhere)', () {
    // The proof of the by-construction close: a NULLABLE node at ANY field
    // position is null-capable (no fabricated fallback); a NON-NULL node is
    // made non-null. Exercised at a record field (the 3rd site) and a class
    // field through the same funnel.
    ObjectNode record(Map<String, A2uiSchemaNode> fields, Set<String> req) =>
        ObjectNode(
          fields: fields,
          required: req,
          construction: const A2uiRecordConstruction(),
        );

    test('a NULLABLE record field passes the coercion through (no fallback)',
        () {
      final node = record(
        const {'note': ScalarNode(A2uiScalarType.string, nullable: true)},
        const {'note'},
      );
      final expr = A2uiDataBuilder([node]).valueExpression(node, "data['h']");
      expect(expr, contains('note: _restageA2uiAs<String>('));
      expect(expr, isNot(contains("?? ''")));
    });

    test(
        'a NON-NULL record field is defaulted (per-field fallback when the '
        'record is present)', () {
      final node = record(
        const {'title': ScalarNode(A2uiScalarType.string)},
        const {'title'},
      );
      final expr = A2uiDataBuilder([node]).valueExpression(node, "data['h']");
      expect(expr, contains("?? ''"));
    });

    test('a NULLABLE enum record field passes through (no values.first)', () {
      final node = record(
        {
          'tone': EnumNode(
            members: const ['a'],
            dartTypeName: 'Tone',
            nullable: true,
          ),
        },
        const {'tone'},
      );
      final expr = A2uiDataBuilder([node]).valueExpression(node, "data['h']");
      expect(expr, isNot(contains('?? Tone.values.first')));
    });
  });

  group('type-spelling — uniform prefix disambiguates cross-library names', () {
    ObjectNode boxFrom(String lib) => ObjectNode(
          fields: const {'x': ScalarNode(A2uiScalarType.integer)},
          required: const {'x'},
          defId: '$lib#Box',
          construction: A2uiClassConstruction(
            dartTypeName: 'Box',
            libraryUri: lib,
            parameters: const [
              A2uiConstructorParameter(name: 'x', named: false),
            ],
          ),
        );

    test(
        'two same-named classes from different libraries get distinct '
        'prefixed spellings (no collision)', () {
      // Uniform import prefixing makes the cross-library same-name case
      // unrepresentable: each library has a distinct prefix, so the two `Box`
      // helpers return/construct `p0.Box` and `p1.Box` — never an ambiguous
      // bare `Box`. (This is what retired the legacy collision guard.)
      final defs = A2uiDataBuilder(
        [boxFrom('package:a/a.dart'), boxFrom('package:b/b.dart')],
        prefixes: const {'package:a/a.dart': 'p0', 'package:b/b.dart': 'p1'},
      ).supportDefinitions().join('\n');
      expect(defs, contains('p0.Box? _restageA2uiBuild_Box('));
      expect(defs, contains('p1.Box? _restageA2uiBuild_Box_2('));
      expect(defs, contains('return p0.Box('));
      expect(defs, contains('return p1.Box('));
    });

    test('the same class twice (one defId) does NOT collide', () {
      expect(
        () => A2uiDataBuilder([
          boxFrom('package:a/a.dart'),
          boxFrom('package:a/a.dart'),
        ]),
        returnsNormally,
      );
    });

    test(
        'firstUnprefixableSpelling flags a customer-generic-over-customer '
        'type', () {
      final inner = ObjectNode(
        fields: const {'label': ScalarNode(A2uiScalarType.string)},
        required: const {'label'},
        defId: 'package:fixture/fixture.dart#Inner',
        construction: A2uiClassConstruction(
          dartTypeName: 'Inner',
          libraryUri: 'package:fixture/fixture.dart',
          parameters: const [
            A2uiConstructorParameter(name: 'label', named: true),
          ],
        ),
      );
      final box = ObjectNode(
        fields: {'item': inner},
        required: const {'item'},
        defId: 'package:fixture/fixture.dart#Box<Inner>',
        construction: A2uiClassConstruction(
          dartTypeName: 'Box<Inner>',
          libraryUri: 'package:fixture/fixture.dart',
          parameters: const [
            A2uiConstructorParameter(name: 'item', named: true),
          ],
        ),
      );
      final builder = A2uiDataBuilder(
        [box],
        prefixes: const {'package:fixture/fixture.dart': 'p0'},
      );
      expect(builder.firstUnprefixableSpelling(box), 'Box<Inner>');
    });

    test(
        'firstUnprefixableSpelling fails closed on a PHANTOM customer type '
        'argument (not represented as a nested node)', () {
      // `Box<Ghost>` where `Ghost` never appears as a reconstructed field — a
      // phantom/inherited type-argument dependency. It is still a customer type
      // that the leading-identifier prefix cannot qualify, so the guard must
      // fail closed (fail-closed-LOUD), not pass it through bare.
      final box = ObjectNode(
        fields: const {'x': ScalarNode(A2uiScalarType.integer)},
        required: const {'x'},
        defId: 'package:fixture/fixture.dart#Box<Ghost>',
        construction: A2uiClassConstruction(
          dartTypeName: 'Box<Ghost>',
          libraryUri: 'package:fixture/fixture.dart',
          parameters: const [
            A2uiConstructorParameter(name: 'x', named: true),
          ],
        ),
      );
      final builder = A2uiDataBuilder(
        [box],
        prefixes: const {'package:fixture/fixture.dart': 'p0'},
      );
      expect(builder.firstUnprefixableSpelling(box), 'Box<Ghost>');
    });

    test('firstUnprefixableSpelling is null for a dart:core-argument generic',
        () {
      final box = ObjectNode(
        fields: const {'x': ScalarNode(A2uiScalarType.integer)},
        required: const {'x'},
        defId: 'package:fixture/fixture.dart#Box<int>',
        construction: A2uiClassConstruction(
          dartTypeName: 'Box<int>',
          libraryUri: 'package:fixture/fixture.dart',
          parameters: const [
            A2uiConstructorParameter(name: 'x', named: true),
          ],
        ),
      );
      final builder = A2uiDataBuilder(
        [box],
        prefixes: const {'package:fixture/fixture.dart': 'p0'},
      );
      expect(builder.firstUnprefixableSpelling(box), isNull);
    });
  });

  group('supportDefinitions — only what is referenced', () {
    test('a scalar-only builder emits ONLY the typed-cast runtime helper', () {
      final builder = A2uiDataBuilder(const [
        ScalarNode(A2uiScalarType.string),
      ]);
      final defs = builder.supportDefinitions();
      final joined = defs.join('\n');
      expect(
        joined,
        contains('T? _restageA2uiAs<T>(Object? v) => v is T ? v : null;'),
      );
      // No class helpers, no depth ceiling, no map helpers for a scalar root.
      expect(joined, isNot(contains('_kA2uiMaxBuildDepth')));
      expect(joined, isNot(contains('_restageA2uiMap')));
      expect(joined, isNot(contains('_restageA2uiBuild_')));
    });

    test('an empty builder emits nothing', () {
      expect(A2uiDataBuilder(const []).supportDefinitions(), isEmpty);
    });
  });
}
