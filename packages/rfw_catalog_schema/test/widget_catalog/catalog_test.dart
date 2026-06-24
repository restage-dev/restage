import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  test('Catalog stores schemaVersion, libraries, widgets', () {
    final catalog = Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-05-09T12:00:00Z',
      libraries: {
        WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Text',
          library: WidgetLibrary.core,
          category: WidgetCategory.decoration,
          description: 'Static text.',
          flutterType: 'package:flutter/widgets.dart#Text',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'text',
              type: PropertyType.string,
              description: 'The displayed text.',
              required: true,
            ),
          ],
        ),
      ],
    );
    expect(catalog.schemaVersion, kSupportedSchemaVersion);
    expect(catalog.libraries[WidgetLibrary.core]!.version, '0.1.0');
    // Per-library counts are computed from the entry lists, not stored.
    expect(catalog.widgetsIn(WidgetLibrary.core).length, 1);
    expect(catalog.widgets.first.name, 'Text');
    expect(catalog.widgets.first.wireId, WireId('w0001'));
    expect(
      catalog.widgets.first.flutterType,
      'package:flutter/widgets.dart#Text',
    );
    expect(catalog.widgets.first.decomposes, isEmpty);
    expect(catalog.widgets.first.properties.first.required, isTrue);
  });

  test('Catalog exposes per-library computed entry getters', () {
    final catalog = Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-05-09T12:00:00Z',
      libraries: const {},
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Text',
          library: WidgetLibrary.core,
          category: WidgetCategory.decoration,
          description: 'Static text.',
          flutterType: 'package:flutter/widgets.dart#Text',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: const [],
        ),
      ],
      structuredTypes: [
        StructuredEntry(
          wireId: WireId('s0001'),
          name: 'TextStyle',
          library: WidgetLibrary.core,
          description: 'Text style.',
          sourceType: 'package:flutter/painting.dart#TextStyle',
          fields: const [],
          variants: const [],
          stability: Stability.stable,
        ),
      ],
    );
    expect(catalog.widgetsIn(WidgetLibrary.core).length, 1);
    expect(catalog.widgetsIn(WidgetLibrary.material), isEmpty);
    expect(catalog.structuredTypesIn(WidgetLibrary.core).length, 1);
    expect(catalog.structuredTypesIn(WidgetLibrary.material), isEmpty);
    expect(catalog.unionsIn(WidgetLibrary.core), isEmpty);
    expect(catalog.designTokensIn(WidgetLibrary.core), isEmpty);
  });

  test('Catalog.findByName scoped to library', () {
    final catalog = Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-05-09T12:00:00Z',
      libraries: const {},
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Button',
          library: WidgetLibrary.material,
          category: WidgetCategory.action,
          description: '...',
          flutterType: 'package:flutter/material.dart#FilledButton',
          childrenSlot: ChildrenSlot.single,
          fires: const [],
          properties: const [],
        ),
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Button',
          library: WidgetLibrary.cupertino,
          category: WidgetCategory.action,
          description: '...',
          flutterType: 'package:flutter/cupertino.dart#CupertinoButton',
          childrenSlot: ChildrenSlot.single,
          fires: const [],
          properties: const [],
        ),
      ],
    );
    expect(
      catalog.findByName('Button', WidgetLibrary.material)?.library,
      WidgetLibrary.material,
    );
    expect(
      catalog.findByName('Button', WidgetLibrary.cupertino)?.library,
      WidgetLibrary.cupertino,
    );
    expect(catalog.findByName('Missing', WidgetLibrary.core), isNull);
  });

  test('WidgetEntry carries decomposes recipes for structured types', () {
    final entry = WidgetEntry(
      wireId: WireId('w0001'),
      name: 'Text',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'Static text with TextStyle decomposed.',
      flutterType: 'package:flutter/widgets.dart#Text',
      childrenSlot: ChildrenSlot.none,
      fires: const [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0001'),
          name: 'text',
          type: PropertyType.string,
          description: 'Text content.',
          required: true,
        ),
        PropertyEntry(
          wireId: WireId('p0002'),
          name: 'fontSize',
          type: PropertyType.length,
          description: 'Font size in logical pixels.',
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef: WireIdRef(
            library: 'restage.core',
            wireId: WireId('s0001'),
          ),
          flatProperties: {
            WireId('p0501'): WireId('p0002'),
          },
        ),
      ],
    );
    final recipe = entry.decomposes.single;
    expect(recipe.structuredRef.wireId, WireId('s0001'));
    expect(recipe.flatProperties[WireId('p0501')], WireId('p0002'));
  });
}
