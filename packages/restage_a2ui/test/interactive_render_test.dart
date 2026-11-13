import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'generated/interactive_catalog.g.dart';
import 'generated/interactive_fixture.dart';

/// Exercise generated adapters through the published processor and renderer.
Future<void> _pumpInteractive(
  WidgetTester tester, {
  required CatalogImplementation catalog,
  required List<ComponentImplementation> items,
  required String type,
  required Map<String, Object?> data,
  required _Runtime dataContext,
  required void Function(A2uiRendererAction) dispatchEvent,
}) async {
  dataContext.mount(catalog, type, data, dispatchEvent);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: A2uiSurface(surface: dataContext.surface)),
    ),
  );
}

final class _Runtime {
  MessageProcessor<ComponentImplementation>? processor;
  final initial = <String, Object?>{};
  final functions = <FunctionImplementation>[];
  SurfaceModel<ComponentImplementation> get surface =>
      processor!.model.getSurface('s')!;
  void update(String path, Object? value) {
    if (processor == null) {
      initial[path.substring(1)] = value;
    } else {
      surface.dataModel.set(path, value);
    }
  }

  Object? getValue(String path) => surface.dataModel.get(path);
  void mount(
    CatalogImplementation catalog,
    String type,
    Map<String, Object?> data,
    void Function(A2uiRendererAction) action,
  ) {
    final components = [
      {
        'id': 'root',
        'component': type,
        for (final entry in data.entries) 'props_${entry.key}': entry.value,
      },
    ];
    if (processor == null) {
      final composed = CatalogImplementation(
        id: 'interaction-test',
        components: catalog.components.values.toList(),
        definitions: catalog.definitions,
        functions: functions,
        protocolVersion: A2uiProtocolVersion.v1_0,
      );
      processor = MessageProcessor<ComponentImplementation>(
        catalogs: [composed],
        defaultVersion: A2uiProtocolVersion.v1_0,
        validationConfig: ValidationConfig.strict,
        onAction: action,
      );
      addTearDown(processor!.dispose);
      processor!.processMessages({
        'version': '1.0',
        'createSurface': {
          'surfaceId': 's',
          'catalogId': composed.id,
          'dataModel': initial,
          'components': components,
        },
      });
    } else {
      processor!.processMessages({
        'version': '1.0',
        'updateComponents': {'surfaceId': 's', 'components': components},
      });
    }
  }
}

/// Round-trips [data] through JSON so values arrive in the shape a2ui_flutter delivers
/// from a decoded payload (e.g. a `{@path}` binding as `Map<String, dynamic>`).
Map<String, Object?> _asDelivered(Map<String, Object?> data) =>
    jsonDecode(jsonEncode(data)) as Map<String, Object?>;

final class _CurrentChoicesFunction extends FunctionImplementation {
  _CurrentChoicesFunction(this.current)
    : super(name: 'currentChoices', argumentSchema: S.object());
  final Signal<Object?> current;
  @override
  Object? execute(
    Map<String, dynamic> args,
    DataContext context, [
    CancellationSignal? cancellationSignal,
  ]) => current;
}

