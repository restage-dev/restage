import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:restage_a2ui/restage_a2ui.dart';

/// Hand-authored upstream fixture: the generated catalog must produce
/// these schema markers, top-level wire names and resolved builder accesses.
CatalogImplementation _catalog() => CatalogImplementation(
  id: 'restage:test/v1',
  protocolVersion: A2uiProtocolVersion.v1_0,
  instructions: 'Use Callout to show an editable message and its detail.',
  components: [
    ComponentImplementation(
      name: 'Callout',
      schema: S.object(
        properties: {
          'props_message': CommonSchemasV1.dynamicString,
          'props_detail': CommonSchemas.componentId,
          'props_id': S.string(),
          'props_component': S.string(),
          'props_onSubmit': Schema.fromMap(const {
            r'$ref': r'common_types.json#/$defs/Action',
          }),
        },
        required: [
          'props_message',
          'props_detail',
          'props_id',
          'props_component',
          'props_onSubmit',
        ],
      ),
      builder: (context, node, props, buildChild) => Column(
        children: [
          Text(props.string('props_message')!),
          Text(
            '${props.string('props_id')}:${props.string('props_component')}',
          ),
          TextFormField(
            key: ValueKey(props.string('props_message')),
            initialValue: props.string('props_message'),
            onChanged: props.writable('props_message')?.set,
          ),
          buildChild(props.child('props_detail')!),
          TextButton(
            onPressed: props.action('props_onSubmit'),
            child: const Text('Submit'),
          ),
        ],
      ),
    ),
    ComponentImplementation(
      name: 'Detail',
      schema: S.object(
        properties: {'props_text': CommonSchemasV1.dynamicString},
        required: ['props_text'],
      ),
      builder: (context, node, props, buildChild) =>
          Text(props.string('props_text')!),
    ),
  ],
);

Map<String, Object?> _payload() => {
  'version': 'v1.0',
  'createSurface': {
    'surfaceId': 's',
    'catalogId': 'restage:test/v1',
    'dataModel': {'message': 'Hello'},
    'components': [
      {
        'id': 'root',
        'component': 'Callout',
        'props_id': 'constructor-id',
        'props_component': 'constructor-component',
        'props_message': {'@path': '/message'},
        'props_detail': 'detail',
        'props_onSubmit': {
          'event': {
            'name': 'submitted',
            'context': {
              'message': {'@path': '/message'},
            },
          },
        },
      },
      {'id': 'detail', 'component': 'Detail', 'props_text': 'Arbitrary child'},
    ],
  },
};

void main() {
  testWidgets('v1 renders arbitrary children, bindings and namespaced fields; '
      'writes back and emits a resolved action', (tester) async {
    final catalog = _catalog();
    final payload = _payload();
    expect(
      RestageA2uiPreRenderCheck(catalogs: [catalog]).check(payload),
      isA<A2uiRenderable>(),
    );
    final actions = <A2uiRendererAction>[];
    final processor = MessageProcessor<ComponentImplementation>(
      catalogs: [catalog],
      defaultVersion: A2uiProtocolVersion.v1_0,
      validationConfig: ValidationConfig.strict,
      onAction: actions.add,
    );
    addTearDown(processor.dispose);
    processor.processMessages(payload);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: A2uiSurface(surface: processor.model.getSurface('s')!),
        ),
      ),
    );
    expect(find.text('Arbitrary child'), findsOneWidget);
    expect(find.text('constructor-id:constructor-component'), findsOneWidget);
    expect(find.text('Hello'), findsNWidgets(2));

    await tester.enterText(find.byType(TextFormField), 'Edited');
    await tester.pump();
    expect(find.text('Edited'), findsNWidgets(2));
    await tester.tap(find.text('Submit'));
    await tester.pump();
    expect(actions, hasLength(1));
    expect(actions.single.name, 'submitted');
    expect(actions.single.sourceComponentId, 'root');
    expect(actions.single.surfaceId, 's');
    // Upstream only fills this optional field from the event payload.
    expect(actions.single.catalogId, isNull);
    expect(actions.single.context, {'message': 'Edited'});

    processor.processMessages({
      'version': 'v1.0',
      'updateDataModel': {
        'surfaceId': 's',
        'path': '/message',
        'value': 'Remote',
      },
    });
    await tester.pump();
    expect(find.text('Remote'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('required arbitrary child and dynamic schema remain enforced', () {
    final check = RestageA2uiPreRenderCheck(catalogs: [_catalog()]);
    final payload = _payload();
    final body = payload['createSurface']! as Map<String, Object?>;
    final components = body['components']! as List<Map<String, Object>>;
    components.first.remove('props_detail');
    expect(check.check(payload), isA<A2uiRejected>());
    components.first['props_detail'] = 'detail';
    components.first['props_message'] = {'path': '/message'};
    expect(check.check(payload), isA<A2uiRejected>());
  });
}
