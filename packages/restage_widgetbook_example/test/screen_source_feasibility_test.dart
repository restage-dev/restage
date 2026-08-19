import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:restage_widgetbook_example/onboarding/screens/restage.generated/opaque_screen_proof.stories.dart'
    as story;
import 'package:restage_widgetbook_example/generated/restage_a2ui_catalog.g.dart';
import 'package:restage_widgetbook_example/onboarding/screens/opaque_screen_proof.dart';
import 'package:widgetbook/widgetbook.dart' as widgetbook;

void main() {
  test('GenUI catalog duplicate names require a generator-side guard', () {
    final item = buildRestageCatalogItems().singleWhere(
      (candidate) => candidate.name == 'opaque_screen_proof',
    );
    final catalog = Catalog(<CatalogItem>[item, item]);
    final components = catalog.toCapabilitiesJson()['components']!;

    expect(catalog.items, hasLength(2));
    expect(components, isA<Map<String, Object?>>());
    expect((components as Map<String, Object?>).keys, <String>[
      'opaque_screen_proof',
    ]);
  });

  testWidgets(
    'GenUI installs and executes one opaque native screen component',
    (tester) async {
      final catalog = buildRestageCatalog();
      final item = catalog.items.singleWhere(
        (candidate) => candidate.name == 'opaque_screen_proof',
      );
      final schema = item.dataSchema.value;
      final properties = schema['properties'] as Map<String, Object?>;
      final required = schema['required'] as List<Object?>;
      final propsSchema = properties['props']! as Map<String, Object?>;
      final props = propsSchema['properties']! as Map<String, Object?>;
      final requiredProps = propsSchema['required']! as List<Object?>;
      final dispatched = <UiEvent>[];
      final dataContext = DataContext(InMemoryDataModel(), DataPath.root);

      expect(item.name, 'opaque_screen_proof');
      expect(
        props.keys,
        containsAll(<String>[
          'title',
          'enabled',
          'data',
          'context',
          'itemContext',
          'restageA2uiStatus',
          'description',
          'usage',
        ]),
      );
      expect(properties.keys, containsAll(<String>['component', 'props']));
      expect(required, containsAll(<String>['component', 'props']));
      expect(requiredProps, contains('title'));
      expect(
        catalog.items.where(
          (candidate) => candidate.name == 'opaque_screen_proof',
        ),
        hasLength(1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => catalog.buildWidget(
              CatalogItemContext(
                data: const <String, Object?>{
                  'props': <String, Object?>{
                    'title': 'A2UI title',
                    'enabled': false,
                    'data': 'A2UI data',
                    'context': 'A2UI context',
                    'itemContext': 'A2UI item context',
                    'restageA2uiStatus': 'urgent',
                    'description': 'A2UI customer description',
                    'usage': 'A2UI customer usage',
                  },
                },
                id: 'opaque-screen-instance',
                type: 'opaque_screen_proof',
                buildChild: (_, [_]) => const SizedBox.shrink(),
                dispatchEvent: dispatched.add,
                buildContext: context,
                dataContext: dataContext,
                getComponent: (_) => null,
                getCatalogItem: (type) => type == item.name ? item : null,
                surfaceId: 'opaque-screen-surface',
                reportError: (error, stackTrace) => Error.throwWithStackTrace(
                  error,
                  stackTrace ?? StackTrace.current,
                ),
              ),
            ),
          ),
        ),
      );

      final screen = tester.widget<OpaqueScreenProof>(
        find.byType(OpaqueScreenProof),
      );
      expect(screen.title, 'A2UI title');
      expect(screen.enabled, isFalse);
      expect(screen.data, 'A2UI data');
      expect(screen.context, 'A2UI context');
      expect(screen.itemContext, 'A2UI item context');
      expect(screen.restageA2uiStatus, OpaqueScreenProofTone.urgent);
      expect(screen.description, 'A2UI customer description');
      expect(screen.usage, 'A2UI customer usage');

      await tester.tap(
        find.byKey(const ValueKey('opaque-screen-proof-action')),
      );
      await tester.pump();

      expect(dispatched, hasLength(1));
      expect(dispatched.single.toMap()['name'], 'continue');
      expect(dispatched.single.toMap()['context'], <String, Object?>{
        'value': 'preview',
      });
    },
  );

  testWidgets('Widgetbook v4 registered story setup records an event', (
    tester,
  ) async {
    story.previewEvents.clear();
    expect(story.component.name, 'opaque_screen_proof');
    expect(story.component.path, 'Screens');
    expect(
      story.OpaqueScreenProofComponent.fullPath,
      'Screens/opaque_screen_proof',
    );
    final registeredStory =
        story.OpaqueScreenProofComponent.stories.singleWhere(
              (candidate) => candidate.name == 'RestageCatalog',
            )
            as story.OpaqueScreenProofStory;
    expect(identical(registeredStory.setup, story.defaults.setup), isTrue);

    await tester.pumpWidget(
      Builder(
        builder: (context) => registeredStory.buildWithConfig(
          context,
          const widgetbook.Config(),
          args: story.OpaqueScreenProofStoryInputArgs.fixed(
            title: 'Widgetbook title',
            enabled: false,
            description: 'Widgetbook customer description',
            usage: 'Widgetbook customer usage',
          ),
        ),
      ),
    );

    final screen = tester.widget<OpaqueScreenProof>(
      find.byType(OpaqueScreenProof),
    );
    expect(screen.title, 'Widgetbook title');
    expect(screen.enabled, isFalse);
    expect(screen.tone, OpaqueScreenProofTone.calm);
    expect(screen.description, 'Widgetbook customer description');
    expect(screen.usage, 'Widgetbook customer usage');

    await tester.tap(find.byKey(const ValueKey('opaque-screen-proof-action')));
    await tester.pump();

    expect(story.previewEvents, <({String id, Object? value})>[
      (id: 'continue', value: 'preview'),
    ]);
  });

  testWidgets('Widgetbook generated enum state constructs the real screen', (
    tester,
  ) async {
    final urgentStory =
        story.OpaqueScreenProofComponent.stories.singleWhere(
              (candidate) => candidate.name == 'ToneUrgent',
            )
            as story.OpaqueScreenProofStory;

    await tester.pumpWidget(
      Builder(
        builder: (context) =>
            urgentStory.buildWithConfig(context, const widgetbook.Config()),
      ),
    );

    final screen = tester.widget<OpaqueScreenProof>(
      find.byType(OpaqueScreenProof),
    );
    expect(screen.enabled, isTrue);
    expect(screen.tone, OpaqueScreenProofTone.urgent);
  });
}
