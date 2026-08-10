import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:restage_a2ui_example/generated/restage_a2ui_catalog.g.dart';
import 'package:restage_a2ui_example/restage_imports.dart';

/// The end-to-end proof: the genui catalog generated from the example's
/// `@RestageWidget` source (`dart run build_runner build`) renders the real
/// customer widgets against genui 0.10.1 and the documented interactivity works —
/// a write-back round-trips (RatingPicker) and an event dispatches (CtaButton).
///
/// This is the "it works" half of the ship-gate: the artifact a developer
/// produces from their own widgets is genuinely renderable + interactive.
Future<void> _pump(
  WidgetTester tester, {
  required Catalog catalog,
  required String type,
  required Map<String, Object?> data,
  required DataContext dataContext,
  required DispatchEventCallback dispatchEvent,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(
        builder: (context) {
          final itemContext = CatalogItemContext(
            data: <String, Object?>{'props': data},
            id: 'root',
            type: type,
            buildChild: (childId, [dataContext]) => Text('child-$childId'),
            dispatchEvent: dispatchEvent,
            buildContext: context,
            dataContext: dataContext,
            getComponent: (_) => null,
            getCatalogItem: (t) {
              for (final item in catalog.items) {
                if (item.name == t) return item;
              }
              return null;
            },
            surfaceId: 'test-surface',
            reportError: (error, stack) => throw error,
          );
          return catalog.buildWidget(itemContext);
        },
      ),
    ),
  );
}

/// Round-trips [data] through JSON so a `{path}` binding arrives as the
/// `Map<String, dynamic>` genui delivers from a decoded payload.
Map<String, Object?> _asDelivered(Map<String, Object?> data) =>
    jsonDecode(jsonEncode(data)) as Map<String, Object?>;

final class _CurrentIntegerListFunction implements ClientFunction {
  _CurrentIntegerListFunction(this.controller);

  final StreamController<Object?> controller;

  @override
  String get name => 'currentIntegerList';

  @override
  String get description => 'Emits the current integer list.';

  @override
  Schema get argumentSchema => S.object(properties: const {});

  @override
  ClientFunctionReturnType get returnType => ClientFunctionReturnType.array;

  @override
  Stream<Object?> execute(JsonMap args, ExecutionContext context) =>
      controller.stream;
}

void main() {
  // Reference the barrel's library sentinel so the generated catalog's source
  // is exercised through the package's own public entry point.
  assert(restageLibrary == 0, 'the library barrel is importable');

  late List<CatalogItem> items;
  late Catalog catalog;
  late DataContext dataContext;
  late List<UiEvent> dispatched;

  setUp(() {
    items = buildRestageCatalogItems();
    catalog = Catalog(items);
    dataContext = DataContext(InMemoryDataModel(), DataPath.root);
    dispatched = <UiEvent>[];
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
    dataContext.update(DataPath('counts'), 'not-a-list');
    await _pump(
      tester,
      catalog: catalog,
      type: 'ScalarListPanel',
      data: _asDelivered(const {
        'labels': <String>[],
        'counts': {'path': 'counts'},
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
    dataContext.update(DataPath('maybeCounts'), false);
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
        'maybeCounts': {'path': 'maybeCounts'},
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );

    expect(find.byType(ScalarListPanel), findsOneWidget);
    expect(find.text('maybe-counts:none'), findsOneWidget);
  });

  testWidgets(
    'a scalar list uses its declared fallback for a wrong-type path',
    (tester) async {
      dataContext.update(DataPath('fallbackCounts'), 'not-a-list');
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
          'fallbackCounts': {'path': 'fallbackCounts'},
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
    dataContext.update(DataPath('selected'), <Object?>[1, 2]);
    await _pump(
      tester,
      catalog: catalog,
      type: 'IntegerListPicker',
      data: _asDelivered(const {
        'selected': {'path': 'selected'},
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );

    expect(find.byType(IntegerListPicker), findsOneWidget);
    expect(find.text('selected:1,2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('integer-list-add')));
    await tester.pump();

    expect(find.text('selected:1,2,3'), findsOneWidget);
    expect(dataContext.getValue<List<Object?>>(DataPath('selected')), <Object?>[
      1,
      2,
      3,
    ]);
  });

  testWidgets('integer-list literal renders and becomes a retained local '
      'override after write', (tester) async {
    await _pump(
      tester,
      catalog: catalog,
      type: 'IntegerListPicker',
      data: _asDelivered(const {
        'selected': <Object?>[1, 2.8, 'x'],
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );
    expect(find.text('selected:1,2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('integer-list-add')));
    await tester.pump();
    expect(find.text('selected:1,2,3'), findsOneWidget);
    expect(
      dataContext.getValue<List<Object?>>(DataPath('root.selected')),
      <int>[1, 2, 3],
    );

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
      'output after immediate cancellation', (tester) async {
    final controller = StreamController<Object?>.broadcast(sync: true);
    addTearDown(controller.close);
    final function = _CurrentIntegerListFunction(controller);
    dataContext = DataContext(
      dataContext.dataModel,
      DataPath.root,
      functions: <ClientFunction>[function],
    );
    await _pump(
      tester,
      catalog: catalog,
      type: 'IntegerListPicker',
      data: _asDelivered(const {
        'selected': {'call': 'currentIntegerList'},
      }),
      dataContext: dataContext,
      dispatchEvent: dispatched.add,
    );
    await tester.pump();
    expect(controller.hasListener, isTrue);

    controller.add(<Object?>[4, 5.8, 'x']);
    await tester.pump();
    expect(find.text('selected:4,5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('integer-list-add')));
    expect(controller.hasListener, isFalse);
    await tester.pump();
    expect(find.text('selected:4,5,3'), findsOneWidget);
    controller.add(<int>[99]);
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

    // The generated catalog reconstructed the customer data classes (Product +
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
      dataContext.update(DataPath('rating'), 2);
      await _pump(
        tester,
        catalog: catalog,
        type: 'RatingPicker',
        data: _asDelivered(const {
          'rating': {'path': 'rating'},
        }),
        dataContext: dataContext,
        dispatchEvent: dispatched.add,
      );

      // The generated catalog constructed the real customer widget, showing two
      // filled stars for the seeded value.
      expect(find.byType(RatingPicker), findsOneWidget);
      expect(find.text('★'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('rating-star-4')));
      await tester.pump();

      // The callback wrote 4 to the bound path; the BoundNumber re-renders with
      // four filled stars.
      expect(find.text('★'), findsNWidgets(4));
      expect(dataContext.getValue<num>(DataPath('rating')), 4);
    },
  );

  testWidgets('dispatch: tapping the button dispatches a UserActionEvent', (
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
    final action = UserActionEvent.fromMap(dispatched.single.toMap());
    expect(action.name, 'onPressed');
    expect(action.sourceComponentId, 'root');
  });
}
