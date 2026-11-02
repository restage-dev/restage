import 'dart:convert';
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_a2ui_example/generated/restage_a2ui_catalog.g.dart';
import 'a2ui_proof_support.dart';

Map<String, Object?> _objectAt(Map<String, Object?> object, String key) =>
    (object[key]! as Map).cast<String, Object?>();
void _expectDescription(Map<String, Object?> object, String description) =>
    expect(object['description'], description);
void main() {
  test(
    'producer receives standard v1 catalog JSON and authored instructions',
    () {
      final document = readStamp()['a2uiCatalog']! as Map;
      expect(document['catalogId'], restageA2uiCatalogId);
      expect(document['protocolVersion'], '1.0');
      expect(document['instructions'], buildRestageCatalog().instructions);
      expect(document['instructions'], isNotEmpty);
      expect(jsonEncode(document), contains('ProductCard'));
      expect(document.containsKey('systemPromptFragments'), isFalse);
    },
  );
  test(
    'strict processor selects exact catalog and rejects invalid title before update',
    () {
      final processor = MessageProcessor<ComponentImplementation>(
        catalogs: [buildRestageCatalog()],
        defaultVersion: A2uiProtocolVersion.v1_0,
        validationConfig: ValidationConfig.strict,
      );
      addTearDown(processor.dispose);
      expect(
        () => processor.processMessages({
          'version': 'v1.0',
          'createSurface': {
            'surfaceId': 'wrong',
            'catalogId': '$restageA2uiCatalogId-wrong',
          },
        }),
        throwsA(isA<A2uiError>()),
      );
      processor.processMessages({
        'version': 'v1.0',
        'createSurface': {'surfaceId': 's', 'catalogId': restageA2uiCatalogId},
      });
      expect(
        processor.model.getSurface('s')!.defaultCatalog!.id,
        restageA2uiCatalogId,
      );
      for (final props in [
        <String, Object?>{},
        {'props_title': null},
        {'props_title': 42},
      ]) {
        expect(
          () => processor.processMessages({
            'version': 'v1.0',
            'updateComponents': {
              'surfaceId': 's',
              'components': [
                {'id': 'root', 'component': 'SectionHeader', ...props},
              ],
            },
          }),
          throwsA(isA<A2uiValidationError>()),
        );
        expect(processor.model.getSurface('s')!.componentsModel.keys, isEmpty);
      }
    },
  );
  test('ProductCard preserves nested documentation in both schema views', () {
    final catalog = buildRestageCatalog();
    final schema =
        catalog.definitions['restage_component_ProductCard']!
            as Map<String, Object?>;
    final definitions = _objectAt(schema, r'$defs');
    final root = _objectAt(definitions, '__a2ui_root__');
    final rootProperties = _objectAt(root, 'properties');
    final productOccurrence = _objectAt(rootProperties, 'props_product');
    final product = _objectAt(definitions, 'Product');
    final productProperties = _objectAt(product, 'properties');
    final money = _objectAt(definitions, 'Money');
    final moneyProperties = _objectAt(money, 'properties');
    final features = _objectAt(productProperties, 'features');
    final feature = _objectAt(features, 'items');
    final featureProperties = _objectAt(feature, 'properties');

    _expectDescription(
      root,
      'Renders a structured product (nested price, tags, features, '
      'attributes, size).',
    );
    _expectDescription(productOccurrence, 'The product to display.');
    _expectDescription(
      product,
      'A product with pricing, feature, attribute, and display metadata.',
    );
    _expectDescription(
      _objectAt(productProperties, 'name'),
      'The user-facing product name.',
    );
    _expectDescription(
      _objectAt(productProperties, 'price'),
      'The price — a nested data class.',
    );
    _expectDescription(money, 'A monetary amount in a specific currency.');
    _expectDescription(
      _objectAt(moneyProperties, 'amount'),
      'The numeric amount.',
    );
    _expectDescription(
      _objectAt(moneyProperties, 'currency'),
      "The ISO currency code (e.g. `'USD'`).",
    );
    _expectDescription(
      _objectAt(productProperties, 'tags'),
      'Marketing tags — a scalar list.',
    );
    _expectDescription(features, 'Feature rows — a list of objects.');
    _expectDescription(
      feature,
      'One feature included in or excluded from a product.',
    );
    _expectDescription(
      _objectAt(featureProperties, 'label'),
      'The feature label.',
    );
    _expectDescription(
      _objectAt(featureProperties, 'included'),
      'Whether this plan includes the feature.',
    );
    _expectDescription(
      _objectAt(productProperties, 'attributes'),
      'Arbitrary attributes — a String-keyed map.',
    );
    final size = _objectAt(productProperties, 'size');
    _expectDescription(size, 'The display size — a named record.');
    final sizeProperties = _objectAt(size, 'properties');
    expect(
      sizeProperties.values.cast<Map<Object?, Object?>>().every(
        (field) => !field.containsKey('description'),
      ),
      isTrue,
      reason: 'record labels must not invent documentation',
    );

    final encoded = jsonEncode(schema);
    for (final description in const [
      'The user-facing product name.',
      'A product with pricing, feature, attribute, and display metadata.',
      'A monetary amount in a specific currency.',
      'One feature included in or excluded from a product.',
    ]) {
      expect(description.allMatches(encoded), hasLength(1));
    }
    expect(encoded, isNot(contains('The internal product name.')));
  });
}
