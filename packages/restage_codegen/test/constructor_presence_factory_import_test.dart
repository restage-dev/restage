import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('presence-only generated factories import the core-owned helper',
      () async {
    final catalog = Catalog(
      schemaVersion: 5,
      generatedAt: '2026-10-18T00:00:00Z',
      libraries: {WidgetLibrary.core: const LibraryInfo(version: '1.0.0')},
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'PresenceProbe',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: 'Native factory presence probe.',
          flutterType: 'package:example/widgets.dart#PresenceProbe',
          childrenSlot: ChildrenSlot.none,
          properties: [
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'label',
              type: PropertyType.string,
              description: 'Optional label.',
              constructorNullable: true,
              constructorDefault: const DartConstScalar('native'),
            ),
          ],
        ),
      ],
    );
    await testBuilder(
      factoryFunctionBuilder(BuilderOptions.empty),
      {
        'restage_core|lib/src/widget_catalog/catalog.json':
            encodeCatalog(catalog),
      },
      rootPackage: 'restage_core',
      outputs: {
        'restage_core|lib/src/registration.g.dart': decodedMatches(
          allOf(
            contains('RestageRfwConstructorPresence.read('),
            contains("import 'package:restage_core/restage_core.dart';"),
            isNot(contains('RestageDecoders.')),
            isNot(contains("import 'package:restage/restage.dart';")),
          ),
        ),
      },
    );
  });
}
