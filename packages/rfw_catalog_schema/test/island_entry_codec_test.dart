import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  Catalog catalog({int itemInputs = 0}) => Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-10-29T00:00:00Z',
        flutterVersion: '3.27.0',
        libraries: {
          WidgetLibrary.custom('app.islands'):
              const LibraryInfo(version: '1.0.0', islands: true),
        },
        widgets: [
          WidgetEntry(
            wireId: WireId('w0001'),
            name: 'Fade',
            library: WidgetLibrary.custom('app.islands'),
            category: null,
            description: 'Fade in Plans',
            flutterType: 'Fade',
            childrenSlot: ChildrenSlot.none,
            itemInputs: itemInputs,
            properties: const [],
          ),
        ],
      );

  test('itemInputs round-trips and is written only when set', () {
    final plain = encodeCatalog(catalog());
    expect(plain, isNot(contains('itemInputs')));
    final widget = decodeCatalog(
      encodeCatalog(catalog(itemInputs: 2)),
    ).widgets.single;
    expect(widget.itemInputs, 2);
  });

  test('a zero itemInputs is refused', () {
    final encoded = encodeCatalog(catalog(itemInputs: 1))
        .replaceFirst('"itemInputs": 1', '"itemInputs": 0');
    expect(
        () => decodeCatalog(encoded), throwsA(isA<CatalogSchemaException>()));
  });
}
