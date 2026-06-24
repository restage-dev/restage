import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Three-widget fixture: zero, one, and many decomposition recipes
/// (`SizedBox`, `Text`/`TextStyle`, `Container`/`BoxDecoration`+`EdgeInsets`).
///
/// Hand-allocated wire IDs follow the per-kind monotonic convention
/// (`w0001`+ for widgets, `p0001`+ for properties, `s0001`+ for
/// structured types). Current canonical fixtures stay bridge-free; legacy
/// projection coverage lives in the legacy codec tests.
final Catalog kExampleRegistry = Catalog(
  schemaVersion: kSupportedSchemaVersion,
  generatedAt: '2026-05-09T00:00:00Z',
  libraries: {
    WidgetLibrary.core: const LibraryInfo(version: '0.0.1'),
  },
  widgets: [
    WidgetEntry(
      wireId: WireId('w0001'),
      name: 'SizedBox',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'A box with explicit width and height.',
      flutterType: 'package:flutter/widgets.dart#SizedBox',
      childrenSlot: ChildrenSlot.single,
      fires: const [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0001'),
          name: 'width',
          type: PropertyType.length,
          description: 'Width in logical pixels.',
        ),
        PropertyEntry(
          wireId: WireId('p0002'),
          name: 'height',
          type: PropertyType.length,
          description: 'Height in logical pixels.',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0002'),
      name: 'Text',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'Static text. TextStyle fields are decomposed to flat '
          'properties.',
      flutterType: 'package:flutter/widgets.dart#Text',
      childrenSlot: ChildrenSlot.none,
      fires: const [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0003'),
          name: 'data',
          type: PropertyType.string,
          description: 'The displayed text.',
          required: true,
        ),
        PropertyEntry(
          wireId: WireId('p0004'),
          name: 'fontSize',
          type: PropertyType.length,
          description: 'Font size in logical pixels.',
        ),
        PropertyEntry(
          wireId: WireId('p0005'),
          name: 'fontWeight',
          type: PropertyType.fontWeight,
          description: 'Font weight.',
        ),
        PropertyEntry(
          wireId: WireId('p0006'),
          name: 'color',
          type: PropertyType.color,
          description: 'Text color.',
          defaultBrandToken: 'onBackground',
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef: WireIdRef(
            library: 'restage.core',
            wireId: WireId('s0001'),
          ),
          flatProperties: {
            WireId('p0501'): WireId('p0004'),
            WireId('p0502'): WireId('p0005'),
            WireId('p0503'): WireId('p0006'),
          },
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0003'),
      name: 'Container',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'A container with optional decoration and padding. '
          'BoxDecoration and EdgeInsets fields are decomposed to flat '
          'properties.',
      flutterType: 'package:flutter/widgets.dart#Container',
      childrenSlot: ChildrenSlot.single,
      fires: const [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0007'),
          name: 'width',
          type: PropertyType.length,
          description: 'Container width.',
        ),
        PropertyEntry(
          wireId: WireId('p0008'),
          name: 'height',
          type: PropertyType.length,
          description: 'Container height.',
        ),
        PropertyEntry(
          wireId: WireId('p0009'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Background color (decomposed from BoxDecoration).',
          defaultBrandToken: 'surface',
        ),
        PropertyEntry(
          wireId: WireId('p0010'),
          name: 'borderRadius',
          type: PropertyType.real,
          description: 'Corner radius (decomposed from BoxDecoration via '
              'BorderRadius.circular).',
        ),
        PropertyEntry(
          wireId: WireId('p0011'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'Padding inside the container.',
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef: WireIdRef(
            library: 'restage.core',
            wireId: WireId('s0002'),
          ),
          flatProperties: {
            WireId('p0510'): WireId('p0009'),
            WireId('p0511'): WireId('p0010'),
          },
        ),
        DecompositionRecipe(
          structuredRef: WireIdRef(
            library: 'restage.core',
            wireId: WireId('s0003'),
          ),
          flatProperties: {
            WireId('p0520'): WireId('p0011'),
          },
        ),
      ],
    ),
  ],
);
