import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// The opaque-record wire contract (`PropertyType.unknown` +
/// `ScalarShape.opaqueRecord()`) is CONSTRUCTED locally by the codegen, so the
/// catalog codec must serialize it. These pin (a) that the recognition
/// predicate is EXACT — it must not capture any other opaque scalar — and
/// (b) that `encodeCatalog` accepts and round-trips the contract.
///
/// Runs with asserts ON (the default under `dart test`). The codec's encode
/// asserts are stripped in an AOT build, so a `dart run`-only exercise of this
/// path proves nothing about them.
void main() {
  group('the opaque-record marker is exact', () {
    test('opaqueRecord() carries unknown + the dart:core#Record category ref',
        () {
      final shape = ScalarShape.opaqueRecord();
      expect(shape.propertyType, PropertyType.unknown);
      expect(shape.dartTypeRef, kRecordTypeRef);
      expect(shape.dartTypeRef!.libraryUri, 'dart:core');
      expect(shape.dartTypeRef!.symbolName, 'Record');
      expect(shape.isOpaqueRecord, isTrue);
    });

    test('an ordinary scalar is not an opaque record', () {
      const shape = ScalarShape(propertyType: PropertyType.string);
      expect(shape.isOpaqueRecord, isFalse);
    });

    test('an UNMARKED opaque scalar is not an opaque record', () {
      // A null dartTypeRef would make the predicate "any opaque scalar" —
      // unowned space that would silently capture the next opaque scalar
      // contract anyone adds. The category ref keeps the predicate exact.
      const shape = ScalarShape(propertyType: PropertyType.unknown);
      expect(shape.isOpaqueRecord, isFalse);
    });

    test('an opaque scalar carrying a DIFFERENT category ref is not one', () {
      const shape = ScalarShape(
        propertyType: PropertyType.unknown,
        dartTypeRef: DartTypeRef(libraryUri: 'dart:core', symbolName: 'Map'),
      );
      expect(shape.isOpaqueRecord, isFalse);
    });

    test('the category ref alone, without unknown, is not one', () {
      const shape = ScalarShape(
        propertyType: PropertyType.string,
        dartTypeRef: kRecordTypeRef,
      );
      expect(shape.isOpaqueRecord, isFalse);
    });
  });

  test('encodeCatalog round-trips an opaque-record property + field', () {
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
            // A nested record FIELD (hits _structuredFieldToJson's assert).
            StructuredField(
              wireId: WireId('p0003'),
              name: 'meta',
              type: PropertyType.unknown,
              description: '',
              valueShape: ScalarShape.opaqueRecord(),
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
          properties: [
            // A record widget PROPERTY (hits _propertyToJson's assert).
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'heading',
              type: PropertyType.unknown,
              description: '',
              required: true,
              valueShape: ScalarShape.opaqueRecord(),
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
    expect((prop.valueShape! as ScalarShape).isOpaqueRecord, isTrue);

    final field = decoded.structuredTypes.single.fields
        .firstWhere((f) => f.name == 'meta');
    expect(field.type, PropertyType.unknown);
    expect(field.valueShape, isA<ScalarShape>());
    expect((field.valueShape! as ScalarShape).isOpaqueRecord, isTrue);

    // Re-encoding the decoded catalog is byte-stable: the marker survives a
    // decode -> re-encode pass unchanged (the property the contract relies on
    // for an older reader passing the shape through the catalog-merge path).
    expect(encodeCatalog(decoded), encoded);
  });
}
