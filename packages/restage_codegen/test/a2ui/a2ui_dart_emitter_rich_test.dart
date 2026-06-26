import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// A nested-data-class node modelling `PlanTier({required String tier,
/// double price})` defined in a customer library.
ObjectNode _planTierNode({bool nullable = false}) => ObjectNode(
      fields: const {
        'tier': ScalarNode(A2uiScalarType.string),
        'price': ScalarNode(A2uiScalarType.number),
      },
      required: const {'tier'},
      defId: 'package:fixture/fixture.dart#PlanTier',
      nullable: nullable,
      construction: A2uiClassConstruction(
        dartTypeName: 'PlanTier',
        libraryUri: 'package:fixture/fixture.dart',
        parameters: const [
          A2uiConstructorParameter(name: 'tier', named: true),
          A2uiConstructorParameter(name: 'price', named: true),
        ],
      ),
    );

void main() {
  group('richShapes — classify', () {
    test('a property with a rich shape becomes a rich A2uiDataField', () {
      final catalog = catalogWith([
        entry(
          name: 'PlanCard',
          flutterType: 'package:fixture/fixture.dart#PlanCard',
          properties: [prop('plan', PropertyType.structured, required: true)],
        ),
      ]);

      final plan = classifyA2uiCatalogDart(
        catalog,
        richShapes: {('PlanCard', 'plan'): _planTierNode()},
      );

      expect(plan.widgets, hasLength(1));
      final field = plan.widgets.single.fields.single;
      final emission = field.emission;
      expect(emission, isA<A2uiDataField>());
      expect((emission as A2uiDataField).rich, isTrue);
      expect(emission.node, _planTierNode());
    });

    test('without a rich shape the property keeps the catalog path', () {
      final catalog = catalogWith([
        entry(
          name: 'Banner',
          properties: [prop('title', PropertyType.string)],
        ),
      ]);

      final plan = classifyA2uiCatalogDart(catalog);
      final emission = plan.widgets.single.fields.single.emission;
      expect(emission, isA<A2uiDataField>());
      expect((emission as A2uiDataField).rich, isFalse);
    });
  });

  group('richShapes — ObjectNode (class) construction', () {
    test(
        'a required nested-data-class arg binds via BoundObject and '
        'reconstructs, failing the widget safe on null', () {
      final catalog = catalogWith([
        entry(
          name: 'PlanCard',
          flutterType: 'package:fixture/fixture.dart#PlanCard',
          properties: [prop('plan', PropertyType.structured, required: true)],
        ),
      ]);

      final source = emitA2uiCatalogDart(
        catalog,
        richShapes: {('PlanCard', 'plan'): _planTierNode()},
      );

      // Schema: the nested object projects to S.object with its fields (the
      // formatter may wrap S.object( onto its own line, so assert the pieces).
      expect(source, contains("'plan': S.object("));
      expect(source, contains("'tier': S.string()"));
      expect(source, contains("'price': S.number()"));
      expect(source, contains("required: <String>['tier']"));
      // Builder: a rich nested object is reconstructed DIRECTLY from the
      // widget data (no BoundObject — its binding-sentinel patterns would
      // misread a literal object with a `path`/`call` field), then fails the
      // WIDGET safe (SizedBox.shrink) on a null required reconstruction —
      // never a force-unwrap.
      expect(source, isNot(contains('BoundObject(')));
      expect(source, contains('final _restageA2uiArg_plan ='));
      expect(source, contains("_restageA2uiBuild_PlanTier(data['plan'], 0)"));
      expect(
        source,
        contains(
          'if (_restageA2uiArg_plan == null) return const SizedBox.shrink();',
        ),
      );
      expect(source, contains('plan: _restageA2uiArg_plan,'));
      // The value-builder support definitions are emitted once.
      expect(source, contains('PlanTier? _restageA2uiBuild_PlanTier('));
      expect(source, contains('T? _restageA2uiAs<T>('));
    });

    test('a required-but-NULLABLE object arg passes through (no guard)', () {
      final catalog = catalogWith([
        entry(
          name: 'PlanCard',
          flutterType: 'package:fixture/fixture.dart#PlanCard',
          properties: [prop('plan', PropertyType.structured, required: true)],
        ),
      ]);

      final source = emitA2uiCatalogDart(
        catalog,
        richShapes: {('PlanCard', 'plan'): _planTierNode(nullable: true)},
      );

      // A nullable arg accepts null, so the reconstruction passes through —
      // never a SizedBox fail-safe (the widget asked for a nullable value).
      expect(source, contains('final _restageA2uiArg_plan ='));
      expect(source, contains("_restageA2uiBuild_PlanTier(data['plan'], 0)"));
      expect(source, isNot(contains('return const SizedBox.shrink();')));
      expect(source, contains('plan: _restageA2uiArg_plan,'));
    });

    test('a required RECORD arg fails the widget safe when missing/malformed',
        () {
      final recordNode = ObjectNode(
        fields: const {
          'title': ScalarNode(A2uiScalarType.string),
          'count': ScalarNode(A2uiScalarType.integer),
        },
        required: const {'title', 'count'},
        construction: const A2uiRecordConstruction(),
      );
      final catalog = catalogWith([
        entry(
          name: 'HeaderCard',
          flutterType: 'package:fixture/fixture.dart#HeaderCard',
          properties: [prop('header', PropertyType.structured, required: true)],
        ),
      ]);

      final source = emitA2uiCatalogDart(
        catalog,
        richShapes: {('HeaderCard', 'header'): recordNode},
      );

      // A non-null record reconstructs to null when its raw is not a map, so a
      // required record arg fails the widget safe (SizedBox.shrink) rather than
      // fabricating a record from per-field fallbacks.
      expect(source, contains('final _restageA2uiArg_header ='));
      expect(source, contains('title:'));
      expect(source, isNot(contains('BoundObject(')));
      expect(
        source,
        contains(
          'if (_restageA2uiArg_header == null) '
          'return const SizedBox.shrink();',
        ),
      );
      expect(source, contains('header: _restageA2uiArg_header,'));
    });

    test('a String-keyed map arg reconstructs via the map helper', () {
      final catalog = catalogWith([
        entry(
          name: 'Counters',
          flutterType: 'package:fixture/fixture.dart#Counters',
          properties: [prop('counts', PropertyType.structured, required: true)],
        ),
      ]);

      final source = emitA2uiCatalogDart(
        catalog,
        richShapes: {
          ('Counters', 'counts'): const MapNode(
            valueType: ScalarNode(A2uiScalarType.integer),
          ),
        },
      );

      // Map → S.object(additionalProperties: ...) schema + the drop-null map
      // helper reconstruction read directly from the widget data.
      expect(source, contains('S.object(additionalProperties: S.integer())'));
      expect(source, isNot(contains('BoundObject(')));
      expect(source, contains('_restageA2uiMap<int>('));
      expect(source, contains("data['counts']"));
      expect(source, contains('Map<String, V>? _restageA2uiMap<V>('));
    });

    test('a list-of-objects arg reconstructs element-by-element', () {
      final catalog = catalogWith([
        entry(
          name: 'PlanList',
          flutterType: 'package:fixture/fixture.dart#PlanList',
          properties: [prop('plans', PropertyType.structured, required: true)],
        ),
      ]);

      final source = emitA2uiCatalogDart(
        catalog,
        richShapes: {('PlanList', 'plans'): ListNode(element: _planTierNode())},
      );

      // List-of-objects → S.list over the element S.object (formatter may wrap
      // S.list( onto its own line).
      expect(source, contains('S.list('));
      expect(source, contains("'tier': S.string()"));
      expect(source, contains('_restageA2uiAs<List<Object?>>('));
      expect(source, contains("data['plans']"));
      // The element type is prefixed (the customer library is imported as p0).
      expect(source, contains('.whereType<p0.PlanTier>()'));
      expect(source, contains('_restageA2uiBuild_PlanTier(e, 0)'));
    });

    test(r'a self-recursive object arg emits $defs/$ref + a recursive helper',
        () {
      const treeId = 'package:fixture/fixture.dart#TreeNode';
      final tree = ObjectNode(
        fields: const {
          'value': ScalarNode(A2uiScalarType.integer),
          'children': ListNode(element: RefNode(treeId)),
        },
        required: const {'value'},
        defId: treeId,
        construction: A2uiClassConstruction(
          dartTypeName: 'TreeNode',
          libraryUri: 'package:fixture/fixture.dart',
          parameters: const [
            A2uiConstructorParameter(name: 'value', named: true),
            A2uiConstructorParameter(name: 'children', named: true),
          ],
        ),
      );
      final catalog = catalogWith([
        entry(
          name: 'Tree',
          flutterType: 'package:fixture/fixture.dart#Tree',
          properties: [prop('root', PropertyType.structured, required: true)],
        ),
      ]);

      final source = emitA2uiCatalogDart(
        catalog,
        richShapes: {('Tree', 'root'): tree},
      );

      // Recursion → a $defs definition + a $ref back-edge in the schema, and a
      // single depth-bounded reconstruction helper the children reuse.
      expect(source, contains(r'$defs:'));
      expect(source, contains(r'$ref:'));
      expect(source, contains('TreeNode? _restageA2uiBuild_TreeNode('));
      expect(source, contains('_depth + 1'));
    });

    test('an OPTIONAL non-null complex arg is omitted (widget default applies)',
        () {
      final catalog = catalogWith([
        entry(
          name: 'PlanCard',
          flutterType: 'package:fixture/fixture.dart#PlanCard',
          properties: [
            prop('label', PropertyType.string),
            // optional (required: false), non-null nested object.
            prop('plan', PropertyType.structured),
          ],
        ),
      ]);

      final plan = classifyA2uiCatalogDart(
        catalog,
        richShapes: {('PlanCard', 'plan'): _planTierNode()},
      );
      final source = emitA2uiCatalogDart(
        catalog,
        richShapes: {('PlanCard', 'plan'): _planTierNode()},
      );

      expect(source, contains("name: 'PlanCard'"));
      expect(source, isNot(contains('plan: plan')));
      expect(source, isNot(contains('_restageA2uiBuild_PlanTier(')));
      final omission =
          plan.coverage.omittedFields.singleWhere((o) => o.fieldName == 'plan');
      expect(
        omission.reason,
        A2uiDartCoverageReason.optionalUnsupportedPropertyType,
      );
    });
  });

  group('richShapes — Pass-2 hardening (fail-closed scope-outs)', () {
    test(
        'HIGH#1(a): a rich property named `data` is collision-proof '
        '(reserved-prefixed local, no shadow of the data map)', () {
      final catalog = catalogWith([
        entry(
          name: 'DataCard',
          flutterType: 'package:fixture/fixture.dart#DataCard',
          properties: [prop('data', PropertyType.structured, required: true)],
        ),
      ]);

      final source = emitA2uiCatalogDart(
        catalog,
        richShapes: {('DataCard', 'data'): _planTierNode()},
      );

      // The reconstructed local is reserved-prefixed; the access still reads
      // the data map by key. No `final data = …` that would shadow the map.
      // (The formatter may wrap the long `final … =` declaration.)
      expect(source, contains('final _restageA2uiArg_data ='));
      expect(source, contains("_restageA2uiBuild_PlanTier(data['data'], 0)"));
      expect(source, contains('data: _restageA2uiArg_data,'));
      expect(source, isNot(contains('final data = _restageA2uiBuild')));
    });

    test(
        'HIGH#1(b): a LEAF field whose identifier is reserved scaffolding '
        '(`data`) is scoped out', () {
      final catalog = catalogWith([
        entry(
          name: 'Banner',
          properties: [
            prop('title', PropertyType.string),
            prop('data', PropertyType.string),
          ],
        ),
      ]);

      final plan = classifyA2uiCatalogDart(catalog);
      final source = emitA2uiCatalogDart(catalog);

      // `data` collides with the generated data-map local → omitted (loud),
      // `title` still emits.
      expect(source, contains("value: data['title'],"));
      expect(source, isNot(contains("value: data['data'],")));
      expect(
        plan.coverage.omittedFields.map((o) => o.fieldName),
        contains('data'),
      );
    });

    test(
        'MED#1: an optional non-null POSITIONAL rich field drops the widget '
        '(never an argument shift)', () {
      final catalog = catalogWith([
        entry(
          name: 'Shifty',
          flutterType: 'package:fixture/fixture.dart#Shifty',
          properties: [
            // optional (required: false), non-null, POSITIONAL rich object.
            prop('plan', PropertyType.structured, positional: true),
            prop('label', PropertyType.string, positional: true),
          ],
        ),
      ]);

      final plan = classifyA2uiCatalogDart(
        catalog,
        richShapes: {('Shifty', 'plan'): _planTierNode()},
      );

      expect(plan.coverage.emittableWidgetCount, 0);
      expect(
        plan.coverage.droppedWidgets.map((d) => d.widgetName),
        contains('Shifty'),
      );
    });

    test(
        'HIGH#2: a catalog enum lacking a libraryUri is scoped out when the '
        'file prefixes customer libs', () {
      // A custom widget (prefixable lib) makes the file prefix; a sibling enum
      // property with only `enumType` (no EnumShape → no libraryUri) cannot be
      // spelled bare safely → scoped out loud.
      final catalog = catalogWith([
        entry(
          name: 'Toned',
          flutterType: 'package:app/widgets.dart#Toned',
          properties: [
            prop('plan', PropertyType.structured, required: true),
            const PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'tone',
              type: PropertyType.enumValue,
              description: '',
              enumType: 'Tone',
            ),
          ],
        ),
      ]);

      final plan = classifyA2uiCatalogDart(
        catalog,
        richShapes: {('Toned', 'plan'): _planTierNode()},
      );

      expect(
        plan.coverage.omittedFields.map((o) => o.fieldName),
        contains('tone'),
      );
    });

    test(
        'HIGH#2 inverse: a flutter enum lacking a libraryUri stays bare when '
        'nothing is prefixed (byte-neutral)', () {
      final catalog = catalogWith([
        entry(
          name: 'Flexish',
          flutterType: 'package:flutter/widgets.dart#Flex',
          properties: [
            const PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'direction',
              type: PropertyType.enumValue,
              description: '',
              required: true,
              enumType: 'Axis',
            ),
          ],
        ),
      ]);

      final plan = classifyA2uiCatalogDart(catalog);
      final source = emitA2uiCatalogDart(catalog);

      // No customer prefix → the flutter enum stays bare + emitted.
      expect(plan.coverage.omittedFields, isEmpty);
      expect(plan.coverage.droppedWidgets, isEmpty);
      expect(source, contains('Axis.values.asNameMap()'));
      expect(source, isNot(contains(' as p0;')));
    });
  });

  group('richShapes — uniform-prefix imports', () {
    test('every customer library import + type spelling is prefixed', () {
      final catalog = catalogWith([
        entry(
          name: 'PlanCard',
          flutterType: 'package:fixture/fixture.dart#PlanCard',
          properties: [prop('plan', PropertyType.structured, required: true)],
        ),
      ]);

      final source = emitA2uiCatalogDart(
        catalog,
        richShapes: {('PlanCard', 'plan'): _planTierNode()},
      );

      // The customer library is imported with a prefix, and EVERY customer
      // type spelling carries it — the widget constructor, the value-builder
      // helper return type, and the reconstruction. Collisions become
      // unrepresentable by construction.
      expect(source, contains("import 'package:fixture/fixture.dart' as p0;"));
      expect(source, contains('p0.PlanCard('));
      expect(source, contains('p0.PlanTier? _restageA2uiBuild_PlanTier('));
      expect(source, contains('return p0.PlanTier('));
      // Flutter / genui / json_schema_builder are NOT prefixed.
      expect(source, contains("import 'package:flutter/widgets.dart';"));
      expect(source, contains("import 'package:genui/genui.dart';"));
      // No bare customer-type spelling leaks through.
      expect(source, isNot(contains('return PlanTier(')));
    });

    test(
        'a rich data class in a DIFFERENT library than the widget is '
        'imported + prefixed', () {
      // The widget ctor and its data class live in different customer
      // libraries; BOTH must be imported (each with its own prefix), or the
      // generated helper references a bare, unimported type.
      final planInModels = ObjectNode(
        fields: const {
          'tier': ScalarNode(A2uiScalarType.string),
          'price': ScalarNode(A2uiScalarType.number),
        },
        required: const {'tier'},
        defId: 'package:app/models.dart#PlanTier',
        construction: A2uiClassConstruction(
          dartTypeName: 'PlanTier',
          libraryUri: 'package:app/models.dart',
          parameters: const [
            A2uiConstructorParameter(name: 'tier', named: true),
            A2uiConstructorParameter(name: 'price', named: true),
          ],
        ),
      );
      final catalog = catalogWith([
        entry(
          name: 'PlanCard',
          flutterType: 'package:app/widgets.dart#PlanCard',
          properties: [prop('plan', PropertyType.structured, required: true)],
        ),
      ]);

      final source = emitA2uiCatalogDart(
        catalog,
        richShapes: {('PlanCard', 'plan'): planInModels},
      );

      // Sorted-URI prefix assignment: models.dart → p0, widgets.dart → p1.
      expect(source, contains("import 'package:app/models.dart' as p0;"));
      expect(source, contains("import 'package:app/widgets.dart' as p1;"));
      expect(source, contains('p1.PlanCard('));
      expect(source, contains('p0.PlanTier? _restageA2uiBuild_PlanTier('));
      expect(source, contains('return p0.PlanTier('));
    });

    test('a list-of-objects element type is prefixed inside whereType', () {
      final catalog = catalogWith([
        entry(
          name: 'PlanList',
          flutterType: 'package:fixture/fixture.dart#PlanList',
          properties: [prop('plans', PropertyType.structured, required: true)],
        ),
      ]);

      final source = emitA2uiCatalogDart(
        catalog,
        richShapes: {('PlanList', 'plans'): ListNode(element: _planTierNode())},
      );

      expect(source, contains('.whereType<p0.PlanTier>()'));
    });

    test('the built-in (flutter-only) catalog stays byte-neutral (no prefix)',
        () {
      final catalog = catalogWith([
        entry(
          name: 'Visibility',
          flutterType: 'package:flutter/widgets.dart#Visibility',
          childrenSlot: ChildrenSlot.single,
          properties: [
            prop('visible', PropertyType.boolean),
            prop('child', PropertyType.widget, required: true),
          ],
        ),
      ]);

      final source = emitA2uiCatalogDart(catalog);

      // No prefixed import and no `pN.` spelling when only flutter is imported.
      expect(source, contains("import 'package:flutter/widgets.dart';"));
      expect(source, isNot(contains(' as p0;')));
      expect(source, isNot(contains('p0.')));
    });

    test('a customer-generic-over-customer-type fails closed LOUD at emit', () {
      // `Box<Inner>` — a customer generic class instantiated with another
      // customer type. The flat instantiated spelling cannot be prefixed
      // component-by-component, so it must fail closed with a clear build-time
      // diagnostic (never emit an ambiguous/uncompilable spelling).
      const innerId = 'package:fixture/fixture.dart#Inner';
      final inner = ObjectNode(
        fields: const {'label': ScalarNode(A2uiScalarType.string)},
        required: const {'label'},
        defId: innerId,
        construction: A2uiClassConstruction(
          dartTypeName: 'Inner',
          libraryUri: 'package:fixture/fixture.dart',
          parameters: const [
            A2uiConstructorParameter(name: 'label', named: true),
          ],
        ),
      );
      const boxId = 'package:fixture/fixture.dart#Box<package:fixture/'
          'fixture.dart#Inner>';
      final box = ObjectNode(
        fields: {'item': inner},
        required: const {'item'},
        defId: boxId,
        construction: A2uiClassConstruction(
          dartTypeName: 'Box<Inner>',
          libraryUri: 'package:fixture/fixture.dart',
          parameters: const [
            A2uiConstructorParameter(name: 'item', named: true),
          ],
        ),
      );
      final catalog = catalogWith([
        entry(
          name: 'Crate',
          flutterType: 'package:fixture/fixture.dart#Crate',
          properties: [prop('box', PropertyType.structured, required: true)],
        ),
      ]);

      expect(
        () => emitA2uiCatalogDart(
          catalog,
          richShapes: {('Crate', 'box'): box},
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('Box<Inner>'), contains('follow-up')),
          ),
        ),
      );
    });
  });
}
