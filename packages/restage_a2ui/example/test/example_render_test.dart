import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:restage_a2ui_example/restage_a2ui_catalog.g.dart';
import 'package:restage_a2ui_example/restage_imports.dart';

/// The end-to-end proof: the genui catalog generated from the example's
/// `@RestageWidget` source (`dart run build_runner build`) renders the real
/// customer widgets against genui 0.9.2 and the documented interactivity works —
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
            data: data,
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
      containsAll(<String>['RatingPicker', 'CtaButton', 'ProductCard']),
    );
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
    // The record-typed `size` drives the card width (300), proving the record
    // reconstructed.
    final card = tester.widget<SizedBox>(
      find.ancestor(
        of: find.byKey(const ValueKey('product-card')),
        matching: find.byType(SizedBox),
      ),
    );
    expect(card.width, 300.0);
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
