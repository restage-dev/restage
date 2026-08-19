import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:restage/restage.dart';
import 'package:restage_widgetbook_example/widgets/restage.generated/bare_catalog_card.stories.dart'
    as bare_story;
import 'package:restage_widgetbook_example/widgets/restage.generated/catalog_showcase.stories.dart'
    as showcase_story;
import 'package:restage_widgetbook_example/widgets/restage.generated/constructor_fidelity_corpus.stories.dart'
    as corpus_story;
import 'package:restage_widgetbook_example/widgets/restage.generated/constructor_fidelity_proof.stories.dart'
    as widgetbook_story;
import 'package:restage_widgetbook_example/generated/restage_a2ui_catalog.g.dart';
import 'package:restage_widgetbook_example/user_factories.g.dart';
import 'package:restage_widgetbook_example/widgets/bare_catalog_card.dart';
import 'package:restage_widgetbook_example/widgets/catalog_showcase.dart';
import 'package:restage_widgetbook_example/widgets/constructor_fidelity_corpus.dart';
import 'package:restage_widgetbook_example/widgets/constructor_fidelity_proof.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart' hide WidgetLibrary;

const _customerLibrary = LibraryName(<String>[
  'restage_widgetbook_example',
  'widgets',
]);
const _remoteLibrary = LibraryName(<String>['constructor', 'proof']);
const _positionalRemoteLibrary = LibraryName(<String>[
  'constructor',
  'positional',
]);
const _nullableWidgetRemoteLibrary = LibraryName(<String>[
  'constructor',
  'nullable-widget',
]);

