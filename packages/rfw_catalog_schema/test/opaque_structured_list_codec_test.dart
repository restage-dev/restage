import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// The opaque list-of-structured wire contract (`PropertyType.unknown` +
/// `ListShape.opaqueStructured`) is CONSTRUCTED locally by the codegen, so the
/// catalog codec must serialize it — this pins that `encodeCatalog` accepts the
/// contract (not asserting `unknown` is decoder-only) and round-trips it
/// faithfully. Runs with asserts ON (the default under `dart test`).
void main() {
  test(
      'encodeCatalog round-trips an opaque list-of-structured property + field',
      () {
    final itemRef = WireIdRef(library: 'acme.widgets', wireId: WireId('s0001'));
    final catalog = Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {
        const WidgetLibrary.custom('acme.widgets'):
            const LibraryInfo(version: '0.0.0'),
      },
      structuredTypes: [
        StructuredEntry(
          wireId: WireId('s0001'),
          name: 'Item',
          library: const WidgetLibrary.custom('acme.widgets'),
          description: '',
          sourceType: 'package:acme/widgets.dart#Item',
          fields: [
            StructuredField(
              wireId: WireId('p0002'),
              name: 'label',
              type: PropertyType.string,
              description: '',
              required: true,
            ),
            // A nested list-of-structured FIELD (hits _structuredFieldToJson).
            StructuredField(
              wireId: WireId('p0003'),
              name: 'children',
              type: PropertyType.unknown,
              description: '',
              valueShape: ListShape.opaqueStructured(itemRef),
            ),
          ],
          variants: [ConstructorVariant(wireId: WireId('v0001'))],
        ),
      ],
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Board',
          library: const WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:acme/widgets.dart#Board',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            // A list-of-structured widget PROPERTY (hits _propertyToJson).
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'items',
              type: PropertyType.unknown,
              description: '',
              required: true,
              valueShape: ListShape.opaqueStructured(itemRef),
            ),
          ],
        ),
      ],
    );

    final decoded = decodeCatalog(encodeCatalog(catalog));

    final prop = decoded.widgets.single.properties.single;
    expect(prop.type, PropertyType.unknown);
    expect(prop.valueShape, isA<ListShape>());
    expect((prop.valueShape! as ListShape).isOpaqueStructuredList, isTrue);

    final listField = decoded.structuredTypes.single.fields
        .firstWhere((f) => f.name == 'children');
    expect(listField.type, PropertyType.unknown);
    expect(listField.valueShape, isA<ListShape>());
    expect((listField.valueShape! as ListShape).isOpaqueStructuredList, isTrue);
  });
}
