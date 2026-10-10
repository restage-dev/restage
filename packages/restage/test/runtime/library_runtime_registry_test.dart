import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// Direct path import — the registry is internal and not re-exported from
// the barrel, but tests reach in to verify per-mount apply behavior.
// ignore: implementation_imports
import 'package:restage/src/runtime/library_runtime_registry.dart';
// ignore: implementation_imports
import 'package:restage/src/measurement/measurement_rfw_presentation.dart';
// ignore: implementation_imports
import 'package:restage/src/delivery/surface_delivery_receipt.dart';
// ignore: implementation_imports
import 'package:restage/src/runtime/installed_widget_vocabulary.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        BlobRenderAccepted,
        BlobRenderCapabilityGate,
        BlobRenderRejected,
        BlobRenderRejectionReason,
        CapabilityManifest,
        InstalledLibrary,
        LibraryCompatibility,
        LibraryRequirement;
// `rfw` exposes its own `WidgetLibrary` (the runtime's decoded-library
// type). The catalog `WidgetLibrary` from `restage_shared` is what
// apps register with — hide rfw's so the catalog identifier is the
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

  test('register + applyTo registers custom library on the runtime', () {
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

  test('applyTo registers each custom library independently', () {
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

  test('reserved built-in namespaces assert without being registered', () {
    for (final namespace in <String>[
      'restage.core',
      'restage.material',
      'restage.cupertino',
    ]) {
      expect(
        () => LibraryRuntimeRegistry.register(
          WidgetLibrary.custom(namespace),
          const <RestageWidgetFactory>[],
          capabilityVersion: 1,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(LibraryRuntimeRegistry.isRegistered(namespace), isFalse);
    }
  });

  test('reserved measurement namespace asserts without claiming a capability',
      () {
    final namespace = kMeasurementRfwPresentationLibrary.parts.join('.');

    expect(
      () => _registerOne(namespace, 'CustomMeasurementPresented'),
      throwsAssertionError,
    );
    expect(LibraryRuntimeRegistry.isRegistered(namespace), isFalse);
    expect(
      LibraryRuntimeRegistry.installedSnapshot()
          .map((entry) => entry.namespace),
      isNot(contains(namespace)),
    );
    expect(
      Restage.widgetLibraryRegistrations
          .map((entry) => entry.library.namespace),
      isNot(contains(namespace)),
    );
  });

  test('normal custom-namespace registration is unchanged', () {
    LibraryRuntimeRegistry.register(
      const WidgetLibrary.custom('acme.widgets'),
      [RestageWidgetFactory(name: 'AcmeWidget', builder: _stubBuilder)],
      capabilityVersion: 2,
    );

    expect(LibraryRuntimeRegistry.isRegistered('acme.widgets'), isTrue);
    expect(LibraryRuntimeRegistry.registeredVersion('acme.widgets'), 2);
  });

  test('reserved preview namespace asserts without being registered', () {
    expect(
      () => _registerOne(kReservedPreviewLibraryName, 'AcmeWidget'),
      throwsAssertionError,
    );
    expect(
      LibraryRuntimeRegistry.isRegistered(kReservedPreviewLibraryName),
      isFalse,
    );
    expect(
      _applyToFreshRuntime().libraries.keys,
      isNot(
        contains(const LibraryName(<String>['restage', 'editor'])),
      ),
    );
  });

  test('reserved preview constructor asserts without registering its library',
      () {
    expect(
      () => _registerOne('acme.widgets', kReservedPreviewConstructorName),
      throwsAssertionError,
    );
    expect(LibraryRuntimeRegistry.isRegistered('acme.widgets'), isFalse);
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

  group('generation', () {
    RestageWidgetLibraryRegistration registration(
      String namespace,
      List<String> widgets, {
      int? capabilityVersion,
    }) =>
        RestageWidgetLibraryRegistration(
          library: WidgetLibrary.custom(namespace),
          capabilityVersion: capabilityVersion,
          widgets: [
            for (final name in widgets)
              RestageWidgetFactory(name: name, builder: _stubBuilder),
          ],
        );

    test('additive mount installs leave it unchanged', () {
      final start = LibraryRuntimeRegistry.generation;
      LibraryRuntimeRegistry.install(
        registration('app.widgets', ['Badge'], capabilityVersion: 1),
      );
      LibraryRuntimeRegistry.install(
        registration('app.widgets', ['Badge', 'Chip'], capabilityVersion: 1),
      );
      LibraryRuntimeRegistry.install(
        registration('app.cards', ['Card'], capabilityVersion: 2),
      );
      LibraryRuntimeRegistry.install(
        registration('app.widgets', ['Badge'], capabilityVersion: 2),
      );

      expect(LibraryRuntimeRegistry.generation, start);
      expect(LibraryRuntimeRegistry.registeredVersion('app.widgets'), 2);
    });

    test('a registration that replaces a namespace changes it', () {
      LibraryRuntimeRegistry.install(
        registration('app.widgets', ['Badge'], capabilityVersion: 1),
      );
      final installed = LibraryRuntimeRegistry.generation;
      _registerOne('app.widgets', 'Chip');

      expect(LibraryRuntimeRegistry.generation, isNot(installed));
    });
  });

  group('compatibleSince', () {
    const requires3 =
        LibraryRequirement(namespace: 'acme.widgets', minVersion: 3);
    const requires4 =
        LibraryRequirement(namespace: 'acme.widgets', minVersion: 4);
    const requires5 =
        LibraryRequirement(namespace: 'acme.widgets', minVersion: 5);

    CapabilityManifest manifest(LibraryRequirement requirement) =>
        CapabilityManifest(builtInFloor: 1, requiredLibraries: [requirement]);

    RestageWidgetLibraryRegistration registration({
      required int capabilityVersion,
      int? compatibleSince,
      List<String> widgets = const ['W'],
    }) =>
        RestageWidgetLibraryRegistration(
          library: WidgetLibrary.custom('acme.widgets'),
          capabilityVersion: capabilityVersion,
          compatibleSince: compatibleSince,
          widgets: [
            for (final name in widgets)
              RestageWidgetFactory(name: name, builder: _stubBuilder),
          ],
        );

    InstalledLibrary snapshot() =>
        LibraryRuntimeRegistry.installedSnapshot().single;

    test('a declared break refuses older content and reports it', () {
      Restage.registerWidgetLibrary(
        WidgetLibrary.custom('acme.widgets'),
        widgets: [RestageWidgetFactory(name: 'W', builder: _stubBuilder)],
        capabilityVersion: 4,
        compatibleSince: 4,
      );

      expect(LibraryRuntimeRegistry.satisfies(requires3), isFalse);
      expect(LibraryRuntimeRegistry.satisfies(requires4), isTrue);
      expect(
        LibraryRuntimeRegistry.compatibilityOf(requires3),
        LibraryCompatibility.contractBroken,
      );
      expect(
        LibraryRuntimeRegistry.describeGap(requires3),
        'installed v4, compatible since v4',
      );
      expect(
        LibraryRuntimeRegistry.receiptReasonFor(manifest(requires3)),
        SurfaceDeliveryReceiptReason.incompatibleLibrary,
      );
      expect(
        LibraryRuntimeRegistry.receiptReasonFor(manifest(requires5)),
        SurfaceDeliveryReceiptReason.unsupported,
      );
      expect(
        LibraryRuntimeRegistry.receiptReasonForLibraries(
          const [requires5, requires3],
        ),
        SurfaceDeliveryReceiptReason.incompatibleLibrary,
      );
      expect(
        snapshot(),
        const InstalledLibrary(
          namespace: 'acme.widgets',
          version: 4,
          compatibleSince: 4,
        ),
      );

      final verdict = BlobRenderCapabilityGate.evaluate(
        required: manifest(requires3),
        installed: currentInstalledCapability(),
      );
      expect(
        (verdict as BlobRenderRejected).reason,
        BlobRenderRejectionReason.requiredLibraryContractBroken,
      );
    });

    test('an additive bump still renders older content', () {
      Restage.registerWidgetLibrary(
        WidgetLibrary.custom('acme.widgets'),
        widgets: [RestageWidgetFactory(name: 'W', builder: _stubBuilder)],
        capabilityVersion: 4,
      );

      expect(LibraryRuntimeRegistry.satisfies(requires3), isTrue);
      expect(
        BlobRenderCapabilityGate.evaluate(
          required: manifest(requires3),
          installed: currentInstalledCapability(),
        ),
        const BlobRenderAccepted(),
      );
      expect(snapshot().toJson().containsKey('compatibleSince'), isFalse);
    });

    test('a missing or older library keeps the unsupported reason', () {
      expect(
        LibraryRuntimeRegistry.receiptReasonFor(manifest(requires3)),
        SurfaceDeliveryReceiptReason.unsupported,
      );
      LibraryRuntimeRegistry.install(registration(capabilityVersion: 2));
      expect(
        LibraryRuntimeRegistry.receiptReasonFor(manifest(requires3)),
        SurfaceDeliveryReceiptReason.unsupported,
      );
    });

    test('an install merge takes compatibleSince from the higher version', () {
      LibraryRuntimeRegistry.install(registration(capabilityVersion: 3));
      LibraryRuntimeRegistry.install(
        registration(capabilityVersion: 4, compatibleSince: 4),
      );
      expect(snapshot().compatibleSince, 4);

      LibraryRuntimeRegistry.install(
        registration(
          capabilityVersion: 3,
          compatibleSince: 1,
          widgets: ['W', 'X'],
        ),
      );
      expect(snapshot().version, 4);
      expect(snapshot().compatibleSince, 4);
    });

    test('an install merge at one version keeps the higher compatibleSince',
        () {
      final start = LibraryRuntimeRegistry.generation;
      LibraryRuntimeRegistry.install(registration(capabilityVersion: 4));
      LibraryRuntimeRegistry.install(
        registration(capabilityVersion: 4, compatibleSince: 3),
      );
      expect(snapshot().compatibleSince, 3);
      LibraryRuntimeRegistry.install(
        registration(capabilityVersion: 4, compatibleSince: 2),
      );
      expect(snapshot().compatibleSince, 3);
      expect(LibraryRuntimeRegistry.generation, start);
    });

    test('a constant registration carries compatibleSince', () {
      LibraryRuntimeRegistry.install(
        RestageWidgetLibraryRegistration.constant(
          library: WidgetLibrary.custom('acme.widgets'),
          widgets: const [],
          capabilityVersion: 4,
          compatibleSince: 4,
        ),
      );
      expect(snapshot().compatibleSince, 4);
      expect(LibraryRuntimeRegistry.satisfies(requires3), isFalse);
    });

    test('a registration rejects compatibleSince outside 1..version', () {
      expect(
        () => registration(capabilityVersion: 4, compatibleSince: 5),
        throwsArgumentError,
      );
      expect(
        () => registration(capabilityVersion: 4, compatibleSince: 0),
        throwsArgumentError,
      );
      expect(
        () => RestageWidgetLibraryRegistration(
          library: WidgetLibrary.custom('acme.widgets'),
          widgets: const [],
          compatibleSince: 1,
        ),
        throwsArgumentError,
      );
    });
  });
}
