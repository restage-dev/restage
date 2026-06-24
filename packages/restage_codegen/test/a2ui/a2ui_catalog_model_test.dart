import 'package:restage_codegen/src/a2ui/a2ui_catalog_model.dart';
import 'package:restage_codegen/src/a2ui/a2ui_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('A2uiLibraryCapability', () {
    test('toJson emits the namespace + version', () {
      const cap = A2uiLibraryCapability(namespace: 'acme.widgets', version: 3);
      expect(cap.toJson(), {'namespace': 'acme.widgets', 'version': 3});
    });

    test('value equality', () {
      expect(
        const A2uiLibraryCapability(namespace: 'a', version: 2),
        const A2uiLibraryCapability(namespace: 'a', version: 2),
      );
      expect(
        const A2uiLibraryCapability(namespace: 'a', version: 2),
        isNot(const A2uiLibraryCapability(namespace: 'a', version: 3)),
      );
    });
  });

  group('RestageCapabilityStamp', () {
    test('sorts availableLibraries + perItemSinceVersion canonically', () {
      final stamp = RestageCapabilityStamp(
        catalogContentVersion: 2,
        availableLibraries: const [
          A2uiLibraryCapability(namespace: 'b.lib', version: 1),
          A2uiLibraryCapability(namespace: 'a.lib', version: 4),
        ],
        perItemSinceVersion: const {'Z': 1, 'A': 2},
      );
      expect(
        stamp.availableLibraries.map((l) => l.namespace).toList(),
        ['a.lib', 'b.lib'],
      );
      expect(stamp.perItemSinceVersion.keys.toList(), ['A', 'Z']);
    });

    test('toJson emits all three axes, availableLibraries always (incl [])',
        () {
      final stamp = RestageCapabilityStamp(
        catalogContentVersion: 5,
        availableLibraries: const [],
        perItemSinceVersion: const {'A': 1},
      );
      expect(stamp.toJson(), {
        'catalogContentVersion': 5,
        'availableLibraries': <Object?>[],
        'perItemSinceVersion': {'A': 1},
      });
    });

    test('toJson emits the sorted custom-library axis', () {
      final stamp = RestageCapabilityStamp(
        catalogContentVersion: 2,
        availableLibraries: const [
          A2uiLibraryCapability(namespace: 'acme.widgets', version: 3),
        ],
        perItemSinceVersion: const {'AcmeBanner': 1},
      );
      expect(stamp.toJson()['availableLibraries'], [
        {'namespace': 'acme.widgets', 'version': 3},
      ]);
    });
  });

  group('RestageStampedA2uiCatalog.toJson', () {
    RestageStampedA2uiCatalog stamped({
      required RestageCapabilityStamp stamp,
      required List<A2uiComponent> components,
    }) =>
        RestageStampedA2uiCatalog(stamp: stamp, components: components);

    test('emits the Restage-stamped A2UI catalog wrapper', () {
      final catalog = stamped(
        stamp: RestageCapabilityStamp(
          catalogContentVersion: 1,
          availableLibraries: const [],
          perItemSinceVersion: const {'Text': 1},
        ),
        components: const [
          A2uiComponent(name: 'Text', dataSchema: {'type': 'object'}),
        ],
      );
      final json = catalog.toJson();

      expect(json['restageCapability'], {
        'catalogContentVersion': 1,
        'availableLibraries': <Object?>[],
        'perItemSinceVersion': {'Text': 1},
      });

      final a2ui = json['a2uiCatalog']! as Map<String, Object?>;
      expect(a2ui[r'$schema'], kA2uiSchemaDialect);
      expect(a2ui['a2uiProtocolVersion'], kA2uiProtocolVersion);
      expect((a2ui['components']! as Map)['Text'], {'type': 'object'});
      expect(a2ui['functions'], <String, Object?>{});
    });

    test('document id for a built-in-only catalog is the content version', () {
      final catalog = stamped(
        stamp: RestageCapabilityStamp(
          catalogContentVersion: 2,
          availableLibraries: const [],
          perItemSinceVersion: const {'Text': 1},
        ),
        components: const [
          A2uiComponent(name: 'Text', dataSchema: {}),
        ],
      );
      expect(catalog.documentId, 'restage:catalog/2');
      final a2ui = catalog.toJson()['a2uiCatalog']! as Map<String, Object?>;
      expect(a2ui[r'$id'], 'restage:catalog/2');
      expect(a2ui['catalogId'], 'restage:catalog/2');
    });

    test('document id incorporates the custom-library capability vector', () {
      final catalog = stamped(
        stamp: RestageCapabilityStamp(
          catalogContentVersion: 2,
          availableLibraries: const [
            A2uiLibraryCapability(namespace: 'acme.widgets', version: 3),
            A2uiLibraryCapability(namespace: 'zed.lib', version: 1),
          ],
          perItemSinceVersion: const {'AcmeBanner': 1},
        ),
        components: const [
          A2uiComponent(name: 'AcmeBanner', dataSchema: {}),
        ],
      );
      // Deterministic + unique per distinct capability vector; libraries are
      // already canonically sorted by the stamp.
      expect(catalog.documentId, 'restage:catalog/2+acme.widgets@3_zed.lib@1');
    });

    test('components are emitted in sorted-name order', () {
      final catalog = stamped(
        stamp: RestageCapabilityStamp(
          catalogContentVersion: 1,
          availableLibraries: const [],
          perItemSinceVersion: const {'B': 1, 'A': 1},
        ),
        components: const [
          A2uiComponent(name: 'B', dataSchema: {}),
          A2uiComponent(name: 'A', dataSchema: {}),
        ],
      );
      final a2ui = catalog.toJson()['a2uiCatalog']! as Map<String, Object?>;
      expect((a2ui['components']! as Map).keys.toList(), ['A', 'B']);
    });
  });
}
