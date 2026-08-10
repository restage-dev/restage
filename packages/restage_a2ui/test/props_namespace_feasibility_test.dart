import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';

import 'generated/props_namespace_spike_catalog.g.dart';
import 'generated/props_namespace_spike_fixture.dart';

void main() {
  test(
    'standalone and generated CatalogItem require the same props object',
    () {
      final catalog = buildPropsNamespaceSpikeCatalog();
      final customerCard = catalog.items.singleWhere(
        (item) => item.name == 'CustomerCard',
      );
      final schema = customerCard.dataSchema.value;
      final properties = (schema['properties']! as Map).cast<String, Object?>();
      final definitions = (schema[r'$defs']! as Map).cast<String, Object?>();
      final rootSchema = (definitions['__a2ui_root__']! as Map)
          .cast<String, Object?>();
      final rootProperties = (rootSchema['properties']! as Map)
          .cast<String, Object?>();
      final propsSchema = (rootProperties['props']! as Map)
          .cast<String, Object?>();
      final propsProperties = (propsSchema['properties']! as Map)
          .cast<String, Object?>();

      expect(properties.keys, <String>['component']);
      expect(rootProperties.keys, <String>['props']);
      expect(rootSchema['required'], <String>['props']);
      expect(schema['required'], <String>['component']);
      expect(
        propsProperties.keys,
        containsAll(<String>['id', 'component', 'catalogId', 'props']),
      );

      final document =
          jsonDecode(
                File(
                  'test/generated/props_namespace_spike_catalog.a2ui.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final standalone =
          ((document['a2uiCatalog']! as Map)['components']! as Map)
              .cast<String, Object?>();
      expect(
        _canonical(standalone['CustomerCard']),
        _canonical(customerCard.dataSchema.value),
      );
    },
  );

  testWidgets(
    'GenUI parses, looks up, and renders required props with bindings, '
    'structured values, children, dispatch, and write-back',
    (tester) async {
      final catalog = buildPropsNamespaceSpikeCatalog();
      final model = InMemoryDataModel()
        ..update(DataPath('boundLabel'), 'from-path')
        ..update(DataPath('enabled'), false);
      final events = <UiEvent>[];
      final errors = <Object>[];
      final definition = SurfaceDefinition.fromJson(
        jsonDecode(jsonEncode(_surfaceJson('CustomerCard'))) as JsonMap,
      );
      final root = definition.components['root']!;
      final rootProps = (root.properties['props']! as Map)
          .cast<String, Object?>();

      expect(root.type, 'CustomerCard');
      expect(root.properties.keys, <String>['props']);
      expect(rootProps['id'], 'customer-id');
      expect(rootProps['component'], 'customer-component');
      expect(rootProps['catalogId'], 'customer-catalog');
      expect(rootProps['props'], 'customer-props');

      final context = _FakeSurfaceContext(
        dataModel: model,
        catalog: catalog,
        definition: ValueNotifier<SurfaceDefinition?>(definition),
        onEvent: events.add,
        onError: (error, _) => errors.add(error),
      );
      await tester.pumpWidget(
        MaterialApp(home: Surface(surfaceContext: context)),
      );
      await tester.pumpAndSettle();

      expect(errors, isEmpty);
      expect(find.byType(PropsNamespaceProbe), findsOneWidget);
      expect(
        find.text(
          'collisions:customer-id|customer-component|customer-catalog|'
          'customer-props',
        ),
        findsOneWidget,
      );
      expect(find.text('bindings:literal|from-path|from-call'), findsOneWidget);
      expect(find.text('recursive:root-node|child-node'), findsOneWidget);
      expect(find.text('structured:a:1,b:2|record:3'), findsOneWidget);
      expect(find.text('leaf:leading'), findsOneWidget);
      expect(find.text('leaf:first'), findsOneWidget);
      expect(find.text('leaf:second'), findsOneWidget);
      expect(find.text('enabled:false'), findsOneWidget);

      final actionButton = find.byKey(
        const ValueKey<String>('props-spike-action'),
      );
      await tester.ensureVisible(actionButton);
      await tester.tap(actionButton);
      await tester.pump();
      expect(events, hasLength(1));
      final action = UserActionEvent.fromMap(events.single.toMap());
      expect(action.name, 'onAction');
      expect(action.sourceComponentId, 'root');

      final writeBackButton = find.byKey(
        const ValueKey<String>('props-spike-writeback'),
      );
      await tester.ensureVisible(writeBackButton);
      await tester.tap(writeBackButton);
      await tester.pump();
      expect(model.getValue<bool>(DataPath('enabled')), isTrue);
      expect(find.text('enabled:true'), findsOneWidget);
    },
  );

  testWidgets(
    'an ordinary non-Restage CatalogItem reads the same props object',
    (tester) async {
      final errors = <Object>[];
      final context = _FakeSurfaceContext(
        dataModel: InMemoryDataModel(),
        catalog: buildPropsNamespaceSpikeCatalog(),
        definition: ValueNotifier<SurfaceDefinition?>(
          SurfaceDefinition.fromJson(
            jsonDecode(jsonEncode(_surfaceJson('ExternalPropsCard')))
                as JsonMap,
          ),
        ),
        onEvent: (_) {},
        onError: (error, _) => errors.add(error),
      );

      await tester.pumpWidget(
        MaterialApp(home: Surface(surfaceContext: context)),
      );
      await tester.pumpAndSettle();

      expect(errors, isEmpty);
      expect(find.text('external:ordinary-renderer'), findsOneWidget);
    },
  );
}

Map<String, Object?> _surfaceJson(String rootComponent) => <String, Object?>{
  'surfaceId': 'props-spike-surface',
  'catalogId': propsNamespaceSpikeCatalogId,
  'components': <String, Object?>{
    'root': rootComponent == 'CustomerCard'
        ? <String, Object?>{
            'id': 'root',
            'component': 'CustomerCard',
            'props': <String, Object?>{
              'id': 'customer-id',
              'component': 'customer-component',
              'catalogId': 'customer-catalog',
              'props': 'customer-props',
              'literalValue': 'literal',
              'pathValue': <String, Object?>{'path': 'boundLabel'},
              'callValue': <String, Object?>{'call': 'spikeString'},
              'node': <String, Object?>{
                'label': 'root-node',
                'child': <String, Object?>{'label': 'child-node'},
              },
              'counts': <String, Object?>{'b': 2, 'a': 1},
              'meta': <String, Object?>{'label': 'record', 'count': 3},
              'leading': 'leading',
              'children': <String>['first', 'second'],
              'enabled': <String, Object?>{'path': 'enabled'},
            },
          }
        : <String, Object?>{
            'id': 'root',
            'component': 'ExternalPropsCard',
            'props': <String, Object?>{'label': 'ordinary-renderer'},
          },
    'leading': <String, Object?>{
      'id': 'leading',
      'component': 'SpikeLeaf',
      'props': <String, Object?>{'label': 'leading'},
    },
    'first': <String, Object?>{
      'id': 'first',
      'component': 'SpikeLeaf',
      'props': <String, Object?>{'label': 'first'},
    },
    'second': <String, Object?>{
      'id': 'second',
      'component': 'SpikeLeaf',
      'props': <String, Object?>{'label': 'second'},
    },
  },
};

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys)
        if (!(key == 'additionalProperties' && value[key] == true))
          key: _canonical(value[key]),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _canonical(item)];
  }
  return value;
}

final class _FakeSurfaceContext implements SurfaceContext {
  _FakeSurfaceContext({
    required this.dataModel,
    required this.catalog,
    required this.definition,
    required this.onEvent,
    required this.onError,
  });

  @override
  String get surfaceId => 'props-spike-surface';

  @override
  final DataModel dataModel;

  @override
  final Catalog catalog;

  @override
  final ValueNotifier<SurfaceDefinition?> definition;

  final ValueChanged<UiEvent> onEvent;
  final void Function(Object, StackTrace?) onError;

  @override
  void handleUiEvent(UiEvent event) => onEvent(event);

  @override
  void reportError(Object error, StackTrace? stack) => onError(error, stack);
}
