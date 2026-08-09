import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:restage/restage.dart';
import 'package:restage_widgetbook_example/generated/constructor_fidelity_corpus.stories.dart'
    as corpus_story;
import 'package:restage_widgetbook_example/generated/constructor_fidelity_proof.stories.dart'
    as widgetbook_story;
import 'package:restage_widgetbook_example/generated/restage_a2ui_catalog.g.dart';
import 'package:restage_widgetbook_example/user_factories.g.dart';
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

void main() {
  setUp(Restage.debugReset);

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
                'label': 'a2ui',
                'enabled': <String, Object?>{'path': 'enabled'},
                'optionalText': 'authored',
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
