import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart'
    show
        InstalledWidgetLibraries,
        Restage,
        RestageWidgetFactory,
        RestageWidgetLibraries,
        WidgetLibrary;
import 'package:restage/src/flow/flow_runtime_support.dart'
    show flowScreenRuntime;
import 'package:rfw/rfw.dart'
    show
        DataSource,
        LibraryName,
        LocalWidgetBuilder,
        LocalWidgetLibrary,
        Runtime;

const LibraryName _core = LibraryName(<String>['restage', 'core']);
const LibraryName _material = LibraryName(<String>['restage', 'material']);
const LibraryName _cupertino = LibraryName(<String>['restage', 'cupertino']);

Widget _stub(BuildContext context, DataSource source) =>
    const SizedBox.shrink();

Runtime _install(RestageWidgetLibraries libraries) {
  final runtime = Runtime();
  addTearDown(runtime.dispose);
  libraries.installInto(
    runtime,
    coreName: _core,
    materialName: _material,
    cupertinoName: _cupertino,
  );
  return runtime;
}

void main() {
  group('with nothing installed', () {
    setUp(InstalledWidgetLibraries.reset);
    tearDown(() {
      InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
    });

    test('the installed libraries are none', () {
      expect(
        InstalledWidgetLibraries.current,
        same(RestageWidgetLibraries.none),
      );
      expect(InstalledWidgetLibraries.current.isEmpty, isTrue);
    });

    test('assembling a flow screen runtime fails loudly', () {
      expect(
        () => flowScreenRuntime(
          LocalWidgetLibrary(const <String, LocalWidgetBuilder>{}),
        ),
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message.toString(),
            'message',
            allOf(
              contains('can resolve no widget'),
              contains('mounted through its generated reference'),
              contains(
                'InstalledWidgetLibraries.install('
                'RestageWidgetLibraries.builtIn())',
              ),
            ),
          ),
        ),
      );
    });

    test('a surface drawing only the app\'s own widgets assembles', () {
      addTearDown(Restage.debugReset);
      Restage.registerWidgetLibrary(
        const WidgetLibrary.custom('acme.design_system'),
        widgets: <RestageWidgetFactory>[
          RestageWidgetFactory(name: 'AcmeMarker', builder: _stub),
        ],
      );
      final runtime = flowScreenRuntime(
        LocalWidgetLibrary(const <String, LocalWidgetBuilder>{}),
      );
      addTearDown(runtime.dispose);

      expect(
        runtime.libraries.keys,
        contains(const LibraryName(<String>['acme', 'design_system'])),
      );
    });
  });

  test('installing a vocabulary reads back the same maps', () {
    addTearDown(() {
      InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
    });
    const vocabulary = RestageWidgetLibraries.fromVocabulary(
      core: <String, LocalWidgetBuilder>{'Column': _stub},
      cupertino: <String, LocalWidgetBuilder>{'CupertinoButton': _stub},
    );

    InstalledWidgetLibraries.install(vocabulary);

    expect(InstalledWidgetLibraries.current, same(vocabulary));
    expect(InstalledWidgetLibraries.current.core.keys, <String>['Column']);
    expect(InstalledWidgetLibraries.current.material, isEmpty);
    expect(
      InstalledWidgetLibraries.current.cupertino.keys,
      <String>['CupertinoButton'],
    );
    expect(InstalledWidgetLibraries.current.isEmpty, isFalse);
  });

  test('a core-only vocabulary installs only the core namespace', () {
    const vocabulary = RestageWidgetLibraries.fromVocabulary(
      core: <String, LocalWidgetBuilder>{'Column': _stub},
    );

    final runtime = _install(vocabulary);

    expect(runtime.libraries.keys, <LibraryName>[_core]);
  });

  test('the built-in libraries install all three namespaces', () {
    final runtime = _install(RestageWidgetLibraries.builtIn());

    expect(
      runtime.libraries.keys,
      containsAll(<LibraryName>[_core, _material, _cupertino]),
    );
  });
}
