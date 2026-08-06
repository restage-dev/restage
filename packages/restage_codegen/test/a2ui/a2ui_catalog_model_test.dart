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
      Map<String, Object?> functions = const {},
      List<String> systemPromptFragments = const [],
    }) =>
        RestageStampedA2uiCatalog(
          stamp: stamp,
          components: components,
          functions: functions,
          systemPromptFragments: systemPromptFragments,
        );

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

    test('document id is a lowercase SHA-256 content address', () {
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
      expect(
        catalog.documentId,
        matches(RegExp(r'^restage:catalog/sha256/[0-9a-f]{64}$')),
      );
      final a2ui = catalog.toJson()['a2uiCatalog']! as Map<String, Object?>;
      expect(a2ui[r'$id'], catalog.documentId);
      expect(a2ui['catalogId'], catalog.documentId);
    });

    test('digest preimage is non-self-referential and substitutes post-hash',
        () {
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
      final preimage = catalog.canonicalDigestPreimage;
      final expectedPreimage = <String>[
        r'{"a2uiCatalog":{"$schema":"https://json-schema.org/draft/2020-12/schema",',
        '"a2uiProtocolVersion":"0.9.1","components":{"AcmeBanner":{}},',
        '"functions":{},"systemPromptFragments":[',
        r'"For every A2UI createSurface message, set catalogId to \"',
        r'{{RESTAGE_A2UI_CATALOG_ID_SHA256}}\"."]},',
        '"restageCapability":{"availableLibraries":',
        '[{"namespace":"acme.widgets","version":3},',
        '{"namespace":"zed.lib","version":1}],',
        '"catalogContentVersion":2,',
        '"perItemSinceVersion":{"AcmeBanner":1}}}',
      ].join();
      expect(preimage, expectedPreimage);
      expect(
        catalog.documentId,
        'restage:catalog/sha256/'
        '13e1d1d8498b8b87c6ebf6228e1d390d702ddd52e8322e9fddfc30865079ffbf',
      );
      expect(
        preimage.split(kA2uiCatalogIdentitySentinel),
        hasLength(2),
        reason: 'the frozen identity sentinel must occur exactly once',
      );
      expect(preimage, isNot(contains(catalog.documentId)));
      expect(preimage, isNot(contains(r'"$id"')));
      expect(preimage, isNot(contains('"catalogId":')));
      expect(
        catalog.systemPromptFragments.single,
        allOf(
          contains(catalog.documentId),
          isNot(contains(kA2uiCatalogIdentitySentinel)),
        ),
      );
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

    test('recursive object-key reordering retains the content address', () {
      final stamp = RestageCapabilityStamp(
        catalogContentVersion: 1,
        availableLibraries: const [],
        perItemSinceVersion: const {'Card': 1},
      );
      final first = stamped(
        stamp: stamp,
        components: const [
          A2uiComponent(
            name: 'Card',
            dataSchema: {
              'type': 'object',
              'properties': {
                'title': {'type': 'string', 'description': 'Title'},
                'count': {'type': 'integer'},
              },
              'required': ['title'],
            },
          ),
        ],
      );
      final reordered = stamped(
        stamp: stamp,
        components: const [
          A2uiComponent(
            name: 'Card',
            dataSchema: {
              'required': ['title'],
              'properties': {
                'count': {'type': 'integer'},
                'title': {'description': 'Title', 'type': 'string'},
              },
              'type': 'object',
            },
          ),
        ],
      );

      expect(reordered.documentId, first.documentId);
      expect(reordered.canonicalDigestPreimage, first.canonicalDigestPreimage);
    });

    test('every registration-contract axis changes the content address', () {
      RestageStampedA2uiCatalog catalog({
        int contentVersion = 1,
        String scalarType = 'string',
        Map<String, Object?> functions = const {},
        List<String> fragments = const ['Card: Use for a card.'],
      }) =>
          stamped(
            stamp: RestageCapabilityStamp(
              catalogContentVersion: contentVersion,
              availableLibraries: const [],
              perItemSinceVersion: const {'Card': 1},
            ),
            components: [
              A2uiComponent(
                name: 'Card',
                dataSchema: {
                  'type': 'object',
                  'properties': {
                    'value': {'type': scalarType},
                  },
                  'required': const ['value'],
                },
              ),
            ],
            functions: functions,
            systemPromptFragments: fragments,
          );

      final base = catalog();
      expect(catalog(contentVersion: 2).documentId, isNot(base.documentId));
      expect(catalog(scalarType: 'integer').documentId, isNot(base.documentId));
      expect(
        catalog(
          functions: const {
            'lookup': {
              'description': 'Lookup a value.',
              'parameters': {'type': 'object'},
              'returnType': {'type': 'string'},
            },
          },
        ).documentId,
        isNot(base.documentId),
      );
      expect(
        catalog(fragments: const ['Card: Use for a compact card.']).documentId,
        isNot(base.documentId),
      );
    });

    test('old-vector-equal requiredness and scalar contracts cannot alias', () {
      RestageStampedA2uiCatalog catalog({
        required String type,
        required List<String> required,
      }) =>
          stamped(
            stamp: RestageCapabilityStamp(
              catalogContentVersion: 1,
              availableLibraries: const [],
              perItemSinceVersion: const {'Card': 1},
            ),
            components: [
              A2uiComponent(
                name: 'Card',
                dataSchema: {
                  'type': 'object',
                  'properties': {
                    'value': {'type': type},
                  },
                  'required': required,
                },
              ),
            ],
          );

      final requiredString = catalog(type: 'string', required: ['value']);
      final optionalString = catalog(type: 'string', required: const []);
      final requiredInteger = catalog(type: 'integer', required: ['value']);
      expect(optionalString.documentId, isNot(requiredString.documentId));
      expect(requiredInteger.documentId, isNot(requiredString.documentId));
    });

    test('lossy integer registrations fail instead of aliasing an exact one',
        () {
      RestageStampedA2uiCatalog catalog(int value) => stamped(
            stamp: RestageCapabilityStamp(
              catalogContentVersion: 1,
              availableLibraries: const [],
              perItemSinceVersion: const {'Card': 1},
            ),
            components: [
              A2uiComponent(
                name: 'Card',
                dataSchema: {
                  'type': 'object',
                  'properties': {
                    'value': {'const': value},
                  },
                },
              ),
            ],
          );

      final exact = catalog(int.parse('9007199254740992'));
      expect(exact.documentId, startsWith('restage:catalog/sha256/'));
      expect(
        () => catalog(int.parse('9007199254740993')),
        throwsFormatException,
      );
    });

    test('a non-identity fragment colliding with the sentinel fails loud', () {
      expect(
        () => stamped(
          stamp: RestageCapabilityStamp(
            catalogContentVersion: 1,
            availableLibraries: const [],
            perItemSinceVersion: const {'Card': 1},
          ),
          components: const [A2uiComponent(name: 'Card', dataSchema: {})],
          systemPromptFragments: const [
            'Card: reserved $kA2uiCatalogIdentitySentinel collision',
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
