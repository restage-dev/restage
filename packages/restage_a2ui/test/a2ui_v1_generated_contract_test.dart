import 'dart:convert';
import 'dart:io';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_a2ui/restage_a2ui.dart';

import 'generated/encoded_property_catalog.g.dart' as encoded;
import 'generated/interactive_catalog.g.dart' as controls;
import 'generated/sample_a2ui_catalog.g.dart' as children;
import 'generated/envelope_collision_catalog.g.dart' as names;
import 'generated/rich_shape_catalog.g.dart' as rich;
import 'generated/constraint_parity_catalog.g.dart' as constrained;

// An undeclared property fails the unknown-property check, or the closed
// schema of a component that declares none.
Matcher _rejectsUndeclared(
  String property, {
  String code = 'extra_forbidden',
}) => throwsA(
  isA<A2uiValidationError>()
      .having((error) => error.path, 'path', '/components/0/$property')
      .having(
        (error) => [
          for (final detail in error.errors) (detail.code, detail.path),
        ],
        'errors',
        contains((code, '/$property')),
      ),
);

Map<String, Object?> _create(String catalogId, Map<String, Object?> root) => {
  'version': '1.0',
  'createSurface': {
    'surfaceId': 's',
    'catalogId': catalogId,
    'components': [
      {'id': 'root', ...root},
    ],
  },
};

