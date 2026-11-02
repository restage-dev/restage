import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'generated/sample_a2ui_catalog.g.dart';

MessageProcessor<ComponentImplementation> _processor({
  bool failingChild = false,
}) {
  final catalog = CatalogImplementation(
    id: 'child-proof',
    protocolVersion: A2uiProtocolVersion.v1_0,
    components: [
      ...buildRestageCatalogItems(),
      ComponentImplementation(
        name: 'TestChild',
        schema: S.object(),
        builder: (_, node, _, _) {
          if (failingChild) throw const FormatException('fixture failure');
          return Text('child-${node.context!.componentModel.id}');
        },
      ),
    ],
    definitions: buildRestageCatalogDefinitions(),
  );
  final processor = MessageProcessor<ComponentImplementation>(
    catalogs: [catalog],
    defaultVersion: A2uiProtocolVersion.v1_0,
    validationConfig: ValidationConfig.strict,
  );
  addTearDown(processor.dispose);
  processor.processMessages({
    'version': 'v1.0',
    'createSurface': {'surfaceId': 's', 'catalogId': catalog.id},
  });
  return processor;
}

void _update(
  MessageProcessor<ComponentImplementation> processor,
  String type,
  Map<String, Object?> props, {
  List<String> children = const [],
}) {
  processor.processMessages({
    'version': 'v1.0',
    'updateComponents': {
      'surfaceId': 's',
      'components': [
        {'id': 'root', 'component': type, ...props},
        for (final id in children) {'id': id, 'component': 'TestChild'},
      ],
    },
  });
}

Future<void> _mount(
  WidgetTester tester,
  MessageProcessor<ComponentImplementation> processor,
) => tester.pumpWidget(
  MaterialApp(home: A2uiSurface(surface: processor.model.getSurface('s')!)),
);

void main() {
  test(
    'generated catalog exposes each fixture item',
    () => expect(
      buildRestageCatalogItems().map((item) => item.name),
      containsAll(['Tooltip', 'Flex', 'Visibility', 'Wrap']),
    ),
  );
  testWidgets('Visibility resolves boolean and required single child', (
    tester,
  ) async {
    final processor = _processor();
    _update(
      processor,
      'Visibility',
      {'props_visible': true, 'props_child': 'c1'},
      children: ['c1'],
    );
    await _mount(tester, processor);
    expect(tester.widget<Visibility>(find.byType(Visibility)).visible, isTrue);
    expect(find.text('child-c1'), findsOneWidget);
  });
  for (final props in [
    <String, Object?>{},
    {'props_child': null},
    {'props_child': 42},
    {'props_child': ''},
    {'props_child': 'dangling'},
  ]) {
    test('invalid required child $props is rejected before render', () {
      final processor = _processor();
      expect(
        () =>
            _update(processor, 'Visibility', {'props_visible': true, ...props}),
        throwsA(isA<A2uiError>()),
      );
      expect(processor.model.getSurface('s')!.componentsModel.keys, isEmpty);
    });
  }
  testWidgets('a registered child builder failure remains observable', (
    tester,
  ) async {
    final processor = _processor(failingChild: true);
    _update(
      processor,
      'Visibility',
      {'props_visible': true, 'props_child': 'c1'},
      children: ['c1'],
    );
    await _mount(tester, processor);
    expect(tester.takeException().toString(), contains('fixture failure'));
    expect(find.text('child-c1'), findsNothing);
  });
  testWidgets('Wrap resolves number and both list children', (tester) async {
    final processor = _processor();
    _update(
      processor,
      'Wrap',
      {
        'props_spacing': 8.0,
        'props_children': ['c1', 'c2'],
      },
      children: ['c1', 'c2'],
    );
    await _mount(tester, processor);
    expect(tester.widget<Wrap>(find.byType(Wrap)).spacing, 8.0);
    expect(find.text('child-c1'), findsOneWidget);
    expect(find.text('child-c2'), findsOneWidget);
  });
  testWidgets('Tooltip resolves string and single child', (tester) async {
    final processor = _processor();
    _update(
      processor,
      'Tooltip',
      {'props_message': 'a tip', 'props_child': 'c1'},
      children: ['c1'],
    );
    await _mount(tester, processor);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'a tip');
    expect(find.text('child-c1'), findsOneWidget);
  });
  testWidgets('Flex resolves enum and production JSON list children', (
    tester,
  ) async {
    final processor = _processor();
    _update(
      processor,
      'Flex',
      {
        'props_direction': 'vertical',
        'props_children': ['c1', 'c2'],
      },
      children: ['c1', 'c2'],
    );
    await _mount(tester, processor);
    final flex = tester
        .widgetList<Flex>(find.byType(Flex))
        .singleWhere((widget) => widget.children.length == 2);
    expect(flex.direction, Axis.vertical);
    expect(find.text('child-c1'), findsOneWidget);
    expect(find.text('child-c2'), findsOneWidget);
  });
  testWidgets('the fixture string enum falls back to its first member', (
    tester,
  ) async {
    final processor = _processor();
    _update(
      processor,
      'Flex',
      {
        'props_direction': 'unknown',
        'props_children': ['c1'],
      },
      children: ['c1'],
    );
    await _mount(tester, processor);
    final flex = tester
        .widgetList<Flex>(find.byType(Flex))
        .singleWhere((widget) => widget.children.length == 1);
    expect(flex.direction, Axis.values.first);
    expect(find.text('child-c1'), findsOneWidget);
  });
}