void main() {
  late List<ComponentImplementation> items;
  late CatalogImplementation catalog;

  late _Runtime dataContext;
  late List<A2uiRendererAction> dispatched;

  setUp(() {
    items = buildRestageCatalogItems();
    catalog = buildRestageCatalog();

    dataContext = _Runtime();
    dispatched = <A2uiRendererAction>[];
  });

  test('the generated interactive catalog exposes the fixture items', () {
    expect(
      items.map((i) => i.name),
      containsAll(<String>[
        'QuickCheck',
        'MultiSelect',
        'ActionButton',
        'Range',
      ]),
    );
  });

  testWidgets('scalar write-back: tap -> write-back -> re-render '
      '(the QuickCheck acceptance bar, explicit {@path} binding)', (
    tester,
  ) async {
    // The producer supplies an EXPLICIT `{@path}` binding on the value prop —
    // the read+write both target this path, so a mis-pairing cannot pass.
    dataContext.update('/answer', 0);
    await _pumpInteractive(
      tester,
      catalog: catalog,
      items: items,
      type: 'QuickCheck',
      data: _asDelivered(const {
        'selected': {'@path': '/answer'},
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );
    // The generated catalog constructed the REAL custom widget.
    expect(find.byType(QuickCheckFixture), findsOneWidget);
    expect(find.text('quickcheck-selected:0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quickcheck-option-2')));
    await tester.pump();

    // The callback wrote 2 back to the bound path and the shared controlled
    // helper re-renders from the path subscription.
    expect(find.text('quickcheck-selected:2'), findsOneWidget);
    expect(dataContext.getValue('/answer'), 2);
  });

  testWidgets('list write-back: tap -> write-back -> re-render', (
    tester,
  ) async {
    dataContext.update('/picks', 'not-a-list');
    await _pumpInteractive(
      tester,
      catalog: catalog,
      items: items,
      type: 'MultiSelect',
      data: _asDelivered(const {
        'chosen': {'@path': '/picks'},
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );
    expect(find.byType(MultiSelectFixture), findsOneWidget);
    expect(find.text('multiselect-chosen:'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('multiselect-add-b')));
    await tester.pump();

    // The settled list replaces the wrong-type value at the same path and the
    // safe object binding re-renders from the newly valid list.
    expect(find.text('multiselect-chosen:b'), findsOneWidget);
    expect(dataContext.getValue('/picks'), <String>['b']);
  });

  testWidgets(
    'a list literal renders, refreshes before write, then retains its '
    'component-scoped override',
    (tester) async {
      await _pumpInteractive(
        tester,
        catalog: catalog,
        items: items,
        type: 'MultiSelect',
        data: _asDelivered(const {
          'chosen': <String>['a'],
        }),
        dataContext: dataContext,
        dispatchEvent: dispatched.add,
      );
      expect(find.text('multiselect-chosen:a'), findsOneWidget);

      await _pumpInteractive(
        tester,
        catalog: catalog,
        items: items,
        type: 'MultiSelect',
        data: _asDelivered(const {
          'chosen': <String>['fresh'],
        }),
        dataContext: dataContext,
        dispatchEvent: dispatched.add,
      );
      expect(find.text('multiselect-chosen:fresh'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('multiselect-add-b')));
      await tester.pump();
      expect(find.text('multiselect-chosen:fresh,b'), findsOneWidget);
      expect(dataContext.getValue('/restage_root/props_chosen'), <String>[
        'fresh',
        'b',
      ]);

      await _pumpInteractive(
        tester,
        catalog: catalog,
        items: items,
        type: 'MultiSelect',
        data: _asDelivered(const {
          'chosen': <String>['late'],
        }),
        dataContext: dataContext,
        dispatchEvent: dispatched.add,
      );
      expect(find.text('multiselect-chosen:fresh,b'), findsOneWidget);
    },
  );

  testWidgets('a list call stays reactive until write, retains its override, '
      'and rejects later output', (tester) async {
    final controller = signal<Object?>(null);

    final function = _CurrentChoicesFunction(controller);
    dataContext.functions.add(function);
    await _pumpInteractive(
      tester,
      catalog: catalog,
      items: items,
      type: 'MultiSelect',
      data: _asDelivered(const {
        'chosen': {'@call': 'currentChoices'},
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );
    await tester.pump();

    controller.value = <Object?>['call', 1];
    await tester.pump();
    expect(find.text('multiselect-chosen:call'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('multiselect-add-b')));

    await tester.pump();
    expect(find.text('multiselect-chosen:call,b'), findsOneWidget);
    controller.value = <String>['late'];
    await tester.pump();
    expect(find.text('multiselect-chosen:call,b'), findsOneWidget);
  });

  testWidgets(
    'dispatch: tap -> a compile-fixed A2uiRendererAction is dispatched',
    (tester) async {
      await _pumpInteractive(
        tester,
        catalog: catalog,
        items: items,
        type: 'ActionButton',
        data: _asDelivered(const {'label': 'Go'}),
        dataContext: dataContext,
        dispatchEvent: dispatched.add,
      );
      expect(find.byType(ActionButtonFixture), findsOneWidget);
      expect(find.text('actionbutton:Go'), findsOneWidget);
      expect(dispatched, isEmpty);

      await tester.tap(find.byKey(const ValueKey('actionbutton')));
      await tester.pump();

      expect(dispatched, hasLength(1));
      final action = dispatched.single;
      // The event name is COMPILE-FIXED from the callback property name (the
      // producer cannot repoint it), with the source component id.
      expect(action.name, 'onPressed');
      expect(action.sourceComponentId, 'root');
    },
  );

  testWidgets('multi-control: each control round-trips its OWN distinct path '
      '(the @RestageProperty annotation pairing, no cross-wiring)', (
    tester,
  ) async {
    dataContext.update('/lo', 0);
    dataContext.update('/hi', 10);
    await _pumpInteractive(
      tester,
      catalog: catalog,
      items: items,
      type: 'Range',
      data: _asDelivered(const {
        'low': {'@path': '/lo'},
        'high': {'@path': '/hi'},
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );
    expect(find.byType(RangeFixture), findsOneWidget);
    expect(find.text('range-low:0'), findsOneWidget);
    expect(find.text('range-high:10'), findsOneWidget);

    // Tapping the low control writes ONLY the low path.
    await tester.tap(find.byKey(const ValueKey('range-low-inc')));
    await tester.pump();
    expect(find.text('range-low:1'), findsOneWidget);
    expect(find.text('range-high:10'), findsOneWidget); // unchanged
    expect(dataContext.getValue('/lo'), 1);
    expect(dataContext.getValue('/hi'), 10);

    // Tapping the high control writes ONLY the high path.
    await tester.tap(find.byKey(const ValueKey('range-high-inc')));
    await tester.pump();
    expect(find.text('range-low:1'), findsOneWidget); // unchanged
    expect(find.text('range-high:11'), findsOneWidget);
    expect(dataContext.getValue('/lo'), 1);
    expect(dataContext.getValue('/hi'), 11);
  });

  testWidgets('the path-field hazard: a value whose content is literally "path" '
      'is DATA at the bound path, not a binding misread', (tester) async {
    // The list value contains the element "path". The read is `{path: P}` (the
    // binding to the SEPARATE data path "picks"); the element "path" is the
    // value AT that path — never confused with the binding (closed by
    // construction: a scalar/list value is read via the path binding, the
    // content is data).
    dataContext.update('/picks', <String>['path']);
    await _pumpInteractive(
      tester,
      catalog: catalog,
      items: items,
      type: 'MultiSelect',
      data: _asDelivered(const {
        'chosen': {'@path': '/picks'},
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );
    expect(find.text('multiselect-chosen:path'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('multiselect-add-b')));
    await tester.pump();
    expect(find.text('multiselect-chosen:path,b'), findsOneWidget);
    expect(dataContext.getValue('/picks'), <String>['path', 'b']);
  });
}
