import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('PropertyEntry.defaultValue computed projection', () {
    PropertyEntry entry({DefaultValueSource? source, String? brandToken}) =>
        PropertyEntry(
          wireId: WireId('p0001'),
          name: 'x',
          type: PropertyType.boolean,
          description: 'd',
          defaultSource: source,
          defaultBrandToken: brandToken,
        );

    test('projects a LiteralDefault source value', () {
      expect(entry(source: const LiteralDefault(true)).defaultValue, true);
    });

    test('is null for a non-literal source', () {
      expect(
        entry(
          source: TokenRefDefault(
            WireIdRef(library: 'restage.core', wireId: WireId('t0001')),
          ),
        ).defaultValue,
        isNull,
      );
      expect(entry(source: const FlutterCtorDefault()).defaultValue, isNull);
    });

    test('is null when no source is declared', () {
      expect(entry().defaultValue, isNull);
    });

    test('defaultBrandToken stays an independent stored field', () {
      final e = entry(brandToken: 'primary');
      expect(e.defaultBrandToken, 'primary');
      expect(e.defaultValue, isNull);
      expect(e.defaultSource, isNull);
    });
  });

  group('PropertyEntry.defaultValue after decode (asymmetry fix)', () {
    test('a decoded literal default projects into defaultValue', () {
      final catalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2024-01-01T00:00:00.000Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: [
          WidgetEntry(
            wireId: WireId('w0001'),
            name: 'W',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: 'd',
            flutterType: 'package:flutter/widgets.dart#W',
            childrenSlot: ChildrenSlot.none,
            fires: const [],
            properties: [
              PropertyEntry(
                wireId: WireId('p0001'),
                name: 'flag',
                type: PropertyType.boolean,
                description: 'd',
                defaultSource: const LiteralDefault(true),
              ),
            ],
          ),
        ],
      );
      // Round-trip through the production codec: the codec serializes only
      // defaultSource (never the legacy defaultValue).
      final decoded = decodeCatalog(encodeCatalog(catalog));
      final prop = decoded.widgets.single.properties.single;
      expect(prop.defaultSource, const LiteralDefault(true));
      // Before the collapse, decode left the stored defaultValue null
      // (asymmetric); now it is a computed projection of the decoded
      // defaultSource.
      expect(prop.defaultValue, true);
    });
  });
}
