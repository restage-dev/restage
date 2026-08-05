import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// The opaque-map wire contract (`PropertyType.unknown` +
/// `ScalarShape.opaqueStringKeyedMap()`) is constructed locally by the codegen,
/// so the catalog codec must serialize it. These pin (a) that the recognition
/// predicate is exact — it must not capture any other opaque scalar — and
/// (b) that `encodeCatalog` accepts and round-trips the contract.
///
/// Runs with asserts on (the default under `dart test`). The codec's encode
/// asserts are stripped in an AOT build, so a `dart run`-only exercise of this
/// path proves nothing about them.
void main() {
  group('the opaque-map marker is exact', () {
    test(
      'opaqueStringKeyedMap() carries unknown + the dart:core#Map category '
      'ref',
      () {
        final shape = ScalarShape.opaqueStringKeyedMap();
        expect(shape.propertyType, PropertyType.unknown);
        expect(shape.dartTypeRef, kMapTypeRef);
        expect(shape.dartTypeRef!.libraryUri, 'dart:core');
        expect(shape.dartTypeRef!.symbolName, 'Map');
        expect(shape.isOpaqueStringKeyedMap, isTrue);
      },
    );

    test('an ordinary scalar is not an opaque map', () {
      const shape = ScalarShape(propertyType: PropertyType.string);
      expect(shape.isOpaqueStringKeyedMap, isFalse);
    });

    test('an UNMARKED opaque scalar is not an opaque map', () {
      // A null dartTypeRef would make the predicate match any opaque scalar:
      // unowned space that would silently capture the next opaque scalar
      // contract anyone adds. The category ref keeps the predicate exact.
      const shape = ScalarShape(propertyType: PropertyType.unknown);
      expect(shape.isOpaqueStringKeyedMap, isFalse);
    });

    test('an opaque scalar carrying a DIFFERENT category ref is not one', () {
      const shape = ScalarShape(
        propertyType: PropertyType.unknown,
        dartTypeRef: kRecordTypeRef,
      );
      expect(shape.isOpaqueStringKeyedMap, isFalse);
    });

    test('the category ref alone, without unknown, is not one', () {
      const shape = ScalarShape(
        propertyType: PropertyType.string,
        dartTypeRef: kMapTypeRef,
      );
      expect(shape.isOpaqueStringKeyedMap, isFalse);
    });

    test('the two opaque scalar markers are mutually exclusive', () {
      final record = ScalarShape.opaqueRecord();
      final map = ScalarShape.opaqueStringKeyedMap();

      // Both shapes use ScalarShape(unknown, <some ref>), so checking only
      // propertyType would confuse them and route a map slot down the record
      // path.
      expect(record.isOpaqueRecord, isTrue);
      expect(record.isOpaqueStringKeyedMap, isFalse);
      expect(map.isOpaqueStringKeyedMap, isTrue);
      expect(map.isOpaqueRecord, isFalse);
      expect(record == map, isFalse);
    });
  });

  test('encodeCatalog round-trips an opaque-map property + field', () {
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
            // A nested map field (hits _structuredFieldToJson's assert).
            StructuredField(
              wireId: WireId('p0003'),
              name: 'meta',
              type: PropertyType.unknown,
              description: '',
              valueShape: ScalarShape.opaqueStringKeyedMap(),
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
            // A map widget property (hits _propertyToJson's assert).
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'heading',
              type: PropertyType.unknown,
              description: '',
              required: true,
              valueShape: ScalarShape.opaqueStringKeyedMap(),
            ),
          ],
        ),
      ],
    );

    final encoded = encodeCatalog(catalog);
    final decoded = decodeCatalog(encoded);

    final prop = decoded.widgets.single.properties.single;
    expect(prop.type, PropertyType.unknown);
    expect(prop.valueShape, isA<ScalarShape>());
    expect(
      (prop.valueShape! as ScalarShape).isOpaqueStringKeyedMap,
      isTrue,
    );

    final field = decoded.structuredTypes.single.fields
        .firstWhere((f) => f.name == 'meta');
    expect(field.type, PropertyType.unknown);
    expect(field.valueShape, isA<ScalarShape>());
    expect(
      (field.valueShape! as ScalarShape).isOpaqueStringKeyedMap,
      isTrue,
    );

    // Re-encoding the decoded catalog is byte-stable: the marker survives a
    // decode -> re-encode pass unchanged.
    expect(encodeCatalog(decoded), encoded);
  });
}
