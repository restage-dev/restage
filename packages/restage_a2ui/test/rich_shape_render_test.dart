import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';

import 'generated/rich_shape_catalog.g.dart';
import 'generated/rich_shape_fixture.dart';

/// Renders generated rich constructors through the published v1 runtime.
Future<void> _pumpCatalogItem(
  WidgetTester tester, {
  required CatalogImplementation catalog,
  required List<ComponentImplementation> items,
  required String type,
  required Map<String, Object?> data,
}) async {
  final processor = MessageProcessor<ComponentImplementation>(
    catalogs: [catalog],
    defaultVersion: A2uiProtocolVersion.v1_0,
    validationConfig: ValidationConfig.strict,
  );
  addTearDown(processor.dispose);
  processor.processMessages({
    'version': 'v1.0',
    'createSurface': {
      'surfaceId': 's',
      'catalogId': catalog.id,
      'components': [
        {
          'id': 'root',
          'component': type,
          for (final entry in data.entries) 'props_${entry.key}': entry.value,
        },
      ],
    },
  });
  await tester.pumpWidget(
    MaterialApp(home: A2uiSurface(surface: processor.model.getSurface('s')!)),
  );
}

/// Round-trips [data] through JSON so the values arrive in the shape a2ui_flutter
/// delivers from a decoded payload (e.g. a `List<dynamic>`, not a
/// `List<String>`).
Map<String, Object?> _asDelivered(Map<String, Object?> data) =>
    jsonDecode(jsonEncode(data)) as Map<String, Object?>;

void main() {
  late List<ComponentImplementation> items;
  late CatalogImplementation catalog;

  setUp(() {
    items = buildRestageCatalogItems();
    catalog = buildRestageCatalog();
  });

  test('the generated rich-shape catalog exposes the fixture items', () {
    expect(
      items.map((i) => i.name),
      containsAll(<String>[
        'PlanCard',
        'FeatureGrid',
        'Glossary',
        'MetaBar',
        'LinkCard',
      ]),
    );
  });

  test('recursive documentation survives the generated catalog', () {
    final schema =
        catalog.definitions['restage_component_CommentThread']! as Map;
    final definitions = (schema[r'$defs']! as Map).cast<String, Object?>();
    final comment = (definitions['Comment']! as Map).cast<String, Object?>();
    final properties = (comment['properties']! as Map).cast<String, Object?>();

    expect(
      comment['description'],
      'A comment that may link to one nested reply.',
    );
    expect((properties['text']! as Map)['description'], 'The comment text.');
    expect(
      (properties['reply']! as Map)['description'],
      'The next reply in the thread.',
    );
    final encoded = jsonEncode(schema);
    for (final description in const [
      'A comment that may link to one nested reply.',
      'The comment text.',
      'The next reply in the thread.',
    ]) {
      expect(description.allMatches(encoded), hasLength(1));
    }
  });

  testWidgets('a nested data class reconstructs (with a nullable enum + '
      'nullable string) and renders', (tester) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'PlanCard',
      data: _asDelivered(const {
        'plan': {
          'name': 'Pro',
          'price': 12.5,
          'badge': 'popular',
          'tagline': 'Best for teams',
        },
      }),
    );
    expect(find.byType(PlanCardFixture), findsOneWidget);
    expect(find.text('plan-name:Pro'), findsOneWidget);
    expect(find.text('plan-price:12.5'), findsOneWidget);
    expect(find.text('plan-badge:popular'), findsOneWidget);
    expect(find.text('plan-tagline:Best for teams'), findsOneWidget);
  });

  testWidgets('a nullable enum + nullable string degrade to null when absent', (
    tester,
  ) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'PlanCard',
      // badge + tagline omitted → the nullable fields reconstruct to null.
      data: _asDelivered(const {
        'plan': {'name': 'Free', 'price': 0.0},
      }),
    );
    expect(find.text('plan-name:Free'), findsOneWidget);
    expect(find.text('plan-badge:none'), findsOneWidget);
    expect(find.text('plan-tagline:-'), findsOneWidget);
  });

  testWidgets('a list-of-objects reconstructs element-by-element', (
    tester,
  ) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'FeatureGrid',
      data: _asDelivered(const {
        'features': [
          {'label': 'SSO', 'included': true},
          {'label': 'Audit log', 'included': false},
        ],
      }),
    );
    expect(find.byType(FeatureGridFixture), findsOneWidget);
    expect(find.text('feature:SSO:true'), findsOneWidget);
    expect(find.text('feature:Audit log:false'), findsOneWidget);
  });

  testWidgets('a String-keyed map reconstructs — including a key named "path"', (
    tester,
  ) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'Glossary',
      // A map key literally named "path" — the binding-sentinel hazard for the
      // map case; direct reconstruction reads it as data, not a binding.
      data: _asDelivered(const {
        'terms': {'path': 'a route', 'api': 'an interface'},
      }),
    );
    expect(find.byType(GlossaryFixture), findsOneWidget);
    expect(find.text('term:api=an interface'), findsOneWidget);
    expect(find.text('term:path=a route'), findsOneWidget);
  });

  testWidgets('a named record reconstructs', (tester) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'MetaBar',
      data: _asDelivered(const {
        'meta': {'title': 'Q3', 'count': 42},
      }),
    );
    expect(find.text('meta:Q3:42'), findsOneWidget);
  });

  testWidgets('an object whose field is named "path" reconstructs correctly '
      '(the BoundObject binding-sentinel hazard, closed by construction)', (
    tester,
  ) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'LinkCard',
      data: _asDelivered(const {
        'link': {'path': '/settings', 'label': 'Settings'},
      }),
    );
    // BoundObject would have read `{path: '/settings', ...}` as a path BINDING
    // and mis-rendered; direct reconstruction reads the field by name.
    expect(find.byType(LinkCardFixture), findsOneWidget);
    expect(find.text('link:Settings:/settings'), findsOneWidget);
  });

  testWidgets('a self-recursive nested object reconstructs depth-first and '
      'renders (\$ref-rooted schema + depth-bounded helper)', (tester) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'CommentThread',
      data: _asDelivered(const {
        'root': {
          'text': 'top',
          'reply': {'text': 'nested'},
        },
      }),
    );
    expect(find.byType(CommentThreadFixture), findsOneWidget);
    expect(find.text('comment:top'), findsOneWidget);
    expect(find.text('reply:nested'), findsOneWidget);
  });

  for (final plan in [
    'not-an-object',
    {'price': 1.0},
  ]) {
    testWidgets(
      'malformed required rich value $plan fails before widget construction',
      (tester) async {
        await expectLater(
          _pumpCatalogItem(
            tester,
            catalog: catalog,
            items: items,
            type: 'PlanCard',
            data: {'plan': plan},
          ),
          throwsA(isA<A2uiValidationError>()),
        );
        expect(find.byType(PlanCardFixture), findsNothing);
      },
    );
  }
}
