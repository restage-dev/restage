import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

WidgetEntry _widget(WidgetBuilderParameter parameter) => WidgetEntry(
      wireId: WireId('w0001'),
      name: 'ProbeBuilder',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'Deferred layout.',
      flutterType: 'package:example/widgets.dart#ProbeBuilder',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
          wireId: WireId('p0001'),
          name: 'builder',
          type: PropertyType.widgetBuilder,
          description: 'Deferred child.',
          builderContract: WidgetBuilderContract(
            parameters: [
              WidgetBuilderParameter.buildContext,
              parameter,
            ],
          ),
        ),
      ],
    );

Catalog _catalog(WidgetBuilderParameter parameter) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-10-24T00:00:00Z',
      libraries: {WidgetLibrary.core: const LibraryInfo(version: '1.0.0')},
      widgets: [_widget(parameter)],
    );

void main() {
  test('builder contract survives schema to IR to schema lowering', () {
    final widget = _widget(WidgetBuilderParameter.boxConstraints);
    final lowered = const RestageCatalogGenAdapter().lowerWidgets([widget]);
    expect(lowered.single.properties.single.type, PropertyType.widgetBuilder);
    expect(
      lowered.single.properties.single.builderContract,
      widget.properties.single.builderContract,
    );
  });

  test('builder parameter identity changes are wire-shape changes', () {
    final changes = diffCatalogs(
      _catalog(WidgetBuilderParameter.boxConstraints),
      _catalog(WidgetBuilderParameter.orientation),
    );
    expect(
      changes.whereType<PropertyShapeChanged>().single.fields,
      contains('builderContract'),
    );
  });
}