void main() {
  for (final pair in [
    ('encoded_property_catalog', encoded.buildRestageCatalog),
    ('interactive_catalog', controls.buildRestageCatalog),
    ('envelope_collision_catalog', names.buildRestageCatalog),
    ('rich_shape_catalog', rich.buildRestageCatalog),
    ('constraint_parity_catalog', constrained.buildRestageCatalog),
  ]) {
    test('${pair.$1} standalone document equals runtime document', () {
      final envelope =
          jsonDecode(
                File('test/generated/${pair.$1}.a2ui.json').readAsStringSync(),
              )
              as Map;
      final document = (envelope['a2uiCatalog']! as Map)
          .cast<String, Object?>();
      expect(Catalog.fromJson(document).toJson(), document);
      expect(pair.$2().toJson(), document);
      expect(
        Catalog.fromJson(document).validationSchema,
        pair.$2().validationSchema,
      );
    });
  }

  test(
    'authored child descriptions match inline and rich producer schemas',
    () {
      final catalog = names.buildRestageCatalog();
      final envelope =
          jsonDecode(
                File(
                  'test/generated/envelope_collision_catalog.a2ui.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final document = envelope['a2uiCatalog']! as Map<String, Object?>;
      expect(catalog.toJson(), document);
      final components = document['components']! as Map;
      final inline = components['InlineCard']! as Map;
      expect(
        ((inline['properties']! as Map)['props_child']! as Map)['description'],
        'Content shown in the header.',
      );
      final runtimeInline = catalog.components['InlineCard']!.schema.value;
      expect(
        ((runtimeInline['properties']! as Map)['props_child']!
            as Map)['description'],
        'Content shown in the header.',
      );
      final definitions = document[r'$defs']! as Map;
      final richRoot = definitions['CustomCard.__a2ui_root__']! as Map;
      expect(
        ((richRoot['properties']! as Map)['props_leading']!
            as Map)['description'],
        'Content shown before the rich details.',
      );
      expect(catalog.definitions['CustomCard.__a2ui_root__'], richRoot);
    },
  );

  for (final name in ['CustomCard', 'OtherCard']) {
    testWidgets(
      'generated $name arbitrary child, namespace collisions and recursive business data render',
      (tester) async {
        final catalog = names.buildRestageCatalog();
        final processor = MessageProcessor<ComponentImplementation>(
          catalogs: [catalog],
          defaultVersion: A2uiProtocolVersion.v1_0,
          validationConfig: ValidationConfig.strict,
        );
        addTearDown(processor.dispose);
        processor.processMessages({
          'version': '1.0',
          'createSurface': {
            'surfaceId': 's',
            'catalogId': catalog.id,
            'dataModel': {'message': 'bound'},
            'components': [
              {
                'id': 'root',
                'component': name,
                'props_id': 'id-value',
                'props_component': 'component-value',
                'props_catalogId': 'catalog-value',
                'props_props': 'props-value',
                'props_literalValue': 'literal',
                'props_pathValue': {'@path': '/message'},
                'props_callValue': 'value',
                'props_node': {
                  'label': 'parent',
                  'child': {'label': 'child'},
                },
                'props_counts': {'path': 1, 'call': 2},
                'props_meta': {'label': 'meta', 'count': 3},
                'props_leading': 'lead',
                'props_children': ['leaf'],
                'props_enabled': true,
              },
              {'id': 'lead', 'component': 'Leaf', 'props_label': 'leading'},
              {'id': 'leaf', 'component': 'Leaf', 'props_label': 'list-child'},
            ],
          },
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: A2uiSurface(surface: processor.model.getSurface('s')!),
            ),
          ),
        );
        for (final text in [
          'collisions:id-value|component-value|catalog-value|props-value',
          'bindings:literal|bound|value',
          'recursive:parent|child',
          'structured:call:2,path:1|meta:3',
          'leaf:leading',
          'leaf:list-child',
        ]) {
          expect(find.text(text), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'generated v1 child, controlled binding and fixed dispatch render',
    (tester) async {
      final actions = <A2uiRendererAction>[];
      final catalog = CatalogImplementation(
        id: 'restage:generated-proof',
        protocolVersion: A2uiProtocolVersion.v1_0,
        definitions: {
          ...children.buildRestageCatalogDefinitions(),
          ...controls.buildRestageCatalogDefinitions(),
        },
        components: [
          ...children.buildRestageCatalogItems(),
          ...controls.buildRestageCatalogItems(),
        ],
      );
      final processor = MessageProcessor<ComponentImplementation>(
        catalogs: [catalog],
        defaultVersion: A2uiProtocolVersion.v1_0,
        validationConfig: ValidationConfig.strict,
        onAction: actions.add,
      );
      addTearDown(processor.dispose);
      processor.processMessages({
        'version': '1.0',
        'createSurface': {
          'surfaceId': 's',
          'catalogId': catalog.id,
          'dataModel': {'answer': 0},
          'components': [
            {
              'id': 'root',
              'component': 'Flex',
              'props_direction': 'vertical',
              'props_children': ['tooltip', 'button'],
            },
            {
              'id': 'tooltip',
              'component': 'Tooltip',
              'props_message': 'Choose',
              'props_child': 'control',
            },
            {
              'id': 'control',
              'component': 'QuickCheck',
              'props_selected': {'@path': '/answer'},
            },
            {
              'id': 'button',
              'component': 'ActionButton',
              'props_label': 'Submit',
            },
          ],
        },
      });
      // The action is compile-fixed: strict validation refuses a payload that
      // tries to supply one.
      expect(
        () => processor.processMessages({
          'version': '1.0',
          'updateComponents': {
            'surfaceId': 's',
            'components': [
              {
                'id': 'button',
                'component': 'ActionButton',
                'props_label': 'Submit',
                'props_onPressed': {
                  'event': {'name': 'spoofed'},
                },
              },
            ],
          },
        }),
        _rejectsUndeclared('props_onPressed'),
      );
      final surface = processor.model.getSurface('s')!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: A2uiSurface(surface: surface)),
        ),
      );
      expect(find.byType(Tooltip), findsOneWidget);
      expect(find.text('quickcheck-selected:0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quickcheck-option-2')));
      await tester.pump();
      expect(surface.dataModel.get('/answer'), 2);
      expect(find.text('quickcheck-selected:2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('actionbutton')));
      await tester.pump();
      expect(actions.single.name, 'onPressed');
      expect(actions.single.sourceComponentId, 'button');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('strict validation refuses undeclared properties on every shape', () {
    final cases = [
      (
        controls.buildRestageCatalog(),
        <String, Object?>{
          'component': 'TapTarget',
          'props_onTap': {
            'event': {'name': 'spoofed'},
          },
        },
        _rejectsUndeclared('props_onTap', code: 'invalid_value'),
      ),
      (
        names.buildRestageCatalog(),
        <String, Object?>{
          'component': 'CustomCard',
          'props_id': 'a',
          'props_component': 'a',
          'props_catalogId': 'a',
          'props_props': 'a',
          'props_literalValue': 'a',
          'props_pathValue': 'a',
          'props_callValue': 'a',
          'props_node': {'label': 'a'},
          'props_counts': {'path': 1},
          'props_meta': {'label': 'a', 'count': 1},
          'props_leading': 'root',
          'props_children': <String>[],
          'props_enabled': true,
          'props_undeclared': 'x',
        },
        _rejectsUndeclared('props_undeclared'),
      ),
    ];
    for (final (catalog, root, rejects) in cases) {
      final processor = MessageProcessor<ComponentImplementation>(
        catalogs: [catalog],
        defaultVersion: A2uiProtocolVersion.v1_0,
        validationConfig: ValidationConfig.strict,
      );
      addTearDown(processor.dispose);
      expect(
        () => processor.processMessages(_create(catalog.id, root)),
        rejects,
      );
    }
  });

  test('a property-less component still takes envelope fields', () {
    final catalog = controls.buildRestageCatalog();
    final processor = MessageProcessor<ComponentImplementation>(
      catalogs: [catalog],
      defaultVersion: A2uiProtocolVersion.v1_0,
      validationConfig: ValidationConfig.strict,
    );
    addTearDown(processor.dispose);
    processor.processMessages(
      _create(catalog.id, {
        'component': 'TapTarget',
        'catalogId': catalog.id,
        'accessibility': {'label': 'Tap'},
        'metadata': {'extensions': <String, Object?>{}},
      }),
    );
    expect(processor.model.getSurface('s')!.componentsModel.keys, ['root']);
  });

  test('the pre-render check refuses undeclared properties by default', () {
    final catalog = controls.buildRestageCatalog();
    final check = RestageA2uiPreRenderCheck(catalogs: [catalog]);
    expect(
      check.check(_create(catalog.id, {'component': 'TapTarget'})),
      isA<A2uiRenderable>(),
    );
    for (final root in <Map<String, Object?>>[
      {
        'component': 'TapTarget',
        'props_onTap': {
          'event': {'name': 'spoofed'},
        },
      },
      {
        'component': 'ActionButton',
        'props_label': 'Submit',
        'props_onPressed': {
          'event': {'name': 'spoofed'},
        },
      },
    ]) {
      expect(check.check(_create(catalog.id, root)), isA<A2uiRejected>());
    }
  });

  testWidgets('a payload-supplied action leaves the fixed dispatch unchanged', (
    tester,
  ) async {
    final actions = <A2uiRendererAction>[];
    final catalog = controls.buildRestageCatalog();
    final processor = MessageProcessor<ComponentImplementation>(
      catalogs: [catalog],
      defaultVersion: A2uiProtocolVersion.v1_0,
      validationConfig: const ValidationConfig(allowUnknownElements: true),
      onAction: actions.add,
    );
    addTearDown(processor.dispose);
    processor.processMessages({
      'version': '1.0',
      'createSurface': {
        'surfaceId': 's',
        'catalogId': catalog.id,
        'components': [
          {
            'id': 'root',
            'component': 'ActionButton',
            'props_label': 'Submit',
            'props_onPressed': {
              'event': {'name': 'spoofed'},
            },
          },
        ],
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: A2uiSurface(surface: processor.model.getSurface('s')!),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('actionbutton')));
    await tester.pump();
    expect(actions.single.name, 'onPressed');
    expect(actions.single.sourceComponentId, 'root');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
