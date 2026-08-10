import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// A one-widget customer catalog with a widget description and one described
/// scalar property, so the generated schema carries both a component-level
/// and a property-level `description`.
Catalog _catalogWithDescriptions({
  String widgetDescription = 'A short note.',
  String propertyDescription = 'The note text.',
}) {
  const acme = WidgetLibrary.custom('acme.widgets');
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      acme: const LibraryInfo(version: '1.0.0', capabilityVersion: 1),
    },
    widgets: [
      WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'Note',
        library: acme,
        category: WidgetCategory.decoration,
        description: widgetDescription,
        flutterType: 'package:acme_widgets/note.dart#Note',
        childrenSlot: ChildrenSlot.none,
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'text',
            type: PropertyType.string,
            description: propertyDescription,
            required: true,
          ),
        ],
      ),
    ],
  );
}

void main() {
  test(
      'property + component descriptions land in the generated .g.dart '
      'schema', () {
    final dart = emitA2uiCatalogDart(_catalogWithDescriptions());
    expect(dart, contains("description: 'The note text.'"));
    expect(dart, contains("description: 'A short note.'"));
  });

  test('descriptions land identically in the .a2ui.json component schema', () {
    final stamp = emitA2uiCatalog(_catalogWithDescriptions()).toJson();
    final a2uiCatalog = stamp['a2uiCatalog']! as Map<String, Object?>;
    final components = a2uiCatalog['components']! as Map<String, Object?>;
    final note = components['Note']! as Map<String, Object?>;
    expect(note['description'], 'A short note.');
    final properties = note['properties']! as Map<String, Object?>;
    final props = properties['props']! as Map<String, Object?>;
    final customerProperties = props['properties']! as Map<String, Object?>;
    expect(
      customerProperties['text'],
      containsPair('description', 'The note text.'),
    );
  });

  test(
      r'a description containing "$", a CRLF, a single quote, and a '
      'newline emits without throwing and with the correctly-escaped '
      'literal', () {
    const widgetDescription = "Costs \$5/mo\r\nDon't miss \$Widget.\nEnd.";
    final dart = emitA2uiCatalogDart(
      _catalogWithDescriptions(widgetDescription: widgetDescription),
    );
    expect(
      dart,
      contains(
        r"description: 'Costs \$5/mo\r\nDon\'t miss \$Widget.\nEnd.'",
      ),
    );
  });

  test(
      r'a described property containing "$" emits the correctly-escaped '
      'literal in the schema', () {
    const propertyDescription = r'Price is $9.99 for $Plan.';
    final dart = emitA2uiCatalogDart(
      _catalogWithDescriptions(propertyDescription: propertyDescription),
    );
    expect(
      dart,
      contains(r"description: 'Price is \$9.99 for \$Plan.'"),
    );
  });

  test('an absent (empty) description omits the key', () {
    final catalog = _catalogWithDescriptions(
      widgetDescription: '',
      propertyDescription: '',
    );

    final dart = emitA2uiCatalogDart(catalog);
    expect(dart, isNot(contains('description:')));

    final stamp = emitA2uiCatalog(catalog).toJson();
    final a2uiCatalog = stamp['a2uiCatalog']! as Map<String, Object?>;
    final components = a2uiCatalog['components']! as Map<String, Object?>;
    final note = components['Note']! as Map<String, Object?>;
    expect(note.containsKey('description'), isFalse);
    final properties = note['properties']! as Map<String, Object?>;
    final props = properties['props']! as Map<String, Object?>;
    final customerProperties = props['properties']! as Map<String, Object?>;
    final text = customerProperties['text']! as Map<String, Object?>;
    expect(text.containsKey('description'), isFalse);
  });
}
