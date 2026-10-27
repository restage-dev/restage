import 'dart:convert';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const _layout = WidgetBuilderContract(
  parameters: [
    WidgetBuilderParameter.buildContext,
    WidgetBuilderParameter.boxConstraints,
  ],
);

Catalog _catalog({
  PropertyType type = PropertyType.widgetBuilder,
  WidgetBuilderContract? contract = _layout,
  String? callbackSignature,
}) =>
    Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-10-24T00:00:00Z',
      libraries: {WidgetLibrary.core: const LibraryInfo(version: '1.0.0')},
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'LayoutBuilder',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: 'Builds with local constraints.',
          flutterType:
              'package:flutter/src/widgets/layout_builder.dart#LayoutBuilder',
          childrenSlot: ChildrenSlot.none,
          properties: [
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'builder',
              type: type,
              description: 'Deferred child.',
              builderContract: contract,
              callbackSignature: callbackSignature,
            ),
          ],
        ),
      ],
    );

void main() {
  test('native context and inert parameters round trip structurally', () {
    final decoded = decodeCatalog(encodeCatalog(_catalog()));
    final property = decoded.widgets.single.properties.single;
    expect(property.type, PropertyType.widgetBuilder);
    expect(property.builderContract, _layout);
    expect(
      property.builderContract!.parameters.first,
      WidgetBuilderParameter.buildContext,
    );
    expect(property.callbackSignature, isNull);
    final encoded =
        jsonDecode(encodeCatalog(_catalog())) as Map<String, dynamic>;
    final widget =
        (encoded['widgets'] as List<dynamic>).single as Map<String, dynamic>;
    final propertyJson =
        (widget['properties'] as List<dynamic>).single as Map<String, dynamic>;
    expect(
      propertyJson['builderContract'],
      {
        'parameters': ['buildContext', 'boxConstraints'],
        'nullableResult': false,
      },
    );
  });

  test('nullable indexed result remains distinct from callback optionality',
      () {
    const contract = WidgetBuilderContract(
      parameters: [
        WidgetBuilderParameter.buildContext,
        WidgetBuilderParameter.itemIndex,
      ],
      nullableResult: true,
    );
    final property = decodeCatalog(encodeCatalog(_catalog(contract: contract)))
        .widgets
        .single
        .properties
        .single;
    expect(property.builderContract, contract);
    expect(property.constructorNullable, isFalse);
  });

  test('builder/event contract mismatch and missing signature fail closed', () {
    for (final catalog in [
      _catalog(contract: null),
      _catalog(type: PropertyType.event),
      _catalog(callbackSignature: 'ValueChanged<int>'),
      _catalog(
        contract: const WidgetBuilderContract(
          parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.boxConstraints,
          ],
          nullableResult: true,
        ),
      ),
      _catalog(
        contract: const WidgetBuilderContract(
          parameters: [
            WidgetBuilderParameter.boxConstraints,
            WidgetBuilderParameter.buildContext,
          ],
        ),
      ),
    ]) {
      expect(
        () => encodeCatalog(catalog),
        throwsA(isA<CatalogSchemaException>()),
      );
    }
  });

  test('malformed wire parameter kinds and nullability refuse', () {
    for (final json in [
      {
        'parameters': ['buildContext', 'hostObject'],
        'nullableResult': false,
      },
      {
        'parameters': ['buildContext'],
        'nullableResult': 'yes',
      },
      {
        'parameters': ['buildContext', 'buildContext'],
        'nullableResult': false,
      },
    ]) {
      expect(
        () => widgetBuilderContractFromJson(json, 'builderContract'),
        throwsA(isA<CatalogSchemaException>()),
      );
    }
  });
}
