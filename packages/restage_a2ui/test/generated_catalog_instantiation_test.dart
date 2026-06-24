import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';

import 'generated/sample_a2ui_catalog.g.dart';

/// Renders a generated `CatalogItem` exactly as genui would: constructs a real
/// [CatalogItemContext] (real [DataContext] + sample data + a `buildChild` stub)
/// and calls `Catalog.buildWidget` inside a real element tree.
///
/// This is the instantiation proof for the M-3.2 emitter against the real genui
/// SDK: it proves the generated code RUNS (not merely type-checks) — in
/// particular the SINGLE/LIST child slots (`itemContext.buildChild`) and the
/// fail-closed enum lookup (`Axis.values.asNameMap()[..] ?? Axis.values.first`),
/// the two behaviours `dynamic` once masked.
Future<void> _pumpCatalogItem(
  WidgetTester tester, {
  required Catalog catalog,
  required List<CatalogItem> items,
  required String type,
  required Map<String, Object?> data,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          final itemContext = CatalogItemContext(
            data: data,
            id: 'root',
            type: type,
            buildChild: (childId, [dataContext]) => Text('child-$childId'),
            dispatchEvent: (_) {},
            buildContext: context,
            dataContext: DataContext(InMemoryDataModel(), DataPath.root),
            getComponent: (_) => null,
            getCatalogItem: (t) {
              for (final item in items) {
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

void main() {
  late List<CatalogItem> items;
  late Catalog catalog;

  setUp(() {
    items = buildRestageCatalogItems();
    catalog = Catalog(items);
  });

  test('the generated catalog exposes the fixture items', () {
    expect(
      items.map((i) => i.name),
      containsAll(<String>['Tooltip', 'Flex', 'Visibility', 'Wrap']),
    );
  });

  testWidgets('Visibility renders — BoundBool value + single child slot', (
    tester,
  ) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'Visibility',
      data: const {'visible': true, 'child': 'c1'},
    );
    // The BoundBool value resolved to `visible: true` and the child rendered.
    expect(find.byType(Visibility), findsOneWidget);
    expect(tester.widget<Visibility>(find.byType(Visibility)).visible, isTrue);
    expect(find.text('child-c1'), findsOneWidget);
  });

  testWidgets('Wrap renders — BoundNumber value + list child slot', (
    tester,
  ) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'Wrap',
      data: const {
        'spacing': 8.0,
        'children': ['c1', 'c2'],
      },
    );
    // The BoundNumber value resolved to `spacing: 8.0` and both children built.
    final wrap = tester.widget<Wrap>(find.byType(Wrap));
    expect(wrap.spacing, 8.0);
    expect(find.text('child-c1'), findsOneWidget);
    expect(find.text('child-c2'), findsOneWidget);
  });

  testWidgets('Tooltip renders — BoundString value + single child slot', (
    tester,
  ) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'Tooltip',
      data: const {'message': 'a tip', 'child': 'c1'},
    );
    // The widget built and its single child resolved via buildChild('c1').
    expect(find.byType(Tooltip), findsOneWidget);
    expect(find.text('child-c1'), findsOneWidget);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'a tip');
  });

  testWidgets('Flex renders — fail-closed enum + list child slot', (
    tester,
  ) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'Flex',
      data: const {
        'direction': 'vertical',
        'children': ['c1', 'c2'],
      },
    );
    // The enum lookup resolved 'vertical' → Axis.vertical, and both list
    // children resolved via buildChild.
    final flex = tester
        .widgetList<Flex>(find.byType(Flex))
        .firstWhere(
          (f) => f.children.length == 2 && f.children.every((c) => c is Text),
        );
    expect(flex.direction, Axis.vertical);
    expect(find.text('child-c1'), findsOneWidget);
    expect(find.text('child-c2'), findsOneWidget);
  });

  testWidgets('Flex renders from production-shaped (jsonDecode) data', (
    tester,
  ) async {
    // A cached payload arrives via jsonDecode, so `children` is a List<dynamic>
    // (not the List<String> the const literals above produce). Prove the
    // generated _restageA2uiBuildChildren handles the shape genui delivers.
    final data =
        jsonDecode(
              jsonEncode({
                'direction': 'vertical',
                'children': ['c1', 'c2'],
              }),
            )
            as Map<String, Object?>;
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'Flex',
      data: data,
    );
    expect(find.text('child-c1'), findsOneWidget);
    expect(find.text('child-c2'), findsOneWidget);
  });

  testWidgets('Flex enum fails closed on an unknown member → first member', (
    tester,
  ) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'Flex',
      data: const {
        'direction': 'not-a-real-axis',
        'children': <String>['c1'],
      },
    );
    final flex = tester
        .widgetList<Flex>(find.byType(Flex))
        .firstWhere((f) => f.children.length == 1 && f.children.single is Text);
    // Unknown member → Axis.values.first (horizontal), never a throw.
    expect(flex.direction, Axis.values.first);
  });
}
