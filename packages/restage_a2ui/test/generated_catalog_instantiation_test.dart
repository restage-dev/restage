import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart'
    show CreateSurfaceMessage, UpdateComponentsMessage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

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
  Set<String> componentIds = const {'c1', 'c2'},
  Widget Function(String childId)? buildChild,
  void Function(String childId)? onBuildChild,
  void Function(String childId)? onGetComponent,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          final itemContext = CatalogItemContext(
            data: data,
            id: 'root',
            type: type,
            buildChild: (childId, [dataContext]) {
              onBuildChild?.call(childId);
              return buildChild?.call(childId) ?? Text('child-$childId');
            },
            dispatchEvent: (_) {},
            buildContext: context,
            dataContext: DataContext(InMemoryDataModel(), DataPath.root),
            getComponent: (childId) {
              onGetComponent?.call(childId);
              if (!componentIds.contains(childId)) return null;
              return Component(
                id: childId,
                type: 'TestChild',
                properties: const {},
              );
            },
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
    catalog = buildRestageCatalog();
    items = catalog.items.toList();
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
    var buildChildCalls = 0;
    var getComponentCalls = 0;
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'Visibility',
      data: const {'visible': true, 'child': 'c1'},
      onBuildChild: (_) => buildChildCalls++,
      onGetComponent: (_) => getComponentCalls++,
    );
    // The BoundBool value resolved to `visible: true` and the child rendered.
    expect(find.byType(Visibility), findsOneWidget);
    expect(tester.widget<Visibility>(find.byType(Visibility)).visible, isTrue);
    expect(find.text('child-c1'), findsOneWidget);
    expect(getComponentCalls, 1);
    expect(buildChildCalls, 1);
  });

  for (final scenario
      in <
        ({
          String label,
          Map<String, Object?> data,
          List<String> messageParts,
          int getComponentCalls,
          bool hidesRawValue,
        })
      >[
        (
          label: 'a missing value',
          data: const {'visible': true},
          messageParts: const ['the value was null or missing'],
          getComponentCalls: 0,
          hidesRawValue: false,
        ),
        (
          label: 'an explicit null',
          data: const {'visible': true, 'child': null},
          messageParts: const ['the value was null or missing'],
          getComponentCalls: 0,
          hidesRawValue: false,
        ),
        (
          label: 'a non-String value',
          data: const {'visible': true, 'child': 42},
          messageParts: const ['runtime type int', 'String component id'],
          getComponentCalls: 0,
          hidesRawValue: true,
        ),
        (
          label: 'an empty id',
          data: const {'visible': true, 'child': ''},
          messageParts: const ['the value was the empty string'],
          getComponentCalls: 0,
          hidesRawValue: false,
        ),
        (
          label: 'a dangling id',
          data: const {'visible': true, 'child': 'dangling'},
          messageParts: const ['component id "dangling" is not registered'],
          getComponentCalls: 1,
          hidesRawValue: false,
        ),
      ]) {
    testWidgets('Visibility rejects ${scenario.label} before child build', (
      tester,
    ) async {
      var buildChildCalls = 0;
      var getComponentCalls = 0;
      await _pumpCatalogItem(
        tester,
        catalog: catalog,
        items: items,
        type: 'Visibility',
        data: scenario.data,
        onBuildChild: (_) => buildChildCalls++,
        onGetComponent: (_) => getComponentCalls++,
      );

      final error = tester.takeException();
      expect(error, isA<StateError>());
      final message = error.toString();
      expect(message, contains('Required A2UI child "Visibility.child"'));
      expect(
        message,
        contains('Provide a non-empty String id for a component'),
      );
      for (final part in scenario.messageParts) {
        expect(message, contains(part));
      }
      if (scenario.hidesRawValue) {
        expect(message, isNot(contains('42')));
      }
      expect(getComponentCalls, scenario.getComponentCalls);
      expect(buildChildCalls, 0);
    });
  }

  testWidgets('Visibility wraps a direct child builder failure with context', (
    tester,
  ) async {
    var buildChildCalls = 0;
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'Visibility',
      data: const {'visible': true, 'child': 'c1'},
      buildChild: (_) => throw const FormatException('fixture failure'),
      onBuildChild: (_) => buildChildCalls++,
    );

    final error = tester.takeException();
    expect(error, isA<StateError>());
    expect(
      error.toString(),
      allOf(
        contains('Required A2UI child "Visibility.child"'),
        contains('component id "c1"'),
        contains('failed to build'),
      ),
    );
    expect(buildChildCalls, 1);
  });

  testWidgets('Visibility preserves a non-error fallback child', (
    tester,
  ) async {
    await _pumpCatalogItem(
      tester,
      catalog: catalog,
      items: items,
      type: 'Visibility',
      data: const {'visible': true, 'child': 'c1'},
      buildChild: (_) => const FallbackWidget(isLoading: true),
    );

    expect(tester.takeException(), isNull);
    final fallback = tester.widget<FallbackWidget>(find.byType(FallbackWidget));
    expect(fallback.error, isNull);
    expect(fallback.isLoading, isTrue);
  });

  testWidgets('real Surface contextualizes a registered child builder failure', (
    tester,
  ) async {
    // genui 0.10.1 sanitizes the raw cause out of the AGENT-facing onSubmit
    // report, but still logs the underlying build exception at SEVERE — the
    // developer-facing loud channel. Capture it to prove the actionable cause
    // is MOVED (to the log), not LOST.
    final severeErrors = <Object?>[];
    final logSub = genUiLogger.onRecord.listen((record) {
      if (record.level.name == 'SEVERE') severeErrors.add(record.error);
    });
    addTearDown(logSub.cancel);
    const catalogId = 'required-child-runtime-test';
    final runtimeCatalog = Catalog(<CatalogItem>[
      ...catalog.items,
      CatalogItem(
        name: 'FailingChild',
        dataSchema: S.object(),
        widgetBuilder: (_) => throw const FormatException('fixture failure'),
      ),
    ], catalogId: catalogId);
    final controller = SurfaceController(catalogs: [runtimeCatalog]);
    final submissions = <ChatMessage>[];
    final submissionSubscription = controller.onSubmit.listen(submissions.add);
    addTearDown(submissionSubscription.cancel);
    addTearDown(controller.dispose);
    controller
      ..handleMessage(
        CreateSurfaceMessage(surfaceId: 'surface', catalogId: catalogId),
      )
      ..handleMessage(
        UpdateComponentsMessage(
          surfaceId: 'surface',
          components: const [
            {
              'id': 'root',
              'component': 'Visibility',
              'visible': true,
              'child': 'broken-child',
            },
            {'id': 'broken-child', 'component': 'FailingChild'},
          ],
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Surface(surfaceContext: controller.contextFor('surface')),
      ),
    );
    await tester.pump();

    final frameworkError = tester.takeException();
    expect(frameworkError, isA<StateError>());
    expect(
      frameworkError.toString(),
      allOf(
        contains('Required A2UI child "Visibility.child"'),
        contains('component id "broken-child"'),
        contains('failed to build'),
      ),
    );
    expect(submissions, hasLength(1));
    final interaction =
        submissions.single.parts.uiInteractionParts.single.interaction;
    final payload = jsonDecode(interaction) as Map<String, Object?>;
    final reportedError =
        (payload['error']! as Map<String, Object?>)['message']! as String;
    // genui 0.10.1 SANITIZES the raw exception text out of the agent-facing
    // report (0.9.2 surfaced 'FormatException: fixture failure' here); the
    // failure is still reported, now with a generic message.
    expect(reportedError, contains('An unexpected system error occurred.'));
    // The underlying cause is not LOST — it MOVED to the SEVERE developer log
    // (genui 0.10.1 `Surface` logs the child build exception before degrading
    // to a FallbackWidget). Assert the actionable cause where it now lives, so
    // the loud-and-actionable required-child diagnostic contract still holds.
    expect(
      severeErrors.any(
        (e) => e.toString().contains('FormatException: fixture failure'),
      ),
      isTrue,
      reason:
          'the underlying child-build exception must reach the developer on the '
          'SEVERE record ERROR slot (not merely the message); '
          'saw: $severeErrors',
    );
    expect(find.byType(FallbackWidget), findsNothing);
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
