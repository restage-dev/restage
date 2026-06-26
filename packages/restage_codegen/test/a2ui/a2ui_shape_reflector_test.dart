import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/a2ui/a2ui_shape_reflector.dart';
import 'package:test/test.dart';

import 'shape_reflector_test_support.dart';

/// Reflects the type of `Data.<field>` in [source] and returns the node,
/// failing the test if the reflector scoped the shape out.
Future<A2uiSchemaNode> reflectField(String source, String field) async {
  final type = await resolveFieldType(
    source,
    className: 'Data',
    fieldName: field,
  );
  final result = reflectType(type);
  expect(
    result,
    isA<A2uiShapeResolved>(),
    reason: 'expected $field to resolve, got $result',
  );
  return (result as A2uiShapeResolved).node;
}

void main() {
  group('reflectType — scalars', () {
    const source = '''
      class Data {
        final String name;
        final int count;
        final double ratio;
        final num amount;
        final bool active;
        Data(this.name, this.count, this.ratio, this.amount, this.active);
      }
    ''';

    test('String → ScalarNode(string)', () async {
      expect(
        await reflectField(source, 'name'),
        const ScalarNode(A2uiScalarType.string),
      );
    });

    test('int → ScalarNode(integer)', () async {
      expect(
        await reflectField(source, 'count'),
        const ScalarNode(A2uiScalarType.integer),
      );
    });

    test('double → ScalarNode(number)', () async {
      expect(
        await reflectField(source, 'ratio'),
        const ScalarNode(A2uiScalarType.number),
      );
    });

    test('num → ScalarNode(number)', () async {
      expect(
        await reflectField(source, 'amount'),
        const ScalarNode(A2uiScalarType.number),
      );
    });

    test('bool → ScalarNode(boolean)', () async {
      expect(
        await reflectField(source, 'active'),
        const ScalarNode(A2uiScalarType.boolean),
      );
    });
  });

  group('reflectType — nullability', () {
    const source = '''
      class Data {
        final String? note;
        final String name;
        Data(this.note, this.name);
      }
    ''';

    test('String? → ScalarNode(string, nullable: true)', () async {
      expect(
        await reflectField(source, 'note'),
        const ScalarNode(A2uiScalarType.string, nullable: true),
      );
    });

    test('a non-nullable scalar is nullable: false', () async {
      final node = await reflectField(source, 'name') as ScalarNode;
      expect(node.nullable, isFalse);
    });
  });

  group('reflectType — enums', () {
    const source = '''
      enum Size { small, medium, large }
      class Data {
        final Size size;
        final Size? maybeSize;
        Data(this.size, this.maybeSize);
      }
    ''';

    test('enum field → EnumNode with the resolved member set + identity',
        () async {
      final node = await reflectField(source, 'size') as EnumNode;
      expect(node.members, ['small', 'medium', 'large']);
      expect(node.dartTypeName, 'Size');
      expect(node.libraryUri, isNotNull);
      expect(node.nullable, isFalse);
    });

    test('a nullable enum carries the nullability flag', () async {
      final node = await reflectField(source, 'maybeSize') as EnumNode;
      expect(node.members, ['small', 'medium', 'large']);
      expect(node.nullable, isTrue);
    });
  });

  group('reflectType — lists', () {
    const source = '''
      class Data {
        final List<String> tags;
        final List<int> counts;
        final List<String>? maybeTags;
        Data(this.tags, this.counts, this.maybeTags);
      }
    ''';

    test('List<String> → ListNode(ScalarNode(string))', () async {
      expect(
        await reflectField(source, 'tags'),
        const ListNode(element: ScalarNode(A2uiScalarType.string)),
      );
    });

    test('List<int> → ListNode(ScalarNode(integer))', () async {
      expect(
        await reflectField(source, 'counts'),
        const ListNode(element: ScalarNode(A2uiScalarType.integer)),
      );
    });

    test('a nullable list carries the nullability flag', () async {
      final node = await reflectField(source, 'maybeTags') as ListNode;
      expect(node.nullable, isTrue);
      expect(node.element, const ScalarNode(A2uiScalarType.string));
    });
  });

  group('reflectType — nested objects', () {
    const source = '''
      class Inner {
        final String label;
        final int value;
        final String? note;
        Inner(this.label, this.value, this.note);
      }
      class Data {
        final Inner item;
        final List<Inner> items;
        Data(this.item, this.items);
      }
    ''';

    test('a nested data class → ObjectNode with its fields + required set',
        () async {
      final node = await reflectField(source, 'item') as ObjectNode;
      expect(node.fields.keys, ['label', 'value', 'note']);
      expect(node.fields['label'], const ScalarNode(A2uiScalarType.string));
      expect(node.fields['value'], const ScalarNode(A2uiScalarType.integer));
      expect(
        node.fields['note'],
        const ScalarNode(A2uiScalarType.string, nullable: true),
      );
      // required = the constructor's required params (here all three positional
      // params must be provided — a nullable-but-required param is required).
      expect(node.required, {'label', 'value', 'note'});
      expect(node.defId, isNotNull);
    });

    test('List<Inner> → ListNode(ObjectNode) (a list of objects)', () async {
      final node = await reflectField(source, 'items') as ListNode;
      final element = node.element as ObjectNode;
      expect(element.fields.keys, ['label', 'value', 'note']);
    });

    test('a computed getter is not reflected as a data field', () async {
      const withGetter = '''
        class Inner {
          final String label;
          Inner(this.label);
          String get shouted => label.toUpperCase();
        }
        class Data {
          final Inner item;
          Data(this.item);
        }
      ''';
      final node = await reflectField(withGetter, 'item') as ObjectNode;
      expect(node.fields.keys, ['label']);
      expect(node.fields.containsKey('shouted'), isFalse);
    });

    test('static + non-constructor private fields are not reflected', () async {
      const withNoise = '''
        class Inner {
          static const int kVersion = 1;
          final String _secret;
          final String label;
          Inner(this.label) : _secret = 'x';
        }
        class Data {
          final Inner item;
          Data(this.item);
        }
      ''';
      final node = await reflectField(withNoise, 'item') as ObjectNode;
      expect(node.fields.keys, ['label']);
    });
  });

  group('reflectType — String-keyed maps', () {
    const source = '''
      class Data {
        final Map<String, int> counts;
        final Map<String, String> labels;
        Data(this.counts, this.labels);
      }
    ''';

    test('Map<String, int> → MapNode(ScalarNode(integer))', () async {
      expect(
        await reflectField(source, 'counts'),
        const MapNode(valueType: ScalarNode(A2uiScalarType.integer)),
      );
    });

    test('Map<String, String> → MapNode(ScalarNode(string))', () async {
      expect(
        await reflectField(source, 'labels'),
        const MapNode(valueType: ScalarNode(A2uiScalarType.string)),
      );
    });
  });

  group('reflectType — named records', () {
    const source = '''
      class Data {
        final ({int x, String y}) point;
        Data(this.point);
      }
    ''';

    test('a named record → ObjectNode over its named fields', () async {
      final node = await reflectField(source, 'point') as ObjectNode;
      expect(node.fields.keys, ['x', 'y']);
      expect(node.fields['x'], const ScalarNode(A2uiScalarType.integer));
      expect(node.fields['y'], const ScalarNode(A2uiScalarType.string));
      expect(node.required, {'x', 'y'});
    });
  });

  group('reflectType — recursion', () {
    test('a self-recursive type breaks the cycle with a RefNode', () async {
      const source = '''
        class TreeNode {
          final String label;
          final List<TreeNode> children;
          TreeNode(this.label, this.children);
        }
        class Data {
          final TreeNode root;
          Data(this.root);
        }
      ''';
      final root = await reflectField(source, 'root') as ObjectNode;
      expect(root.fields['label'], const ScalarNode(A2uiScalarType.string));
      final children = root.fields['children']! as ListNode;
      // The recursive reference is a RefNode keyed to the object's defId,
      // not an infinite re-expansion.
      final ref = children.element as RefNode;
      expect(ref.defId, root.defId);
    });
  });

  group('reflectType — scope-outs encountered while reading shapes', () {
    test('a non-String-key map → scope-out (nonStringKeyMap)', () async {
      const source = '''
        class Data {
          final Map<int, String> byId;
          Data(this.byId);
        }
      ''';
      final type = await resolveFieldType(
        source,
        className: 'Data',
        fieldName: 'byId',
      );
      final result = reflectType(type);
      expect(
        result,
        isA<A2uiShapeScopedOut>().having(
          (s) => s.reason,
          'reason',
          A2uiShapeScopeOutReason.nonStringKeyMap,
        ),
      );
    });

    test('a positional record → scope-out (positionalRecord)', () async {
      const source = '''
        class Data {
          final (int, String) pair;
          Data(this.pair);
        }
      ''';
      final type = await resolveFieldType(
        source,
        className: 'Data',
        fieldName: 'pair',
      );
      final result = reflectType(type);
      expect(
        result,
        isA<A2uiShapeScopedOut>().having(
          (s) => s.reason,
          'reason',
          A2uiShapeScopeOutReason.positionalRecord,
        ),
      );
    });
  });

  group('the governing invariant — the OUT set (fail-closed-LOUD)', () {
    Future<A2uiShapeResult> reflect(String source, String field) async {
      final type = await resolveFieldType(
        source,
        className: 'Data',
        fieldName: field,
      );
      return reflectType(type);
    }

    Matcher scopedOut(A2uiShapeScopeOutReason reason) =>
        isA<A2uiShapeScopedOut>()
            .having((s) => s.reason, 'reason', reason)
            .having((s) => s.typeDescription, 'typeDescription', isNotEmpty);

    test('dynamic → scope-out (dynamicOrObject)', () async {
      const source = '''
        class Data {
          final dynamic anything;
          Data(this.anything);
        }
      ''';
      expect(
        await reflect(source, 'anything'),
        scopedOut(A2uiShapeScopeOutReason.dynamicOrObject),
      );
    });

    test('Object → scope-out (dynamicOrObject)', () async {
      const source = '''
        class Data {
          final Object thing;
          Data(this.thing);
        }
      ''';
      expect(
        await reflect(source, 'thing'),
        scopedOut(A2uiShapeScopeOutReason.dynamicOrObject),
      );
    });

    test('an unbound type parameter → scope-out (unboundGeneric)', () async {
      const source = '''
        class Data<T> {
          final T value;
          Data(this.value);
        }
      ''';
      expect(
        await reflect(source, 'value'),
        scopedOut(A2uiShapeScopeOutReason.unboundGeneric),
      );
    });

    test('one OUT field scopes the whole enclosing object out (loud)',
        () async {
      const source = '''
        class Inner {
          final String label;
          final dynamic blob;
          Inner(this.label, this.blob);
        }
        class Data {
          final Inner item;
          Data(this.item);
        }
      ''';
      // The object is NOT partially emitted with the bad field silently
      // dropped — the whole shape fails closed, loud.
      expect(
        await reflect(source, 'item'),
        scopedOut(A2uiShapeScopeOutReason.dynamicOrObject),
      );
    });
  });

  group('the reclassifications (NOT data scope-outs)', () {
    test('a function/callback field is the event surface, not a data scope-out',
        () async {
      const source = '''
        class Data {
          final void Function() onTap;
          Data(this.onTap);
        }
      ''';
      final type = await resolveFieldType(
        source,
        className: 'Data',
        fieldName: 'onTap',
      );
      final result = reflectType(type);
      // A callback routes to the interactivity layer (Phase 2), and is NOT
      // emitted as an unsupported-data diagnostic.
      expect(result, isA<A2uiShapeEventSurface>());
      expect(result, isNot(isA<A2uiShapeScopedOut>()));
    });

    test('a concrete generic instantiation resolves → IN', () async {
      const source = '''
        class Data {
          final List<String> tags;
          final Map<String, int> counts;
          Data(this.tags, this.counts);
        }
      ''';
      // Concrete instantiations of generic built-ins resolve and are accepted,
      // unlike unbound type parameters.
      expect(await reflectField(source, 'tags'), isA<ListNode>());
      expect(await reflectField(source, 'counts'), isA<MapNode>());
    });
  });

  group('the positive data-class gate (no silent guesses)', () {
    Future<A2uiShapeResult> reflect(String source, String field) async {
      final type = await resolveFieldType(
        source,
        className: 'Data',
        fieldName: field,
      );
      return reflectType(type);
    }

    Matcher scopedOut(A2uiShapeScopeOutReason reason) =>
        isA<A2uiShapeScopedOut>().having((s) => s.reason, 'reason', reason);

    test('a bare Function field is the event surface, not an empty object',
        () async {
      const source = '''
        class Data {
          final Function callback;
          Data(this.callback);
        }
      ''';
      expect(await reflect(source, 'callback'), isA<A2uiShapeEventSurface>());
    });

    test(
        'a record with a PRIVATE field label → loud scope-out (unspellable '
        'cross-library)', () async {
      const source = '''
        class Data {
          final ({String label, int _count}) meta;
          Data(this.meta);
        }
      ''';
      // A `(_count: …)` literal in the generated separate library is a
      // different record type than the customer's — fail closed, never emit
      // unassignable source.
      expect(
        await reflect(source, 'meta'),
        scopedOut(A2uiShapeScopeOutReason.unsupported),
      );
    });

    test('a non-data dart: type (Set) → loud scope-out, not an empty object',
        () async {
      const source = '''
        class Data {
          final Set<int> ids;
          Data(this.ids);
        }
      ''';
      expect(
        await reflect(source, 'ids'),
        scopedOut(A2uiShapeScopeOutReason.unsupported),
      );
    });

    test('a Future field → loud scope-out', () async {
      const source = '''
        class Data {
          final Future<int> pending;
          Data(this.pending);
        }
      ''';
      expect(
        await reflect(source, 'pending'),
        scopedOut(A2uiShapeScopeOutReason.unsupported),
      );
    });

    test('Map<String, Function> → loud scope-out, NOT MapNode(empty object)',
        () async {
      const source = '''
        class Data {
          final Map<String, void Function()> handlers;
          Data(this.handlers);
        }
      ''';
      expect(
        await reflect(source, 'handlers'),
        scopedOut(A2uiShapeScopeOutReason.unsupported),
      );
    });

    test('List<Function> → loud scope-out (container over a non-data element)',
        () async {
      const source = '''
        class Data {
          final List<void Function()> taps;
          Data(this.taps);
        }
      ''';
      expect(
        await reflect(source, 'taps'),
        scopedOut(A2uiShapeScopeOutReason.unsupported),
      );
    });

    test('an abstract base → DEFERRED union reason (not structural)', () async {
      const source = '''
        abstract class Shape {}
        class Data {
          final Shape shape;
          Data(this.shape);
        }
      ''';
      expect(
        await reflect(source, 'shape'),
        scopedOut(A2uiShapeScopeOutReason.sealedUnionDeferred),
      );
    });

    test('a sealed base → DEFERRED union reason', () async {
      const source = '''
        sealed class Node {}
        class Data {
          final Node node;
          Data(this.node);
        }
      ''';
      expect(
        await reflect(source, 'node'),
        scopedOut(A2uiShapeScopeOutReason.sealedUnionDeferred),
      );
    });
  });

  group('constructor-based field reading (no silent drops)', () {
    test('a superclass (super.x) field is carried, not dropped', () async {
      const source = '''
        class Base {
          final String id;
          Base(this.id);
        }
        class Derived extends Base {
          final int n;
          Derived(this.n, {required super.id});
        }
        class Data {
          final Derived item;
          Data(this.item);
        }
      ''';
      final node = await reflectField(source, 'item') as ObjectNode;
      expect(node.fields.keys, containsAll(<String>['n', 'id']));
      expect(node.fields['id'], const ScalarNode(A2uiScalarType.string));
      expect(node.required, containsAll(<String>['n', 'id']));
    });

    test(
        'a concrete customer generic (Box<int>) resolves IN with int '
        'substituted', () async {
      const source = '''
        class Box<T> {
          final T value;
          final String label;
          Box(this.value, this.label);
        }
        class Data {
          final Box<int> box;
          Data(this.box);
        }
      ''';
      final node = await reflectField(source, 'box') as ObjectNode;
      expect(node.fields['value'], const ScalarNode(A2uiScalarType.integer));
      expect(node.fields['label'], const ScalarNode(A2uiScalarType.string));
    });

    test('prefers the unnamed generative constructor when several exist',
        () async {
      const source = '''
        class WithPrimary {
          final String a;
          WithPrimary(this.a);
          WithPrimary.alt() : a = 'x';
        }
        class Data {
          final WithPrimary item;
          Data(this.item);
        }
      ''';
      final node = await reflectField(source, 'item') as ObjectNode;
      expect(node.fields.keys, ['a']);
    });

    test(
        'an ambiguous constructor set (named-only) → loud scope-out, never '
        'an arbitrary pick', () async {
      const source = '''
        class MultiCtor {
          final String a;
          MultiCtor.first(this.a);
          MultiCtor.second(this.a);
        }
        class Data {
          final MultiCtor item;
          Data(this.item);
        }
      ''';
      final type = await resolveFieldType(
        source,
        className: 'Data',
        fieldName: 'item',
      );
      expect(
        reflectType(type),
        isA<A2uiShapeScopedOut>().having(
          (s) => s.reason,
          'reason',
          A2uiShapeScopeOutReason.unsupported,
        ),
      );
    });

    test('a nullable String key (Map<String?, V>) → nonStringKeyMap', () async {
      const source = '''
        class Data {
          final Map<String?, int> byKey;
          Data(this.byKey);
        }
      ''';
      final type = await resolveFieldType(
        source,
        className: 'Data',
        fieldName: 'byKey',
      );
      expect(
        reflectType(type),
        isA<A2uiShapeScopedOut>().having(
          (s) => s.reason,
          'reason',
          A2uiShapeScopeOutReason.nonStringKeyMap,
        ),
      );
    });
  });

  group('Pass-2 hardening (deeper fail-open edges)', () {
    Future<A2uiShapeResult> reflect(String source, String field) async {
      final type = await resolveFieldType(
        source,
        className: 'Data',
        fieldName: field,
      );
      return reflectType(type);
    }

    Matcher scopedOutUnsupported() => isA<A2uiShapeScopedOut>().having(
          (s) => s.reason,
          'reason',
          A2uiShapeScopeOutReason.unsupported,
        );

    test(
        'a callback field INSIDE a data object → the object scopes out loud, '
        'not silently dropped', () async {
      const source = '''
        class Inner {
          final String label;
          final void Function() onTap;
          Inner(this.label, this.onTap);
        }
        class Data {
          final Inner item;
          Data(this.item);
        }
      ''';
      expect(await reflect(source, 'item'), scopedOutUnsupported());
    });

    test(
        'a computed getter colliding with a ctor-param name does not mistype '
        'the field (uses the param type)', () async {
      const source = '''
        class Inner {
          final String stored;
          int get count => stored.length;
          Inner(String count) : stored = count;
        }
        class Data {
          final Inner item;
          Data(this.item);
        }
      ''';
      final node = await reflectField(source, 'item') as ObjectNode;
      // The ctor param `count` is a String; the same-named computed getter
      // (int) must NOT mistype it.
      expect(node.fields['count'], const ScalarNode(A2uiScalarType.string));
    });

    test(
        'Box<String> and Box<String?> get distinct canonical defIds '
        '(type-arg nullability is part of the shape)', () async {
      const source = '''
        class Box<T> {
          final T value;
          Box(this.value);
        }
        class Data {
          final Box<String> a;
          final Box<String?> b;
          Data(this.a, this.b);
        }
      ''';
      final a = await reflectField(source, 'a') as ObjectNode;
      final b = await reflectField(source, 'b') as ObjectNode;
      expect(a.defId, isNotNull);
      expect(a.defId, isNot(b.defId));
    });

    test(
        'a class with only a private (or factory) constructor → loud scope-out',
        () async {
      const source = '''
        class Secret {
          final String x;
          Secret._(this.x);
          factory Secret.make() => Secret._('a');
        }
        class Data {
          final Secret s;
          Data(this.s);
        }
      ''';
      expect(await reflect(source, 's'), scopedOutUnsupported());
    });

    test(
        'a REQUIRED private constructor parameter → loud scope-out (the '
        'object is unconstructable)', () async {
      const source = '''
        class Inner {
          final String _secret;
          final String label;
          Inner({required String secret, required this.label}) : _secret = secret;
          String get secretLen => _secret;
        }
        class Data {
          final Inner item;
          Data(this.item);
        }
      ''';
      // `secret` is public-named here (it resolves); the genuinely-private
      // REQUIRED case below is a private field-formal.
      expect(await reflectField(source, 'item'), isA<ObjectNode>());

      const privateRequired = '''
        class Inner {
          final String _token;
          Inner({required this._token});
        }
        class Data {
          final Inner item;
          Data(this.item);
        }
      ''';
      expect(await reflect(privateRequired, 'item'), scopedOutUnsupported());
    });
  });

  group('reflectType — ObjectNode construction info', () {
    test(
        'a named-constructor data class carries its type, library, and '
        'named params in declaration order', () async {
      const source = '''
        class Inner {
          final String label;
          final int count;
          const Inner({required this.label, this.count = 0});
        }
        class Data {
          final Inner item;
          Data(this.item);
        }
      ''';
      final node = await reflectField(source, 'item') as ObjectNode;
      final ctor = node.construction! as A2uiClassConstruction;
      expect(ctor.dartTypeName, 'Inner');
      expect(ctor.libraryUri, isNotNull);
      expect(ctor.parameters.map((p) => p.name).toList(), ['label', 'count']);
      expect(ctor.parameters.every((p) => p.named), isTrue);
    });

    test(
        'a positional-constructor data class records positional params in '
        'order', () async {
      const source = '''
        class Point {
          final int x;
          final int y;
          Point(this.x, this.y);
        }
        class Data {
          final Point p;
          Data(this.p);
        }
      ''';
      final node = await reflectField(source, 'p') as ObjectNode;
      final ctor = node.construction! as A2uiClassConstruction;
      expect(ctor.dartTypeName, 'Point');
      expect(ctor.parameters.map((p) => p.name).toList(), ['x', 'y']);
      expect(ctor.parameters.every((p) => !p.named), isTrue);
    });

    test('a concrete generic data class carries its instantiated type spelling',
        () async {
      // The reflector substitutes Box<int>'s field types; the construction must
      // also carry the instantiated spelling `Box<int>` (not the raw `Box`), so
      // the value-builder emits type-correct source (a raw `Box` would not be
      // assignable to a `Box<int>` parameter).
      const source = '''
        class Box<T extends num> {
          final T value;
          Box(this.value);
        }
        class Data {
          final Box<int> box;
          Data(this.box);
        }
      ''';
      final node = await reflectField(source, 'box') as ObjectNode;
      final ctor = node.construction! as A2uiClassConstruction;
      expect(ctor.dartTypeName, 'Box<int>');
      expect(node.fields['value'], const ScalarNode(A2uiScalarType.integer));
    });

    test('a named record carries record construction (no Dart type name)',
        () async {
      const source = '''
        class Data {
          final ({int x, String y}) point;
          Data(this.point);
        }
      ''';
      final node = await reflectField(source, 'point') as ObjectNode;
      expect(node.construction, isA<A2uiRecordConstruction>());
    });

    test('a list-of-objects carries construction on the element', () async {
      const source = '''
        class Inner {
          final String label;
          Inner(this.label);
        }
        class Data {
          final List<Inner> items;
          Data(this.items);
        }
      ''';
      final node = await reflectField(source, 'items') as ListNode;
      final element = node.element as ObjectNode;
      final ctor = element.construction! as A2uiClassConstruction;
      expect(ctor.dartTypeName, 'Inner');
      expect(ctor.parameters.map((p) => p.name).toList(), ['label']);
    });
  });

  // The value-builder reconstructs runtime values fail-safe; two shapes have
  // no statically-synthesizable fallback, so they fail closed at the reflector
  // (never a schema the builder can't reconstruct → no schema/builder
  // divergence). Both carry a DEFERRED reason (a should-be-IN capability), not
  // a structural one.
  group('reflectType — value-builder buildability scope-outs', () {
    Future<A2uiShapeResult> reflect(String source, String field) async {
      final type = await resolveFieldType(
        source,
        className: 'Data',
        fieldName: field,
      );
      return reflectType(type);
    }

    Matcher scopedOut(A2uiShapeScopeOutReason reason) =>
        isA<A2uiShapeScopedOut>()
            .having((s) => s.reason, 'reason', reason)
            .having((s) => s.typeDescription, 'typeDescription', isNotEmpty);

    test('an all-scalar/enum record still resolves', () async {
      const source = '''
        enum Tone { soft, loud }
        class Data {
          final ({String title, Tone tone}) header;
          Data(this.header);
        }
      ''';
      final node = await reflectField(source, 'header') as ObjectNode;
      expect(node.construction, isA<A2uiRecordConstruction>());
      expect(node.fields.keys, ['title', 'tone']);
    });

    test('a record with a nested-object field → recordNonScalarFieldDeferred',
        () async {
      const source = '''
        class Inner {
          final String label;
          Inner(this.label);
        }
        class Data {
          final ({String title, Inner body}) header;
          Data(this.header);
        }
      ''';
      expect(
        await reflect(source, 'header'),
        scopedOut(A2uiShapeScopeOutReason.recordNonScalarFieldDeferred),
      );
    });

    test('a record with a list field → recordNonScalarFieldDeferred', () async {
      const source = '''
        class Data {
          final ({String title, List<String> tags}) header;
          Data(this.header);
        }
      ''';
      expect(
        await reflect(source, 'header'),
        scopedOut(A2uiShapeScopeOutReason.recordNonScalarFieldDeferred),
      );
    });

    test(
        'an optional non-null nested-object param → '
        'optionalObjectParamDeferred', () async {
      // `Data.config` is optional (has a default), non-nullable, and an object
      // → no statically-synthesizable fallback → loud deferred scope-out.
      const source = '''
        class Inner {
          final String label;
          const Inner(this.label);
        }
        class Data {
          final Inner config;
          const Data({this.config = const Inner('x')});
        }
        class Holder {
          final Data data;
          Holder(this.data);
        }
      ''';
      expect(
        await reflectViaOwner(source, 'Holder', 'data'),
        scopedOut(A2uiShapeScopeOutReason.optionalObjectParamDeferred),
      );
    });

    test('an optional NULLABLE object param resolves (null is the fallback)',
        () async {
      const source = '''
        class Inner {
          final String label;
          const Inner(this.label);
        }
        class Data {
          final Inner? config;
          const Data({this.config});
        }
        class Holder {
          final Data data;
          Holder(this.data);
        }
      ''';
      final node = await reflectViaOwnerResolved(source, 'Holder', 'data');
      final config = (node as ObjectNode).fields['config']! as ObjectNode;
      expect(config.nullable, isTrue);
      expect(node.required, isNot(contains('config')));
    });

    // The value-builder emits the type's spelling (helper return / constructor /
    // whereType) into a SEPARATE generated library, so an unspellable /
    // unimportable name (a private type, an unbound/phantom type argument) must
    // fail closed at the reflector — never an emit that cannot compile.
    test('a private data class → scope-out (not referenceable cross-library)',
        () async {
      const source = '''
        class _Private {
          final String label;
          _Private(this.label);
        }
        class Data {
          final _Private item;
          Data(this.item);
        }
      ''';
      expect(
        await reflect(source, 'item'),
        scopedOut(A2uiShapeScopeOutReason.unsupported),
      );
    });

    test('a private TYPE ARGUMENT → scope-out (the spelling is unimportable)',
        () async {
      const source = '''
        class _P {
          final int x;
          _P(this.x);
        }
        class Box<T> {
          final int count;
          Box(this.count);
        }
        class Data {
          final Box<_P> box;
          Data(this.box);
        }
      ''';
      expect(
        await reflect(source, 'box'),
        scopedOut(A2uiShapeScopeOutReason.unsupported),
      );
    });

    test('a private enum → scope-out (the spelling is unimportable)', () async {
      const source = '''
        enum _Tone { soft, loud }
        class Data {
          final _Tone tone;
          Data(this.tone);
        }
      ''';
      expect(
        await reflect(source, 'tone'),
        scopedOut(A2uiShapeScopeOutReason.unsupported),
      );
    });

    test('a phantom/unbound type argument → scope-out (T not in scope)',
        () async {
      const source = '''
        class Box<T> {
          final String label;
          Box(this.label);
        }
        class Data<T> {
          final Box<T> box;
          Data(this.box);
        }
      ''';
      // Data is read UN-instantiated, so `box` is `Box<T>` with the open T.
      expect(
        await reflect(source, 'box'),
        scopedOut(A2uiShapeScopeOutReason.unsupported),
      );
    });

    test('an optional non-null SCALAR param resolves (defaultable)', () async {
      const source = '''
        class Data {
          final int count;
          const Data({this.count = 3});
        }
        class Holder {
          final Data data;
          Holder(this.data);
        }
      ''';
      final node =
          await reflectViaOwnerResolved(source, 'Holder', 'data') as ObjectNode;
      expect(node.fields['count'], const ScalarNode(A2uiScalarType.integer));
      expect(node.required, isNot(contains('count')));
    });
  });

  group('reflectType — callback signatures (Phase-2 interactivity)', () {
    // The event surface now carries the callback signature the Phase-2 lowering
    // reads: a 0-arg callback dispatches an event; a single-value
    // `ValueChanged<T>` writes the value back; any other shape is unsupported
    // (fail-loud before lowering, never mis-lowered to dispatch). ValueChanged
    // is spelled as `void Function(T)` so the fixtures need no Flutter import.
    Future<A2uiCallbackSignature> signatureOf(
      String source,
      String field,
    ) async {
      final type =
          await resolveFieldType(source, className: 'Data', fieldName: field);
      final result = reflectType(type);
      expect(
        result,
        isA<A2uiShapeEventSurface>(),
        reason: 'expected $field to be the event surface, got $result',
      );
      return (result as A2uiShapeEventSurface).signature;
    }

    test('ValueChanged<bool> (void Function(bool)) → write-back(boolean)',
        () async {
      const source = '''
        class Data {
          final void Function(bool) onChanged;
          Data(this.onChanged);
        }
      ''';
      expect(
        await signatureOf(source, 'onChanged'),
        const A2uiCallbackWriteBack(
          A2uiScalarType.boolean,
          nullable: false,
          isList: false,
        ),
      );
    });

    test('ValueChanged<bool?> → write-back(boolean, nullable)', () async {
      const source = '''
        class Data {
          final void Function(bool?) onChanged;
          Data(this.onChanged);
        }
      ''';
      expect(
        await signatureOf(source, 'onChanged'),
        const A2uiCallbackWriteBack(
          A2uiScalarType.boolean,
          nullable: true,
          isList: false,
        ),
      );
    });

    test('ValueChanged<String> → write-back(string)', () async {
      const source = '''
        class Data {
          final void Function(String) onChanged;
          Data(this.onChanged);
        }
      ''';
      expect(
        await signatureOf(source, 'onChanged'),
        const A2uiCallbackWriteBack(
          A2uiScalarType.string,
          nullable: false,
          isList: false,
        ),
      );
    });

    test('VoidCallback (void Function()) → dispatch', () async {
      const source = '''
        class Data {
          final void Function() onTap;
          Data(this.onTap);
        }
      ''';
      expect(await signatureOf(source, 'onTap'), const A2uiCallbackDispatch());
    });

    test('ValueChanged<List<String>> → write-back(string, isList)', () async {
      const source = '''
        class Data {
          final void Function(List<String>) onChanged;
          Data(this.onChanged);
        }
      ''';
      expect(
        await signatureOf(source, 'onChanged'),
        const A2uiCallbackWriteBack(
          A2uiScalarType.string,
          nullable: false,
          isList: true,
        ),
      );
    });

    test('a multi-arg callback → unsupported (never mis-lowered to dispatch)',
        () async {
      const source = '''
        class Data {
          final void Function(int, int) onResize;
          Data(this.onResize);
        }
      ''';
      expect(
        await signatureOf(source, 'onResize'),
        isA<A2uiCallbackUnsupported>(),
      );
    });

    test('ValueChanged<List<non-scalar>> → unsupported (#L by construction)',
        () async {
      // The leaf-list element MUST be a scalar: a non-scalar element fails
      // closed at the reflector, never a write-back. So a list write-back value
      // is always a `List<scalar>` — never a list of maps — and the
      // `{path}`/`{call}` map-pattern hazard cannot arise on a list value.
      const source = '''
        class Data {
          final void Function(List<Object>) onChanged;
          Data(this.onChanged);
        }
      ''';
      expect(
        await signatureOf(source, 'onChanged'),
        isA<A2uiCallbackUnsupported>(),
      );
    });

    test('a non-scalar value callback → unsupported', () async {
      const source = '''
        class Data {
          final void Function(Object) onChanged;
          Data(this.onChanged);
        }
      ''';
      expect(
        await signatureOf(source, 'onChanged'),
        isA<A2uiCallbackUnsupported>(),
      );
    });

    test('a single NAMED-arg callback is not a ValueChanged → unsupported',
        () async {
      const source = '''
        class Data {
          final void Function({bool value}) onChanged;
          Data(this.onChanged);
        }
      ''';
      expect(
        await signatureOf(source, 'onChanged'),
        isA<A2uiCallbackUnsupported>(),
      );
    });

    test('a bare Function carries an unsupported signature', () async {
      const source = '''
        class Data {
          final Function callback;
          Data(this.callback);
        }
      ''';
      expect(
        await signatureOf(source, 'callback'),
        isA<A2uiCallbackUnsupported>(),
      );
    });

    test('a non-void single-arg callback → unsupported (not ValueChanged)',
        () async {
      // `int Function(bool)` returns a value — not a `void` setter — so it must
      // NOT lower to a write-back (whose lambda returns void and would be
      // unassignable).
      const source = '''
        class Data {
          final int Function(bool) onChanged;
          Data(this.onChanged);
        }
      ''';
      expect(
        await signatureOf(source, 'onChanged'),
        isA<A2uiCallbackUnsupported>(),
      );
    });

    test('a non-void 0-arg callback → unsupported (not VoidCallback)',
        () async {
      const source = '''
        class Data {
          final bool Function() onTap;
          Data(this.onTap);
        }
      ''';
      expect(
        await signatureOf(source, 'onTap'),
        isA<A2uiCallbackUnsupported>(),
      );
    });

    test('an optional-positional value callback → unsupported (not required)',
        () async {
      // `void Function([bool])` has no required value argument — not the
      // ValueChanged shape.
      const source = '''
        class Data {
          final void Function([bool]) onChanged;
          Data(this.onChanged);
        }
      ''';
      expect(
        await signatureOf(source, 'onChanged'),
        isA<A2uiCallbackUnsupported>(),
      );
    });
  });
}

/// Reflects the type of `<owner>.<field>` in [source] (an owner class wrapping
/// the class-under-test), returning the raw result.
Future<A2uiShapeResult> reflectViaOwner(
  String source,
  String owner,
  String field,
) async {
  final type =
      await resolveFieldType(source, className: owner, fieldName: field);
  return reflectType(type);
}

/// As [reflectViaOwner], asserting the result resolved and returning its node.
Future<A2uiSchemaNode> reflectViaOwnerResolved(
  String source,
  String owner,
  String field,
) async {
  final result = await reflectViaOwner(source, owner, field);
  expect(result, isA<A2uiShapeResolved>(), reason: 'got $result');
  return (result as A2uiShapeResolved).node;
}
