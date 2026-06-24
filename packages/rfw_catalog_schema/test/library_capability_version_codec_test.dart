import 'dart:convert';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// Builds a minimal single-library catalog whose one library carries
/// [capabilityVersion] (null leaves it undeclared).
Catalog _catalog({required WidgetLibrary library, int? capabilityVersion}) =>
    Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {
        library: LibraryInfo(
          version: '1.0.0',
          capabilityVersion: capabilityVersion,
        ),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'AcmeButton',
          library: library,
          category: WidgetCategory.layout,
          description: 'A button.',
          flutterType: 'package:acme/acme_button.dart#AcmeButton',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: const [],
        ),
      ],
    );

void main() {
  const customLib = WidgetLibrary.custom('acme.widgets');

  group('LibraryInfo.capabilityVersion through the catalog codec', () {
    test('a declared capabilityVersion round-trips', () {
      final input = _catalog(library: customLib, capabilityVersion: 5);
      final decoded = decodeCatalog(encodeCatalog(input));
      expect(decoded.libraries[customLib]!.capabilityVersion, 5);
    });

    test('an absent capabilityVersion decodes to null', () {
      // A built-in library never declares one — its content line is per-widget.
      final input = _catalog(library: WidgetLibrary.core);
      final decoded = decodeCatalog(encodeCatalog(input));
      expect(decoded.libraries[WidgetLibrary.core]!.capabilityVersion, isNull);
    });

    test(
        'a null capabilityVersion is OMITTED from the encoded JSON '
        '(byte-neutral)', () {
      final input = _catalog(library: WidgetLibrary.core);
      final json = jsonDecode(encodeCatalog(input)) as Map<String, dynamic>;
      final libraries = json['libraries'] as Map<String, dynamic>;
      final coreInfo = libraries['restage.core'] as Map<String, dynamic>;
      expect(coreInfo.containsKey('capabilityVersion'), isFalse);
    });

    test('a declared capabilityVersion IS emitted', () {
      final input = _catalog(library: customLib, capabilityVersion: 3);
      final json = jsonDecode(encodeCatalog(input)) as Map<String, dynamic>;
      final libraries = json['libraries'] as Map<String, dynamic>;
      final info = libraries['acme.widgets'] as Map<String, dynamic>;
      expect(info['capabilityVersion'], 3);
    });

    test('rejects an explicit null capabilityVersion (not treated as absent)',
        () {
      final json = jsonDecode(encodeCatalog(_catalog(library: customLib)))
          as Map<String, dynamic>;
      final libraries = json['libraries'] as Map<String, dynamic>;
      (libraries['acme.widgets'] as Map<String, dynamic>)['capabilityVersion'] =
          null;
      expect(
        () => decodeCatalog(jsonEncode(json)),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('rejects a non-positive capabilityVersion', () {
      final json = jsonDecode(encodeCatalog(_catalog(library: customLib)))
          as Map<String, dynamic>;
      final libraries = json['libraries'] as Map<String, dynamic>;
      (libraries['acme.widgets'] as Map<String, dynamic>)['capabilityVersion'] =
          0;
      expect(
        () => decodeCatalog(jsonEncode(json)),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('rejects a non-integer capabilityVersion', () {
      final json = jsonDecode(encodeCatalog(_catalog(library: customLib)))
          as Map<String, dynamic>;
      final libraries = json['libraries'] as Map<String, dynamic>;
      (libraries['acme.widgets'] as Map<String, dynamic>)['capabilityVersion'] =
          'two';
      expect(
        () => decodeCatalog(jsonEncode(json)),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    // The encode/source boundary must be as strict as decode: a catalog
    // carrying a non-positive capabilityVersion in memory must fail to encode,
    // not emit bytes the decoder will then reject (the builder must never
    // produce a catalog it cannot read back).
    test('rejects ENCODING a zero capabilityVersion', () {
      expect(
        () => encodeCatalog(_catalog(library: customLib, capabilityVersion: 0)),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('rejects ENCODING a negative capabilityVersion', () {
      expect(
        () =>
            encodeCatalog(_catalog(library: customLib, capabilityVersion: -1)),
        throwsA(isA<CatalogSchemaException>()),
      );
    });
  });

  group('@RestageLibrary.capabilityVersion source-boundary validation', () {
    test('the const constructor rejects a non-positive capabilityVersion', () {
      expect(
        () => RestageLibrary(
          library: customLib,
          capabilityVersion: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => RestageLibrary(
          library: customLib,
          capabilityVersion: -1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('the const constructor accepts null or a positive capabilityVersion',
        () {
      expect(
        const RestageLibrary(library: customLib).capabilityVersion,
        isNull,
      );
      expect(
        const RestageLibrary(library: customLib, capabilityVersion: 1)
            .capabilityVersion,
        1,
      );
    });
  });
}
