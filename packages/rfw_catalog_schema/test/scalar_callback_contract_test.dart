import 'dart:convert';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const _semantic = ScalarCallbackContract(
  parameters: [
    ScalarCallbackParameter.widget,
    ScalarCallbackParameter.itemIndex,
  ],
);
const _key =
    ScalarCallbackContract(parameters: [ScalarCallbackParameter.valueKey]);
const _builder = WidgetBuilderContract(
  parameters: [
    WidgetBuilderParameter.buildContext,
    WidgetBuilderParameter.itemIndex,
  ],
  nullableResult: true,
);

Catalog _catalog({
  ScalarCallbackContract? scalar = _semantic,
  PropertyType scalarType = PropertyType.scalarCallback,
  WidgetBuilderContract? builder = _builder,
}) =>
    Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-10-24T00:00:00Z',
      libraries: {WidgetLibrary.core: const LibraryInfo(version: '1.0.0')},
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Indexed',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: '',
          flutterType: 'package:example/indexed.dart#Indexed',
          childrenSlot: ChildrenSlot.none,
          properties: [
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'findChildIndexCallback',
              type: PropertyType.scalarCallback,
              description: '',
              scalarContract: _key,
            ),
          ],
        ),
      ],
      structuredTypes: [
        StructuredEntry(
          wireId: WireId('s0001'),
          name: 'Delegate',
          library: WidgetLibrary.core,
          description: '',
          sourceType: 'package:example/delegate.dart#Delegate',
          fields: [
            StructuredField(
              wireId: WireId('p0002'),
              name: 'builder',
              type: PropertyType.widgetBuilder,
              description: '',
              builderContract: builder,
            ),
            StructuredField(
              wireId: WireId('p0003'),
              name: 'semanticIndexCallback',
              type: scalarType,
              description: '',
              scalarContract: scalar,
            ),
          ],
          variants: const [],
        ),
      ],
    );

void main() {
  test('widget and scalar signatures round trip on structured fields', () {
    final decoded = decodeCatalog(encodeCatalog(_catalog()));
    expect(decoded.widgets.single.properties.single.scalarContract, _key);
    final fields = decoded.structuredTypes.single.fields;
    expect(fields.first.builderContract, _builder);
    expect(fields.last.scalarContract, _semantic);
    expect(
      fields.last.scalarContract!.parameters.first,
      ScalarCallbackParameter.widget,
    );
  });

  test('missing, mismatched and malformed structured contracts refuse', () {
    for (final catalog in [
      _catalog(scalar: null),
      _catalog(builder: null),
      _catalog(scalarType: PropertyType.integer),
      _catalog(
        scalar: const ScalarCallbackContract(
          parameters: [
            ScalarCallbackParameter.itemIndex,
            ScalarCallbackParameter.widget,
          ],
        ),
      ),
    ]) {
      expect(
        () => encodeCatalog(catalog),
        throwsA(isA<CatalogSchemaException>()),
      );
    }
    for (final json in [
      {
        'parameters': ['widget', 'hostObject'],
        'nullableResult': true,
      },
      {
        'parameters': ['valueKey'],
        'nullableResult': 'yes',
      },
    ]) {
      expect(
        () => scalarCallbackContractFromJson(json, 'callback'),
        throwsA(isA<CatalogSchemaException>()),
      );
    }
  });

  test('wire decoder refuses callback contracts on unrelated fields', () {
    final json = jsonDecode(encodeCatalog(_catalog())) as Map<String, dynamic>;
    final structured = (json['structuredTypes'] as List<dynamic>).single
        as Map<String, dynamic>;
    final fields = structured['fields'] as List<dynamic>;
    (fields.last as Map<String, dynamic>)['type'] = 'integer';
    expect(
      () => decodeCatalog(jsonEncode(json)),
      throwsA(isA<CatalogSchemaException>()),
    );
  });

  test('nonnullable integer result is a distinct valid scalar contract', () {
    const integer = ScalarCallbackContract(
      parameters: [ScalarCallbackParameter.valueKey],
      nullableResult: false,
    );
    expect(integer, isNot(_key));
    expect(
      scalarCallbackContractFromJson(
        scalarCallbackContractToJson(integer),
        'callback',
      ),
      integer,
    );
  });
}
