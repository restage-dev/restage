import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:restage_a2ui_example/generated/restage_a2ui_catalog.g.dart';
import 'package:restage_a2ui_example/restage_imports.dart';

/// Exercise generated adapters through the published processor and renderer.
Future<void> _pump(
  WidgetTester tester, {
  required CatalogImplementation catalog,

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

/// Round-trips [data] through JSON so a `{@path}` binding arrives as the
/// `Map<String, dynamic>` a2ui_flutter delivers from a decoded payload.
Map<String, Object?> _asDelivered(Map<String, Object?> data) =>
    jsonDecode(jsonEncode(data)) as Map<String, Object?>;

final class _CurrentIntegerListFunction extends FunctionImplementation {
  _CurrentIntegerListFunction(this.current)
    : super(name: 'currentIntegerList', argumentSchema: S.object());
  final Signal<Object?> current;
  @override
  Object? execute(
    Map<String, dynamic> args,
    DataContext context, [
    CancellationSignal? cancellationSignal,
  ]) => current;
}

void main() {
  // Reference the barrel's library sentinel so the generated catalog's source
  // is exercised through the package's own public entry point.
  assert(restageLibrary == 0, 'the library barrel is importable');

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

  test('the generated catalog exposes the example widgets', () {
    expect(
      items.map((i) => i.name),
      containsAll(<String>[
        'RatingPicker',
        'CtaButton',
        'ProductCard',
        'ScalarListPanel',
        'IntegerListPicker',
      ]),
    );
  });

  testWidgets('direct scalar-list properties compile and render every family', (
    tester,
  ) async {
    await _pump(
      tester,
      catalog: catalog,
      type: 'ScalarListPanel',
      data: _asDelivered(const {
        'labels': ['alpha', 'beta'],
        'counts': [1, 2],
        'weights': [1, 2.5],
        'measurements': [1, 2.5],
        'flags': [true, false],
        'maybeCounts': [3, 4],
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );

    expect(find.byType(ScalarListPanel), findsOneWidget);
    expect(find.text('labels:alpha,beta'), findsOneWidget);
    expect(find.text('counts:1,2'), findsOneWidget);
    expect(find.text('weights:1.0,2.5'), findsOneWidget);
    expect(find.text('measurements:1,2.5'), findsOneWidget);
    expect(find.text('measurement-types:int,double'), findsOneWidget);
    expect(find.text('flags:true,false'), findsOneWidget);
    expect(find.text('maybe-counts:3,4'), findsOneWidget);
    expect(find.text('fallback-counts:7,8'), findsOneWidget);
  });

  testWidgets('a required scalar list uses its empty fallback for a '
      'wrong-type path', (tester) async {
    dataContext.update('/counts', 'not-a-list');
    await _pump(
      tester,
      catalog: catalog,
      type: 'ScalarListPanel',
      data: _asDelivered(const {
        'labels': <String>[],
        'counts': {'@path': '/counts'},
        'weights': <double>[],
        'measurements': <num>[],
        'flags': <bool>[],
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );

    expect(find.byType(ScalarListPanel), findsOneWidget);
    expect(find.text('counts:'), findsOneWidget);
  });

  testWidgets('a nullable scalar list remains null for a wrong-type path', (
    tester,
  ) async {
    dataContext.update('/maybeCounts', false);
    await _pump(
      tester,
      catalog: catalog,
      type: 'ScalarListPanel',
      data: _asDelivered(const {
        'labels': <String>[],
        'counts': <int>[],
        'weights': <double>[],
        'measurements': <num>[],
        'flags': <bool>[],
        'maybeCounts': {'@path': '/maybeCounts'},
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );

    expect(find.byType(ScalarListPanel), findsOneWidget);
    expect(find.text('maybe-counts:none'), findsOneWidget);
  });

  testWidgets(
    'a binding that resolves to nothing uses the constructor default',
    (tester) async {
      await _pump(
        tester,
        catalog: catalog,
        type: 'ScalarListPanel',
        data: _asDelivered(const {
          'labels': <String>[],
          'counts': <int>[],
          'weights': <double>[],
          'measurements': <num>[],
          'flags': <bool>[],
          'fallbackCounts': {'@path': '/missing'},
        }),
        dataContext: dataContext,
        dispatchEvent: dispatched.add,
      );

      expect(find.text('fallback-counts:7,8'), findsOneWidget);
    },
  );

  testWidgets('a literal null stays null even with a constructor default', (
    tester,
  ) async {
    await _pump(
      tester,
      catalog: catalog,
      type: 'ScalarListPanel',
      data: _asDelivered(const {
        'labels': <String>[],
        'counts': <int>[],
        'weights': <double>[],
        'measurements': <num>[],
        'flags': <bool>[],
        'fallbackCounts': null,
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );

    expect(find.text('fallback-counts:none'), findsOneWidget);
  });

  testWidgets(
    'a scalar list uses its declared fallback for a wrong-type path',
    (tester) async {
      dataContext.update('/fallbackCounts', 'not-a-list');
      await _pump(
        tester,
        catalog: catalog,
        type: 'ScalarListPanel',
        data: _asDelivered(const {
          'labels': <String>[],
          'counts': <int>[],
          'weights': <double>[],
          'measurements': <num>[],
          'flags': <bool>[],
          'fallbackCounts': {'@path': '/fallbackCounts'},
        }),
        dataContext: dataContext,
        dispatchEvent: dispatched.add,
      );

      expect(find.byType(ScalarListPanel), findsOneWidget);
      expect(find.text('fallback-counts:7,8'), findsOneWidget);
    },
  );

  testWidgets('a nullable scalar list remains null when absent', (
    tester,
  ) async {
    await _pump(
      tester,
      catalog: catalog,
      type: 'ScalarListPanel',
      data: _asDelivered(const {
        'labels': <String>[],
        'counts': <int>[],
        'weights': <double>[],
        'measurements': <num>[],
        'flags': <bool>[],
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );

    expect(find.byType(ScalarListPanel), findsOneWidget);
    expect(find.text('maybe-counts:none'), findsOneWidget);
    expect(find.text('fallback-counts:7,8'), findsOneWidget);
  });

  testWidgets('integer-list write-back updates its bound path and re-renders', (
    tester,
  ) async {
    dataContext.update('/selected', <Object?>[1, 2]);
    await _pump(
      tester,
      catalog: catalog,
      type: 'IntegerListPicker',
      data: _asDelivered(const {
        'selected': {'@path': '/selected'},
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );

    expect(find.byType(IntegerListPicker), findsOneWidget);
    expect(find.text('selected:1,2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('integer-list-add')));
    await tester.pump();

    expect(find.text('selected:1,2,3'), findsOneWidget);
    expect(dataContext.getValue('/selected'), <Object?>[1, 2, 3]);
  });

  testWidgets('integer-list literal renders and becomes a retained local '
      'override after write', (tester) async {
    await _pump(
      tester,
      catalog: catalog,
      type: 'IntegerListPicker',
      data: _asDelivered(const {
        'selected': <int>[1, 2],
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );
    expect(find.text('selected:1,2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('integer-list-add')));
    await tester.pump();
    expect(find.text('selected:1,2,3'), findsOneWidget);
    expect(dataContext.getValue('/restage_root/props_selected'), <int>[
      1,
      2,
      3,
    ]);

    await _pump(
      tester,
      catalog: catalog,
      type: 'IntegerListPicker',
      data: _asDelivered(const {
        'selected': <int>[9],
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );
    expect(find.text('selected:1,2,3'), findsOneWidget);
  });

  testWidgets('integer-list call stays reactive until write and rejects later '
      'output after local override', (tester) async {
    final controller = signal<Object?>(null);

    final function = _CurrentIntegerListFunction(controller);
    dataContext.functions.add(function);
    await _pump(
      tester,
      catalog: catalog,
      type: 'IntegerListPicker',
      data: _asDelivered(const {
        'selected': {'@call': 'currentIntegerList'},
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );
    await tester.pump();

    controller.value = <Object?>[4, 5.8, 'x'];
    await tester.pump();
    expect(find.text('selected:4,5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('integer-list-add')));

    await tester.pump();
    expect(find.text('selected:4,5,3'), findsOneWidget);
    controller.value = <int>[99];
    await tester.pump();
    expect(find.text('selected:4,5,3'), findsOneWidget);
  });

  testWidgets('rich data: a structured Product (nested object + scalar list + '
      'list-of-objects + map + record) reconstructs and renders', (
    tester,
  ) async {
    await _pump(
      tester,
      catalog: catalog,
      type: 'ProductCard',
      data: _asDelivered(const {
        'product': {
          'name': 'Pro Plan',
          'price': {'amount': 9.99, 'currency': 'USD'},
          'tags': ['popular', 'new'],
          'features': [
            {'label': 'Unlimited', 'included': true},
            {'label': 'Priority support', 'included': false},
          ],
          'attributes': {'tier': 'gold'},
          'size': {'width': 300.0, 'height': 200.0},
        },
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );

    // The generated catalog reconstructed the custom data classes (Product +
    // nested Money + Feature) and the map/record directly from the wire map
    // and rendered them — the full rich data vocabulary.
    expect(find.byType(ProductCard), findsOneWidget);
    expect(find.text('Pro Plan'), findsOneWidget); // nested object
    expect(find.text('9.99 USD'), findsOneWidget); // nested data class
    expect(find.text('#popular'), findsOneWidget); // scalar list
    expect(find.text('✓ Unlimited'), findsOneWidget); // list-of-objects
    expect(find.text('✗ Priority support'), findsOneWidget);
    expect(find.text('tier: gold'), findsOneWidget); // String-keyed map
    // The record-typed `size` drives the visible card dimensions, proving the
    // record reconstructed without hiding its footprint in an invisible box.
    final card = tester.widget<SizedBox>(
      find.ancestor(
        of: find.byKey(const ValueKey('product-card')),
        matching: find.byType(SizedBox),
      ),
    );
    expect(card.width, 300.0);
    expect(card.height, 200.0);
    expect(
      find.descendant(of: find.byWidget(card), matching: find.byType(Card)),
      findsOneWidget,
    );
  });

  testWidgets(
    'write-back: tapping a star writes the rating back and re-renders',
    (tester) async {
      dataContext.update('/rating', 2);
      await _pump(
        tester,
        catalog: catalog,
        type: 'RatingPicker',
        data: _asDelivered(const {
          'rating': {'@path': '/rating'},
        }),
        dataContext: dataContext,
        dispatchEvent: dispatched.add,
      );

      // The generated catalog constructed the real custom widget, showing two
      // filled stars for the seeded value.
      expect(find.byType(RatingPicker), findsOneWidget);
      expect(find.text('★'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('rating-star-4')));
      await tester.pump();

      // The callback wrote 4 to the bound path; the resolved number re-renders with
      // four filled stars.
      expect(find.text('★'), findsNWidgets(4));
      expect(dataContext.getValue('/rating'), 4);
    },
  );

  testWidgets('dispatch: tapping the button dispatches a A2uiRendererAction', (
    tester,
  ) async {
    await _pump(
      tester,
      catalog: catalog,
      type: 'CtaButton',
      data: _asDelivered(const {'label': 'Subscribe'}),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );

    expect(find.byType(CtaButton), findsOneWidget);
    expect(find.text('Subscribe'), findsOneWidget);
    expect(dispatched, isEmpty);

    await tester.tap(find.byKey(const ValueKey('cta-button')));
    await tester.pump();

    expect(dispatched, hasLength(1));
    final action = dispatched.single;
    expect(action.name, 'onPressed');
    expect(action.sourceComponentId, 'root');
  });
}
