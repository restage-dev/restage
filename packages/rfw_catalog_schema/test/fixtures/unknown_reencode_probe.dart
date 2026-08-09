import 'dart:io';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

void main() {
  final catalog = Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '2026-08-08T00:00:00Z',
    libraries: {
      const WidgetLibrary.custom('acme.widgets'):
          const LibraryInfo(version: '1.0.0'),
    },
    widgets: [
      WidgetEntry(
        wireId: WireId('w0001'),
        name: 'Probe',
        library: const WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.input,
        description: 'A probe.',
        flutterType: 'package:acme/widgets.dart#Probe',
        childrenSlot: ChildrenSlot.none,
        properties: [
          PropertyEntry(
            wireId: WireId('p0001'),
            name: 'futureValue',
            type: PropertyType.unknown,
            description: 'A future value.',
          ),
        ],
      ),
    ],
  );

  try {
    encodeCatalog(catalog);
  } on CatalogSchemaException catch (error) {
    stdout.writeln(error.runtimeType);
    return;
  }
  stderr.writeln('lossy unknown property encoded without a runtime guard');
  exitCode = 1;
}
