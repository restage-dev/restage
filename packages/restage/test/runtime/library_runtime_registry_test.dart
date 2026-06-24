import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// Direct path import — the registry is internal and not re-exported from
// the barrel, but tests reach in to verify per-mount apply behavior.
// ignore: implementation_imports
import 'package:restage/src/runtime/library_runtime_registry.dart';
import 'package:restage_shared/restage_shared.dart' show LibraryRequirement;
// `rfw` exposes its own `WidgetLibrary` (the runtime's decoded-library
// type). The catalog `WidgetLibrary` from `restage_shared` is what
// customers register with — hide rfw's so the catalog identifier is the
// one in scope.
import 'package:rfw/rfw.dart' hide WidgetLibrary;

Widget _stubBuilder(BuildContext context, DataSource source) =>
    const SizedBox();

void _registerOne(String namespace, String widgetName) {
  LibraryRuntimeRegistry.register(
    WidgetLibrary.custom(namespace),
    [RestageWidgetFactory(name: widgetName, builder: _stubBuilder)],
  );
}

Runtime _applyToFreshRuntime() {
  final runtime = Runtime();
  LibraryRuntimeRegistry.applyTo(runtime);
  return runtime;
}

void main() {
  setUp(LibraryRuntimeRegistry.clear);

  test('register + applyTo registers customer library on the runtime', () {
    _registerOne('acme.design_system', 'AcmeButton');
    expect(
      _applyToFreshRuntime().libraries.keys,
      contains(const LibraryName(['acme', 'design_system'])),
    );
  });

  test('re-registering the same namespace replaces the prior entry', () {
    _registerOne('acme.design_system', 'OldWidget');
    _registerOne('acme.design_system', 'NewWidget');

    final library = _applyToFreshRuntime()
            .libraries[const LibraryName(['acme', 'design_system'])]!
        as LocalWidgetLibrary;
    expect(library.widgets.keys, ['NewWidget']);
  });

  test('clear empties the registry — applyTo registers nothing afterwards', () {
    _registerOne('acme.design_system', 'AcmeButton');
    LibraryRuntimeRegistry.clear();
    expect(_applyToFreshRuntime().libraries, isEmpty);
  });

  test('multi-segment namespace maps to multi-segment LibraryName', () {
    _registerOne('acme.design_system.icons', 'IconA');
    expect(
      _applyToFreshRuntime().libraries.keys,
      contains(const LibraryName(['acme', 'design_system', 'icons'])),
    );
  });

  test('applyTo registers each customer library independently', () {
    _registerOne('acme.design_system', 'A');
    _registerOne('beta.design_system', 'B');
    expect(
      _applyToFreshRuntime().libraries.keys,
      containsAll(<LibraryName>[
        const LibraryName(['acme', 'design_system']),
        const LibraryName(['beta', 'design_system']),
      ]),
    );
  });

  test('register rejects reserved built-in namespaces (typed singleton)', () {
    expect(
      () => LibraryRuntimeRegistry.register(
        WidgetLibrary.core,
        [RestageWidgetFactory(name: 'X', builder: _stubBuilder)],
      ),
      throwsAssertionError,
    );
  });

  test('register rejects reserved built-in namespaces (custom string)', () {
    expect(
      () => _registerOne('restage.material', 'X'),
      throwsAssertionError,
    );
  });

  test('register rejects duplicate widget names within one library', () {
    expect(
      () => LibraryRuntimeRegistry.register(
        const WidgetLibrary.custom('acme.design_system'),
        [
          RestageWidgetFactory(name: 'Same', builder: _stubBuilder),
          RestageWidgetFactory(name: 'Same', builder: _stubBuilder),
        ],
      ),
      throwsAssertionError,
    );
  });

  test('register accepts an empty widget list', () {
    LibraryRuntimeRegistry.register(
      const WidgetLibrary.custom('acme.design_system'),
      const [],
    );

    final library = _applyToFreshRuntime()
            .libraries[const LibraryName(['acme', 'design_system'])]!
        as LocalWidgetLibrary;
    expect(library.widgets, isEmpty);
  });

  group('capability version tracking', () {
    void registerVersioned(String namespace, {int? capabilityVersion}) {
      LibraryRuntimeRegistry.register(
        WidgetLibrary.custom(namespace),
        [RestageWidgetFactory(name: 'W', builder: _stubBuilder)],
        capabilityVersion: capabilityVersion,
      );
    }

    test('satisfies a requirement at or below the registered version', () {
      registerVersioned('acme.widgets', capabilityVersion: 3);
      expect(
        LibraryRuntimeRegistry.satisfies(
          const LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
        ),
        isTrue,
      );
      expect(
        LibraryRuntimeRegistry.satisfies(
          const LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
        ),
        isTrue,
      );
    });

    test('does not satisfy a requirement above the registered version', () {
      registerVersioned('acme.widgets', capabilityVersion: 2);
      expect(
        LibraryRuntimeRegistry.satisfies(
          const LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
        ),
        isFalse,
      );
    });

    test('does not satisfy an unregistered namespace (fail-closed)', () {
      expect(
        LibraryRuntimeRegistry.satisfies(
          const LibraryRequirement(namespace: 'ghost.widgets', minVersion: 1),
        ),
        isFalse,
      );
    });

    test('a versionless registration satisfies no requirement (fail-closed)',
        () {
      registerVersioned('acme.widgets'); // no capabilityVersion declared
      expect(
        LibraryRuntimeRegistry.satisfies(
          const LibraryRequirement(namespace: 'acme.widgets', minVersion: 1),
        ),
        isFalse,
      );
    });

    test('re-registering updates the recorded capability version', () {
      registerVersioned('acme.widgets', capabilityVersion: 2);
      registerVersioned('acme.widgets', capabilityVersion: 5);
      expect(
        LibraryRuntimeRegistry.satisfies(
          const LibraryRequirement(namespace: 'acme.widgets', minVersion: 5),
        ),
        isTrue,
      );
    });

    test('isRegistered + registeredVersion expose diagnostic primitives', () {
      registerVersioned('acme.widgets', capabilityVersion: 4);
      expect(LibraryRuntimeRegistry.isRegistered('acme.widgets'), isTrue);
      expect(LibraryRuntimeRegistry.isRegistered('ghost.widgets'), isFalse);
      expect(LibraryRuntimeRegistry.registeredVersion('acme.widgets'), 4);
      expect(LibraryRuntimeRegistry.registeredVersion('ghost.widgets'), isNull);
    });

    test('registeredVersion is null for a versionless registration', () {
      registerVersioned('acme.widgets');
      expect(LibraryRuntimeRegistry.isRegistered('acme.widgets'), isTrue);
      expect(LibraryRuntimeRegistry.registeredVersion('acme.widgets'), isNull);
    });
  });
}