void main() {
  setUp(Restage.debugReset);

  test('bare marker uses the Widgetbook navigation root', () {
    expect(bare_story.component.path, '');

    final component = bare_story.BareCatalogCardComponent;
    expect(component.path, '');
    expect(component.fullPath, 'BareCatalogCard');
    expect(component.stories.single.path, 'BareCatalogCard/RestageCatalog');
  });

  testWidgets('bare marker executes its generated Widgetbook story', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => bare_story.defaults.builder!(
            context,
            bare_story.BareCatalogCardStoryInputArgs.fixed(
              label: 'widgetbook bare',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BareCatalogCard), findsOneWidget);
    expect(find.text('widgetbook bare'), findsOneWidget);
  });

  testWidgets('finite Widgetbook stories execute their exact source states', (
    tester,
  ) async {
    final component = showcase_story.CatalogShowcaseComponent;
    expect(showcase_story.component.path, 'input');
    expect(component.path, 'input');
    expect(component.fullPath, 'input/CatalogShowcase');

    final stories = component.stories;
    expect(stories.map((story) => story.name), <String>[
      'RestageCatalog',
      'EnabledFalse',
      'StatusProcessing',
    ]);
    expect(stories.map((story) => story.path), <String>[
      'input/CatalogShowcase/RestageCatalog',
      'input/CatalogShowcase/EnabledFalse',
      'input/CatalogShowcase/StatusProcessing',
    ]);
    final builders = <Widget Function(BuildContext)>[
      (context) => showcase_story.$RestageCatalog.builder(
        context,
        showcase_story.$RestageCatalog.args,
      ),
      (context) => showcase_story.$EnabledFalse.builder(
        context,
        showcase_story.$EnabledFalse.args,
      ),
      (context) => showcase_story.$StatusProcessing.builder(
        context,
        showcase_story.$StatusProcessing.args,
      ),
    ];
    const expectedStates = <(bool, CatalogShowcaseStatus)>[
      (true, CatalogShowcaseStatus.ready),
      (false, CatalogShowcaseStatus.ready),
      (true, CatalogShowcaseStatus.processing),
    ];

    for (var index = 0; index < builders.length; index += 1) {
      await tester.pumpWidget(
        MaterialApp(
          home: Material(child: Builder(builder: builders[index])),
        ),
      );

      final widget = tester.widget<CatalogShowcase>(
        find.byType(CatalogShowcase),
      );
      expect(widget.enabled, expectedStates[index].$1);
      expect(widget.status, expectedStates[index].$2);
    }
  });

  testWidgets('bare marker executes its generated RFW factory', (tester) async {
    registerRestageCustomerWidgets();
    final registration = Restage.widgetLibraryRegistrations.singleWhere(
      (candidate) =>
          candidate.library.namespace == 'restage_widgetbook_example.widgets',
    );
    final runtime = Runtime()
      ..update(
        _customerLibrary,
        LocalWidgetLibrary(<String, LocalWidgetBuilder>{
          for (final factory in registration.widgets)
            factory.name: factory.builder,
        }),
      )
      ..update(
        _remoteLibrary,
        parseLibraryFile(r'''
import restage_widgetbook_example.widgets;
widget Root = BareCatalogCard(
  label: {
    "$restage.constructor.presence": 1,
    "$restage.constructor.value": "rfw bare",
  },
);
'''),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(_remoteLibrary, 'Root'),
          onEvent: (_, _) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BareCatalogCard), findsOneWidget);
    expect(find.text('rfw bare'), findsOneWidget);
  });

  testWidgets('bare marker executes its generated A2UI component', (
    tester,
  ) async {
    final catalog = Catalog(buildRestageCatalogItems());
    final dataContext = DataContext(InMemoryDataModel(), DataPath.root);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => catalog.buildWidget(
            CatalogItemContext(
              data: const <String, Object?>{
                'props': <String, Object?>{'label': 'a2ui bare'},
              },
              id: 'bare-proof',
              type: 'BareCatalogCard',
              buildChild: (_, [_]) => const SizedBox.shrink(),
              dispatchEvent: (_) {},
              buildContext: context,
              dataContext: dataContext,
              getComponent: (_) => null,
              getCatalogItem: (type) {
                for (final item in catalog.items) {
                  if (item.name == type) return item;
                }
                return null;
              },
              surfaceId: 'bare-proof-surface',
              reportError: (error, stackTrace) => Error.throwWithStackTrace(
                error,
                stackTrace ?? StackTrace.current,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BareCatalogCard), findsOneWidget);
    expect(find.text('a2ui bare'), findsOneWidget);
  });

  testWidgets(
    'A2UI executes every exact CatalogShowcase child-bearing property',
    (tester) async {
      final catalog = Catalog(buildRestageCatalogItems());
      final dataContext = DataContext(InMemoryDataModel(), DataPath.root);

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Builder(
              builder: (context) => catalog.buildWidget(
                CatalogItemContext(
                  data: const <String, Object?>{
                    'props': <String, Object?>{
                      'title': 'multi-slot proof',
                      'enabled': true,
                      'status': 'ready',
                      'hero': 'hero-id',
                      'details': <String>['detail-a-id', 'detail-b-id'],
                      'footer': 'footer-id',
                      'data': <String, Object?>{
                        'note': 'from props',
                        'count': 2,
                      },
                    },
                  },
                  id: 'showcase-proof',
                  type: 'CatalogShowcase',
                  buildChild: (childId, [_]) => Text('child-$childId'),
                  dispatchEvent: (_) {},
                  buildContext: context,
                  dataContext: dataContext,
                  getComponent: (id) => Component(
                    id: id,
                    type: 'SectionHeader',
                    properties: const <String, Object?>{},
                  ),
                  getCatalogItem: (type) {
                    for (final item in catalog.items) {
                      if (item.name == type) return item;
                    }
                    return null;
                  },
                  surfaceId: 'showcase-proof-surface',
                  reportError: (error, stackTrace) => Error.throwWithStackTrace(
                    error,
                    stackTrace ?? StackTrace.current,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final showcase = tester.widget<CatalogShowcase>(
        find.byType(CatalogShowcase),
      );
      expect(showcase.hero, isA<Text>());
      expect(showcase.details, hasLength(2));
      expect(showcase.footer, isA<Text>());
      expect(find.text('child-hero-id'), findsOneWidget);
      expect(find.text('child-detail-a-id'), findsOneWidget);
      expect(find.text('child-detail-b-id'), findsOneWidget);
      expect(find.text('child-footer-id'), findsOneWidget);
      expect(find.text('ready: from props (2)'), findsOneWidget);
    },
  );

  testWidgets('Widgetbook executes its generated story builder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => widgetbook_story.defaults.builder!(
            context,
            widgetbook_story.ConstructorFidelityProofStoryInputArgs.fixed(
              label: 'widgetbook',
              enabled: false,
              optionalText: 'authored',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ConstructorFidelityProof), findsOneWidget);
    expect(find.text('widgetbook|false|authored'), findsOneWidget);
  });

  testWidgets('Widgetbook preserves the broad corpus constructor default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => corpus_story.defaults.builder!(
            context,
            corpus_story.ConstructorFidelityCorpusStoryInputArgs.fixed(),
          ),
        ),
      ),
    );

    final widget = tester.widget<ConstructorFidelityCorpus>(
      find.byType(ConstructorFidelityCorpus),
    );
    expect(widget.directColor.toARGB32(), 0xFF112233);
  });

  testWidgets('RFW binds and invokes the generated customer factory', (
    tester,
  ) async {
    registerRestageCustomerWidgets();
    final registration = Restage.widgetLibraryRegistrations.singleWhere(
      (candidate) =>
          candidate.library.namespace == 'restage_widgetbook_example.widgets',
    );
    final events = <(String, DynamicMap)>[];
    final runtime = Runtime()
      ..update(
        _customerLibrary,
        LocalWidgetLibrary(<String, LocalWidgetBuilder>{
          for (final factory in registration.widgets)
            factory.name: factory.builder,
        }),
      )
      ..update(
        _remoteLibrary,
        parseLibraryFile(r'''
import restage_widgetbook_example.widgets;
widget Root = ConstructorFidelityProof(
  label: "rfw",
  enabled: {
    "$restage.constructor.presence": 1,
    "$restage.constructor.value": false,
  },
  optionalText: {
    "$restage.constructor.presence": 1,
    "$restage.constructor.value": "authored",
  },
  onChanged: event "changed" {},
);
'''),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(_remoteLibrary, 'Root'),
          onEvent: (name, arguments) => events.add((name, arguments)),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ConstructorFidelityProof), findsOneWidget);
    expect(find.text('rfw|false|authored'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('constructor-fidelity-toggle')));
    await tester.pump();
    expect(events, hasLength(1));
    expect(events.single.$1, 'changed');
    expect(events.single.$2, <String, Object?>{'value': true});
  });

  testWidgets('RFW preserves an omitted optional positional hole', (
    tester,
  ) async {
    registerRestageCustomerWidgets();
    final registration = Restage.widgetLibraryRegistrations.singleWhere(
      (candidate) =>
          candidate.library.namespace == 'restage_widgetbook_example.widgets',
    );
    final runtime = Runtime()
      ..update(
        _customerLibrary,
        LocalWidgetLibrary(<String, LocalWidgetBuilder>{
          for (final factory in registration.widgets)
            factory.name: factory.builder,
        }),
      )
      ..update(
        _positionalRemoteLibrary,
        parseLibraryFile(r'''
import restage_widgetbook_example.widgets;
widget Root = ConstructorPositionalCorpus(
  requiredLabel: "positional",
  trailing: {
    "$restage.constructor.presence": 1,
    "$restage.constructor.value": "authored-trailing",
  },
);
'''),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(
            _positionalRemoteLibrary,
            'Root',
          ),
          onEvent: (_, _) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ConstructorPositionalCorpus), findsOneWidget);
    expect(
      find.text('positional|leading-default|authored-trailing'),
      findsOneWidget,
    );
  });

  testWidgets(
    'RFW preserves explicit null for required named and positional Widget?',
    (tester) async {
      registerRestageCustomerWidgets();
      final registration = Restage.widgetLibraryRegistrations.singleWhere(
        (candidate) =>
            candidate.library.namespace == 'restage_widgetbook_example.widgets',
      );
      final runtime = Runtime()
        ..update(
          _customerLibrary,
          LocalWidgetLibrary(<String, LocalWidgetBuilder>{
            for (final factory in registration.widgets)
              factory.name: factory.builder,
          }),
        )
        ..update(
          _nullableWidgetRemoteLibrary,
          parseLibraryFile(r'''
import restage_widgetbook_example.widgets;
widget Root = RequiredNullableWidgetProof(
  positionalNullable: null,
  positionalControl: BareCatalogCard(
    label: {
      "$restage.constructor.presence": 1,
      "$restage.constructor.value": "positional-control",
    },
  ),
  namedNullable: null,
  namedControl: BareCatalogCard(
    label: {
      "$restage.constructor.presence": 1,
      "$restage.constructor.value": "named-control",
    },
  ),
);
'''),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(
              _nullableWidgetRemoteLibrary,
              'Root',
            ),
            onEvent: (_, _) {},
          ),
        ),
      );
      await tester.pump();

      final proof = tester.widget<RequiredNullableWidgetProof>(
        find.byType(RequiredNullableWidgetProof),
      );
      expect(proof.positionalNullable, isNull);
      expect(proof.namedNullable, isNull);
      expect(proof.positionalControl, isNotNull);
      expect(proof.namedControl, isNotNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('positional-control'), findsOneWidget);
      expect(find.text('named-control'), findsOneWidget);
    },
  );

  testWidgets('A2UI instantiates generated data and executes write-back', (
    tester,
  ) async {
    final catalog = Catalog(buildRestageCatalogItems());
    final dataContext = DataContext(InMemoryDataModel(), DataPath.root)
      ..update(DataPath('enabled'), false);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => catalog.buildWidget(
            CatalogItemContext(
              data: const <String, Object?>{
                'props': <String, Object?>{
                  'label': 'a2ui',
                  'enabled': <String, Object?>{'path': 'enabled'},
                  'optionalText': 'authored',
                },
              },
              id: 'proof',
              type: 'ConstructorFidelityProof',
              buildChild: (_, [_]) => const SizedBox.shrink(),
              dispatchEvent: (_) {},
              buildContext: context,
              dataContext: dataContext,
              getComponent: (_) => null,
              getCatalogItem: (type) {
                for (final item in catalog.items) {
                  if (item.name == type) return item;
                }
                return null;
              },
              surfaceId: 'proof-surface',
              reportError: (error, stackTrace) => Error.throwWithStackTrace(
                error,
                stackTrace ?? StackTrace.current,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ConstructorFidelityProof), findsOneWidget);
    expect(find.text('a2ui|false|authored'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('constructor-fidelity-toggle')));
    await tester.pump();
    expect(dataContext.getValue<bool>(DataPath('enabled')), isTrue);
  });
}
