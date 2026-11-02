import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:restage_widgetbook_example/onboarding/screens/restage.generated/get_started_screen.stories.dart'
    as story;
import 'package:restage_widgetbook_example/generated/restage_a2ui_catalog.g.dart';
import 'package:restage_widgetbook_example/onboarding/screens/get_started_screen.dart';
import 'package:widgetbook/widgetbook.dart' as widgetbook;

void main() {
  testWidgets('A2UI installs and executes one opaque native screen component', (
    tester,
  ) async {
    final catalog = buildRestageCatalog();
    final item = catalog.components.values.singleWhere(
      (candidate) => candidate.name == 'get_started_screen',
    );
    final schema = item.schema.value;
    final properties = schema['properties'] as Map<String, Object?>;
    final required = schema['required'] as List<Object?>;
    final props = properties;
    final dispatched = <A2uiRendererAction>[];
    expect(item.name, 'get_started_screen');
    expect(
      props.keys,
      containsAll(<String>[
        'props_title',
        'props_enabled',
        'props_data',
        'props_context',
        'props_itemContext',
        'props_restageA2uiStatus',
        'props_description',
        'props_usage',
      ]),
    );
    expect(required, contains('props_title'));
    expect(
      catalog.components.values.where(
        (candidate) => candidate.name == 'get_started_screen',
      ),
      hasLength(1),
    );

    final processor = MessageProcessor<ComponentImplementation>(
      catalogs: [catalog],
      defaultVersion: A2uiProtocolVersion.v1_0,
      validationConfig: ValidationConfig.strict,
      onAction: dispatched.add,
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
            'component': 'get_started_screen',
            'props_title': 'A2UI title',
            'props_enabled': false,
            'props_data': 'A2UI data',
            'props_context': 'A2UI context',
            'props_itemContext': 'A2UI item context',
            'props_restageA2uiStatus': 'urgent',
            'props_description': 'A2UI custom description',
            'props_usage': 'A2UI example usage',
          },
        ],
      },
    });
    await tester.pumpWidget(
      MaterialApp(home: A2uiSurface(surface: processor.model.getSurface('s')!)),
    );

    final screen = tester.widget<GetStartedScreen>(
      find.byType(GetStartedScreen),
    );
    expect(screen.title, 'A2UI title');
    expect(screen.enabled, isFalse);
    expect(screen.data, 'A2UI data');
    expect(screen.context, 'A2UI context');
    expect(screen.itemContext, 'A2UI item context');
    expect(screen.restageA2uiStatus, GetStartedScreenTone.urgent);
    expect(screen.description, 'A2UI custom description');
    expect(screen.usage, 'A2UI example usage');

    await tester.tap(find.byKey(const ValueKey('get-started-action')));
    await tester.pump();

    expect(dispatched, hasLength(1));
    expect(dispatched.single.name, 'continue');
    expect(dispatched.single.context, <String, Object?>{'value': 'preview'});
  });

  testWidgets('Widgetbook v4 registered story setup records an event', (
    tester,
  ) async {
    story.previewEvents.clear();
    expect(story.component.name, 'get_started_screen');
    expect(story.component.path, 'Screens');
    expect(
      story.GetStartedScreenComponent.fullPath,
      'Screens/get_started_screen',
    );
    final registeredStory =
        story.GetStartedScreenComponent.stories.singleWhere(
              (candidate) => candidate.name == 'RestageCatalog',
            )
            as story.GetStartedScreenStory;
    expect(identical(registeredStory.setup, story.defaults.setup), isTrue);

    await tester.pumpWidget(
      Builder(
        builder: (context) => registeredStory.buildWithConfig(
          context,
          const widgetbook.Config(),
          args: story.GetStartedScreenStoryInputArgs.fixed(
            title: 'Widgetbook title',
            enabled: false,
            description: 'Widgetbook custom description',
            usage: 'Widgetbook example usage',
          ),
        ),
      ),
    );

    final screen = tester.widget<GetStartedScreen>(
      find.byType(GetStartedScreen),
    );
    expect(screen.title, 'Widgetbook title');
    expect(screen.enabled, isFalse);
    expect(screen.tone, GetStartedScreenTone.calm);
    expect(screen.description, 'Widgetbook custom description');
    expect(screen.usage, 'Widgetbook example usage');

    await tester.tap(find.byKey(const ValueKey('get-started-action')));
    await tester.pump();

    expect(story.previewEvents, <({String id, Object? value})>[
      (id: 'continue', value: 'preview'),
    ]);
  });

  testWidgets('Widgetbook generated enum state constructs the real screen', (
    tester,
  ) async {
    final urgentStory =
        story.GetStartedScreenComponent.stories.singleWhere(
              (candidate) => candidate.name == 'ToneUrgent',
            )
            as story.GetStartedScreenStory;

    await tester.pumpWidget(
      Builder(
        builder: (context) =>
            urgentStory.buildWithConfig(context, const widgetbook.Config()),
      ),
    );

    final screen = tester.widget<GetStartedScreen>(
      find.byType(GetStartedScreen),
    );
    expect(screen.enabled, isTrue);
    expect(screen.tone, GetStartedScreenTone.urgent);
  });
}
