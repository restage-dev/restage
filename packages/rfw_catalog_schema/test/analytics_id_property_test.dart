import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('analyticsId catalog property', () {
    test('is an optional string synthetic', () {
      final property = analyticsIdProperty();

      expect(property.wireId, WireId.unallocatedProperty);
      expect(property.name, kAnalyticsIdPropertyName);
      expect(property.type, PropertyType.string);
      expect(property.required, isFalse);
      expect(property.synthetic, kAnalyticsIdSyntheticStrategy);
      expect(property.positional, isFalse);
    });

    test('uses the bounded lowercase identifier grammar', () {
      final maximumLength = 'a${List.filled(127, 'x').join()}';
      final tooLong = 'a${List.filled(128, 'x').join()}';
      for (final value in [
        'checkout',
        'checkout.primary',
        'checkout:primary',
        'checkout-primary',
        'a1._:-',
        maximumLength,
      ]) {
        expect(isValidAnalyticsId(value), isTrue, reason: value);
      }

      for (final value in [
        '',
        'Checkout',
        'checkout primary',
        'checkout\nprimary',
        'café',
        '-checkout',
        '.checkout',
        'checkout/',
        tooLong,
      ]) {
        expect(isValidAnalyticsId(value), isFalse, reason: value);
      }
    });

    test('round-trips through the canonical catalog codec', () {
      final catalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: [
          WidgetEntry(
            wireId: WireId('w0001'),
            name: 'Probe',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: 'Probe widget.',
            flutterType: 'package:probe/probe.dart#Probe',
            childrenSlot: ChildrenSlot.none,
            properties: [
              analyticsIdProperty(wireId: WireId('p0001')),
            ],
          ),
        ],
      );

      final decoded =
          requireNativeCatalog(decodeCatalog(encodeCatalog(catalog)));
      final property = decoded.widgets.single.properties.single;
      expect(property.name, kAnalyticsIdPropertyName);
      expect(property.synthetic, kAnalyticsIdSyntheticStrategy);
      expect(property.type, PropertyType.string);
    });

    test('rejects duplicate property names in one widget', () {
      final catalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: [
          WidgetEntry(
            wireId: WireId('w0001'),
            name: 'Probe',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: 'Probe widget.',
            flutterType: 'package:probe/probe.dart#Probe',
            childrenSlot: ChildrenSlot.none,
            properties: [
              analyticsIdProperty(wireId: WireId('p0001')),
              analyticsIdProperty(wireId: WireId('p0002')),
            ],
          ),
        ],
      );

      expect(
        () => encodeCatalog(catalog),
        throwsA(isA<CatalogSchemaException>()),
      );
    });
  });
}
