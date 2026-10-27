import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

Catalog _catalog({bool nullableResult = true}) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-10-24T00:00:00Z',
      libraries: {WidgetLibrary.core: const LibraryInfo(version: '1.0.0')},
      widgets: const [],
      structuredTypes: [
        StructuredEntry(
          wireId: WireId('s0001'),
          name: 'Delegate',
          library: WidgetLibrary.core,
          description: '',
          sourceType: 'src#Delegate',
          fields: [
            StructuredField(
              wireId: WireId('p0001'),
              name: 'builder',
              type: PropertyType.widgetBuilder,
              description: '',
              builderContract: const WidgetBuilderContract(
                parameters: [
                  WidgetBuilderParameter.buildContext,
                  WidgetBuilderParameter.itemIndex,
                ],
                nullableResult: true,
              ),
            ),
            StructuredField(
              wireId: WireId('p0002'),
              name: 'semanticIndexCallback',
              type: PropertyType.scalarCallback,
              description: '',
              scalarContract: ScalarCallbackContract(
                parameters: const [
                  ScalarCallbackParameter.widget,
                  ScalarCallbackParameter.itemIndex,
                ],
                nullableResult: nullableResult,
              ),
            ),
          ],
          variants: const [],
        ),
      ],
    );

void main() {
  test('structured callback contracts survive IR lowering', () {
    final source = _catalog();
    final lowered = const RestageCatalogGenAdapter().lowerCatalog(
      library: WidgetLibrary.core,
      generatedAt: '2026-10-24T00:00:00Z',
      version: '1.0.0',
      widgets: const [],
      structuredEntries: source.structuredTypes,
    );
    expect(
      lowered.structuredTypes.single.fields.first.builderContract,
      source.structuredTypes.single.fields.first.builderContract,
    );
    expect(
      lowered.structuredTypes.single.fields.last.scalarContract,
      source.structuredTypes.single.fields.last.scalarContract,
    );
  });

  test('structured callback result changes participate in fit diff', () {
    final changes = diffCatalogs(_catalog(), _catalog(nullableResult: false));
    expect(
      changes.whereType<PropertyShapeChanged>().single.fields,
      contains('scalarContract'),
    );
  });
}
