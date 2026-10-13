import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// ignore: implementation_imports
import 'package:restage/src/runtime/library_runtime_registry.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;
import 'package:rfw/rfw.dart' show LocalWidgetLibrary, Runtime;

Widget _badge(BuildContext context, DataSource source) =>
    Text('badge ${source.v<String>(<Object>['label'])}');

Widget _chip(BuildContext context, DataSource source) => const Text('chip');

Widget _other(BuildContext context, DataSource source) => const Text('other');

const WidgetLibrary _appWidgets = WidgetLibrary.custom('app.widgets');

const RestageWidgetLibraryRegistration _badgeLibrary =
    RestageWidgetLibraryRegistration.constant(
  library: _appWidgets,
  capabilityVersion: 1,
  widgets: [RestageWidgetFactory(name: 'Badge', builder: _badge)],
);

const SurfaceVocabulary _vocabulary = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(
    core: <String, LocalWidgetBuilder>{'Column': buildColumn},
  ),
  libraries: [_badgeLibrary],
);

Set<String> _installedWidgets() {
  final runtime = Runtime();
  LibraryRuntimeRegistry.applyTo(runtime);
  final library = runtime.libraries[const LibraryName(['app', 'widgets'])];
  return library is LocalWidgetLibrary ? library.widgets.keys.toSet() : {};
}

void main() {
  setUp(() {
    Restage.debugReset();
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });

  tearDown(() {
    InstalledIconTable.reset();
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
  });

  group('SurfaceVocabulary.libraries', () {
    test('installs the app widgets with their capability version', () {
      _vocabulary.addToInstalled();

      expect(_installedWidgets(), {'Badge'});
      expect(
        LibraryRuntimeRegistry.satisfies(
          const LibraryRequirement(namespace: 'app.widgets', minVersion: 1),
        ),
        isTrue,
      );
    });

    test('installing again changes nothing', () {
      _vocabulary.addToInstalled();
      final generation = LibraryRuntimeRegistry.generation;

      _vocabulary.addToInstalled();

      expect(LibraryRuntimeRegistry.generation, generation);
    });

    test('adds to a library another surface installed', () {
      _vocabulary.addToInstalled();
      const SurfaceVocabulary(
        libraries: [
          RestageWidgetLibraryRegistration.constant(
            library: _appWidgets,
            capabilityVersion: 1,
            widgets: [RestageWidgetFactory(name: 'Chip', builder: _chip)],
          ),
        ],
      ).addToInstalled();

      expect(_installedWidgets(), {'Badge', 'Chip'});
    });

    test('keeps the builders an app registration installed', () {
      Restage.registerWidgetLibrary(
        _appWidgets,
        capabilityVersion: 1,
        widgets: const [RestageWidgetFactory(name: 'Badge', builder: _other)],
      );
      final generation = LibraryRuntimeRegistry.generation;

      _vocabulary.addToInstalled();

      expect(LibraryRuntimeRegistry.generation, generation);
      expect(
        Restage.widgetLibraryRegistrations.single.widgets.single.builder,
        same(_other),
      );
    });

    test('installs again after a registration replaces the library', () {
      _vocabulary.addToInstalled();
      Restage.registerWidgetLibrary(
        _appWidgets,
        capabilityVersion: 1,
        widgets: const [RestageWidgetFactory(name: 'Chip', builder: _chip)],
      );

      _vocabulary.addToInstalled();

      expect(_installedWidgets(), {'Badge', 'Chip'});
    });

    test('names nothing only when it carries no library either', () {
      expect(const SurfaceVocabulary().isEmpty, isTrue);
      expect(
        const SurfaceVocabulary(libraries: [_badgeLibrary]).isEmpty,
        isFalse,
      );
    });
  });

  testWidgets('a flow renders an app widget with nothing registered',
      (tester) async {
    FlowUnavailableError? unavailable;
    await tester.pumpWidget(
      MaterialApp(
        home: _FlowHost(
          flow: _flow,
          resolver: const _Resolver(_flow, 'Badge(label: "Hi")'),
          onUnavailable: (error) => unavailable = error,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(unavailable, isNull);
    expect(find.text('badge Hi'), findsOneWidget);
  });

  testWidgets(
      'a delivered version renders another widget of an installed library',
      (tester) async {
    FlowUnavailableError? unavailable;
    await tester.pumpWidget(
      MaterialApp(
        home: _FlowHost(
          flow: _libraryFlow,
          resolver: _Resolver(_libraryFlow, 'Chip()'),
          onUnavailable: (error) => unavailable = error,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(unavailable, isNull);
    expect(find.text('chip'), findsOneWidget);
  });
}

// What a generated mount carries for a surface that draws only Badge: every
// widget of the library it draws from.
const SurfaceFlowRef<_Result> _libraryFlow = SurfaceFlowRef<_Result>(
  id: 'library_flow',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  decodeResult: _Result.decode,
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: <String, LocalWidgetBuilder>{'Column': buildColumn},
    ),
    libraries: [
      RestageWidgetLibraryRegistration.constant(
        library: _appWidgets,
        capabilityVersion: 1,
        widgets: [
          RestageWidgetFactory(name: 'Badge', builder: _badge),
          RestageWidgetFactory(name: 'Chip', builder: _chip),
        ],
      ),
    ],
  ),
);

final class _Result {
  const _Result();

  static _Result decode(Map<String, Object?> result) => const _Result();
}

const SurfaceFlowRef<_Result> _flow = SurfaceFlowRef<_Result>(
  id: 'welcome_flow',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  decodeResult: _Result.decode,
  vocabulary: _vocabulary,
);

Uint8List _screenBlob(String child) {
  final source = '''
    import restage.core;
    import app.widgets;
    widget OnboardingScreen = Column(
      children: [$child],
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

final class _Resolver implements FlowResolver {
  const _Resolver(this._flow, this._child);

  final SurfaceFlowRef<_Result> _flow;
  final String _child;

  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async {
    final blob = _screenBlob(_child);
    return ResolvedFlow(
      document: FlowDocument(
        flow: _flow.id,
        version: _flow.version,
        schemaVersion: 1,
        minClient: _flow.minClient,
        initial: 'welcome',
        actions: const {},
        legacyTerminalResultPassthrough: true,
        screenArtifacts: {
          'welcome': ScreenArtifact(
            path: 'welcome.rfw',
            version: 1,
            schemaVersion: 1,
            minClient: _flow.minClient,
            contentHash: FlowContentHash.compute(blob),
          ),
        },
        states: const {
          'welcome': ScreenFlowState(
            screen: 'welcome',
            on: {'finish': FlowTransition.goto('done')},
          ),
          'done': EndFlowState(result: {}),
        },
      ),
      screenBlobs: {'welcome': blob},
      cacheHit: false,
    );
  }
}

class _FlowHost extends StatefulWidget {
  const _FlowHost({
    required this.flow,
    required this.resolver,
    required this.onUnavailable,
  });

  final SurfaceFlowRef<_Result> flow;
  final FlowResolver resolver;
  final void Function(FlowUnavailableError error) onUnavailable;

  @override
  State<_FlowHost> createState() => _FlowHostState();
}

class _FlowHostState extends State<_FlowHost> {
  late final RestageFlowController<_Result> _controller;

  @override
  void initState() {
    super.initState();
    _controller = RestageFlowController<_Result>(
      flow: widget.flow,
      resolver: widget.resolver,
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: widget.onUnavailable,
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RestageFlowView<_Result>(controller: _controller);
}
