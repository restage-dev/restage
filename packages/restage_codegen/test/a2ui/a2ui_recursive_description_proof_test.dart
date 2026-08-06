import 'dart:convert';

import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_definition_registry.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/a2ui/a2ui_shape_reflector.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'shape_reflector_test_support.dart';

const _recursiveDescriptionsFixture = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Canonical monetary amount.
class Money {
  const Money({required this.minorUnits, this.parent});

  final int minorUnits;
  final Money? parent;
}

class Product {
  const Product({required this.price, required this.discount});

  @RestageDataField(description: 'Checkout price.')
  final Money price;

  @RestageDataField(description: 'Promotional discount.')
  final Money discount;
}

class ProductReversed {
  const ProductReversed({required this.discount, required this.price});

  @RestageDataField(description: 'Promotional discount.')
  final Money discount;

  @RestageDataField(description: 'Checkout price.')
  final Money price;
}

class Holder {
  const Holder({required this.product, required this.reversed});

  final Product product;
  final ProductReversed reversed;
}
''';

Future<ObjectNode> _reflectProduct(String field) async {
  final type = await resolveFieldType(
    _recursiveDescriptionsFixture,
    className: 'Holder',
    fieldName: field,
  );
  final result = reflectType(type);
  expect(result, isA<A2uiShapeResolved>(), reason: 'got $result');
  return (result as A2uiShapeResolved).node as ObjectNode;
}

A2uiDartWidgetPlan _planFor(
  A2uiSchemaNode node, {
  String description = '',
}) =>
    classifyA2uiCatalogDart(
      catalogWith([
        entry(
          name: 'PriceCard',
          properties: [
            prop(
              'product',
              PropertyType.structured,
              required: true,
              description: description,
            ),
          ],
        ),
      ]),
      richShapes: {('PriceCard', 'product'): node},
    ).widgets.single;

String _widgetExpression(A2uiSchemaNode node) =>
    a2uiWidgetDataSchemaExpression([
      (
        name: 'product',
        required: true,
        emission: A2uiDataField(node, rich: true),
      ),
    ]);

void main() {
  group('recursive and repeated description projection', () {
    test('reflector keeps occurrence and canonical definition facts separate',
        () async {
      final product = await _reflectProduct('product');
      final price = product.fields['price']! as ObjectNode;
      final discount = product.fields['discount']! as ObjectNode;

      expect(price.defId, discount.defId);
      expect(price.occurrenceDescription, 'Checkout price.');
      expect(discount.occurrenceDescription, 'Promotional discount.');
      expect(price.definitionDescription, 'Canonical monetary amount.');
      expect(discount.definitionDescription, 'Canonical monetary amount.');
      expect(price, isNot(discount));

      final parent = price.fields['parent']! as RefNode;
      expect(parent.defId, price.defId);
      expect(parent.occurrenceDescription, isNull);
      expect(
        const RefNode('money', occurrenceDescription: 'First occurrence.'),
        isNot(
          const RefNode(
            'money',
            occurrenceDescription: 'Second occurrence.',
          ),
        ),
      );
    });

    test('reverse traversal has byte parity in expression and schema map',
        () async {
      final product = await _reflectProduct('product');
      final reversed = await _reflectProduct('reversed');

      final expression = _widgetExpression(product);
      final reversedExpression = _widgetExpression(reversed);
      expect(utf8.encode(reversedExpression), utf8.encode(expression));
      expect(expression, contains(r'$defs'));
      expect(expression, contains(r'$ref'));
      expect(expression, contains('Checkout price.'));
      expect(expression, contains('Promotional discount.'));
      expect(
        'Canonical monetary amount.'.allMatches(expression),
        hasLength(1),
      );

      final schema = a2uiWidgetDataSchemaMapForPlan(_planFor(product));
      final reversedSchema = a2uiWidgetDataSchemaMapForPlan(_planFor(reversed));
      expect(
        utf8.encode(jsonEncode(reversedSchema)),
        utf8.encode(jsonEncode(schema)),
      );
      expect(jsonEncode(schema), contains(r'"$defs"'));
      expect(jsonEncode(schema), contains(r'"$ref"'));
      expect(jsonEncode(schema), contains('Checkout price.'));
      expect(jsonEncode(schema), contains('Promotional discount.'));
      expect(
        'Canonical monetary amount.'.allMatches(jsonEncode(schema)),
        hasLength(1),
      );

      final catalog = catalogWith([
        entry(
          name: 'PriceCard',
          properties: [
            prop('product', PropertyType.structured, required: true),
          ],
        ),
      ]);
      final documentId = emitA2uiCatalog(
        catalog,
        richShapes: {('PriceCard', 'product'): product},
      ).documentId;
      final reversedDocumentId = emitA2uiCatalog(
        catalog,
        richShapes: {('PriceCard', 'product'): reversed},
      ).documentId;
      expect(reversedDocumentId, documentId);
    });

    test('the outer property overlay wins and emits exactly once', () async {
      final product = await _reflectProduct('product');
      final price = product.fields['price']! as ObjectNode;
      const outer = 'Outer checkout price.';

      final expression = a2uiWidgetDataSchemaExpression(
        [
          (
            name: 'product',
            required: true,
            emission: A2uiDataField(price, rich: true),
          ),
        ],
        fieldDescription: (_) => outer,
      );
      expect(outer.allMatches(expression), hasLength(1));
      expect(expression, isNot(contains('Checkout price.')));
      expect(
        'description:'.allMatches(expression),
        hasLength(2),
        reason: 'one occurrence description plus one canonical definition',
      );

      final schema = a2uiWidgetDataSchemaMapForPlan(
        _planFor(price, description: outer),
      );
      final bytes = jsonEncode(schema);
      expect(outer.allMatches(bytes), hasLength(1));
      expect(bytes, isNot(contains('Checkout price.')));
      expect('"description":'.allMatches(bytes), hasLength(2));
    });

    test('mixed documents canonicalize only the documented named subtree', () {
      const moneyId = 'package:proof/proof.dart#Money';
      const productId = 'package:proof/proof.dart#Product';
      const legacyId = 'package:proof/proof.dart#Legacy';

      ObjectNode money(String occurrence) => ObjectNode(
            defId: moneyId,
            definitionDescription: 'Canonical monetary amount.',
            occurrenceDescription: occurrence,
            fields: const {
              'amount': ScalarNode(A2uiScalarType.integer),
              'parent': RefNode(moneyId, nullable: true),
            },
            required: const {'amount'},
          );

      ObjectNode product({required bool reversed}) => ObjectNode(
            defId: productId,
            fields: reversed
                ? {
                    'discount': money('Promotional discount.'),
                    'price': money('Checkout price.'),
                  }
                : {
                    'price': money('Checkout price.'),
                    'discount': money('Promotional discount.'),
                  },
            required: const {'price', 'discount'},
          );

      final legacy = ObjectNode(
        defId: legacyId,
        fields: const {
          'zeta': ScalarNode(A2uiScalarType.string),
          'alpha': ScalarNode(A2uiScalarType.integer),
          'next': RefNode(legacyId, nullable: true),
        },
        required: const {'zeta', 'alpha'},
      );

      List<A2uiWidgetField> fields(ObjectNode documented) => [
            (
              name: 'legacy',
              required: true,
              emission: A2uiDataField(legacy, rich: true),
            ),
            (
              name: 'documented',
              required: true,
              emission: A2uiDataField(documented, rich: true),
            ),
          ];

      A2uiDartWidgetPlan plan(ObjectNode documented) => classifyA2uiCatalogDart(
            catalogWith([
              entry(
                name: 'MixedCard',
                properties: [
                  prop('legacy', PropertyType.structured, required: true),
                  prop('documented', PropertyType.structured, required: true),
                ],
              ),
            ]),
            richShapes: {
              ('MixedCard', 'legacy'): legacy,
              ('MixedCard', 'documented'): documented,
            },
          ).widgets.single;

      final forward = a2uiWidgetDataSchemaExpression(
        fields(product(reversed: false)),
      );
      final reversed = a2uiWidgetDataSchemaExpression(
        fields(product(reversed: true)),
      );
      expect(reversed, forward);
      expect(
        forward.indexOf("'legacy':"),
        lessThan(forward.indexOf("'documented':")),
      );
      final legacyDefinition = forward.substring(
        forward.indexOf("'Legacy': S.object"),
        forward.indexOf("'Money': S.object"),
      );
      expect(
        legacyDefinition.indexOf("'zeta':"),
        lessThan(legacyDefinition.indexOf("'alpha':")),
      );

      final forwardMap = a2uiWidgetDataSchemaMapForPlan(
        plan(product(reversed: false)),
      );
      final reversedMap = a2uiWidgetDataSchemaMapForPlan(
        plan(product(reversed: true)),
      );
      expect(jsonEncode(reversedMap), jsonEncode(forwardMap));
      final definitions = forwardMap[r'$defs']! as Map<String, Object?>;
      final root = definitions['__a2ui_root__']! as Map<String, Object?>;
      final rootProperties = root['properties']! as Map<String, Object?>;
      expect(rootProperties.keys, ['legacy', 'documented']);
      final legacySchema = definitions['Legacy']! as Map<String, Object?>;
      final legacyProperties =
          legacySchema['properties']! as Map<String, Object?>;
      expect(legacyProperties.keys, ['zeta', 'alpha', 'next']);
      final documentedSchema =
          rootProperties['documented']! as Map<String, Object?>;
      final documentedProperties =
          documentedSchema['properties']! as Map<String, Object?>;
      expect(documentedProperties.keys, ['discount', 'price']);
    });

    test('nested canonical member facts merge independent of candidate order',
        () {
      const invoiceId = 'package:proof/proof.dart#Invoice';
      const detailsId = 'package:proof/proof.dart#Details';

      ObjectNode candidate({
        required String rootOccurrence,
        required bool factsPresent,
      }) =>
          ObjectNode(
            defId: invoiceId,
            definitionDescription: 'Canonical invoice.',
            occurrenceDescription: rootOccurrence,
            fields: {
              'amount': ScalarNode(
                A2uiScalarType.integer,
                occurrenceDescription:
                    factsPresent ? 'Canonical amount member.' : null,
              ),
              'details': ObjectNode(
                defId: detailsId,
                definitionDescription:
                    factsPresent ? 'Canonical details type.' : null,
                occurrenceDescription:
                    factsPresent ? 'Canonical details member.' : null,
                fields: const {
                  'code': ScalarNode(A2uiScalarType.string),
                },
                required: const {'code'},
              ),
              'parent': RefNode(
                invoiceId,
                occurrenceDescription:
                    factsPresent ? 'Canonical parent member.' : null,
                nullable: true,
              ),
            },
            required: const {'amount', 'details'},
          );

      final absent = candidate(
        rootOccurrence: 'Checkout invoice.',
        factsPresent: false,
      );
      final present = candidate(
        rootOccurrence: 'Discount invoice.',
        factsPresent: true,
      );
      final forward = A2uiDefinitionRegistry([absent, present]);
      final reversed = A2uiDefinitionRegistry([present, absent]);
      final forwardDefinition = forward.definitionFor(invoiceId);
      final reversedDefinition = reversed.definitionFor(invoiceId);
      expect(reversedDefinition, forwardDefinition);

      final forwardExpression = a2uiDataSchemaExpression(forwardDefinition);
      final reversedExpression = a2uiDataSchemaExpression(reversedDefinition);
      expect(reversedExpression, forwardExpression);
      for (final description in const [
        'Canonical amount member.',
        'Canonical details member.',
        'Canonical details type.',
        'Canonical parent member.',
      ]) {
        expect(description.allMatches(forwardExpression), hasLength(1));
      }

      final forwardMap =
          a2uiWidgetDataSchemaMapForPlan(_planFor(forwardDefinition));
      final reversedMap =
          a2uiWidgetDataSchemaMapForPlan(_planFor(reversedDefinition));
      expect(jsonEncode(reversedMap), jsonEncode(forwardMap));
      final bytes = jsonEncode(forwardMap);
      for (final description in const [
        'Canonical amount member.',
        'Canonical details member.',
        'Canonical details type.',
        'Canonical parent member.',
      ]) {
        expect(description.allMatches(bytes), hasLength(1));
      }
    });

    test('nested canonical member conflicts are deterministic', () {
      const invoiceId = 'package:proof/proof.dart#Invoice';

      ObjectNode candidate(String rootOccurrence, String memberDescription) =>
          ObjectNode(
            defId: invoiceId,
            definitionDescription: 'Canonical invoice.',
            occurrenceDescription: rootOccurrence,
            fields: {
              'amount': ScalarNode(
                A2uiScalarType.integer,
                occurrenceDescription: memberDescription,
              ),
              'parent': const RefNode(invoiceId, nullable: true),
            },
            required: const {'amount'},
          );

      final first = candidate('Checkout invoice.', 'First amount member.');
      final second = candidate('Discount invoice.', 'Second amount member.');
      final expected = isA<StateError>().having(
        (error) => error.message,
        'message',
        'Conflicting canonical member description for "$invoiceId.amount".',
      );
      expect(
        () => A2uiDefinitionRegistry([first, second]),
        throwsA(expected),
      );
      expect(
        () => A2uiDefinitionRegistry([second, first]),
        throwsA(expected),
      );
    });

    test('canonical structure conflicts are deterministic', () {
      ObjectNode candidate(A2uiScalarType type) => ObjectNode(
            defId: 'package:proof/proof.dart#Money',
            definitionDescription: 'Canonical monetary amount.',
            fields: {'value': ScalarNode(type)},
            required: const {'value'},
          );

      ObjectNode root(List<ObjectNode> candidates) => ObjectNode(
            fields: {
              'price': candidates[0],
              'discount': candidates[1],
            },
            required: const {'price', 'discount'},
          );

      final expected = isA<StateError>().having(
        (error) => error.message,
        'message',
        'Conflicting canonical structure for '
            '"package:proof/proof.dart#Money".',
      );
      final first = candidate(A2uiScalarType.integer);
      final second = candidate(A2uiScalarType.string);
      expect(
        () => a2uiDataSchemaExpression(root([first, second])),
        throwsA(expected),
      );
      expect(
        () => a2uiDataSchemaExpression(root([second, first])),
        throwsA(expected),
      );
    });

    test('canonical description conflicts are deterministic', () {
      ObjectNode candidate(String description) => ObjectNode(
            defId: 'package:proof/proof.dart#Money',
            definitionDescription: description,
            fields: const {
              'value': ScalarNode(A2uiScalarType.integer),
            },
            required: const {'value'},
          );

      ObjectNode root(List<ObjectNode> candidates) => ObjectNode(
            fields: {
              'price': candidates[0],
              'discount': candidates[1],
            },
            required: const {'price', 'discount'},
          );

      final expected = isA<StateError>().having(
        (error) => error.message,
        'message',
        'Conflicting canonical description for '
            '"package:proof/proof.dart#Money".',
      );
      final first = candidate('First canonical description.');
      final second = candidate('Second canonical description.');
      expect(
        () => a2uiDataSchemaExpression(root([first, second])),
        throwsA(expected),
      );
      expect(
        () => a2uiDataSchemaExpression(root([second, first])),
        throwsA(expected),
      );
    });

    test('description-free nonrecursive schema keeps its exact expression', () {
      final node = ObjectNode(
        fields: const {'label': ScalarNode(A2uiScalarType.string)},
        required: const {'label'},
        defId: 'package:proof/proof.dart#Plain',
      );

      expect(
        a2uiDataSchemaExpression(node),
        "S.object(properties: {'label': S.string()}, "
        "required: <String>['label'],)",
      );
      expect(
        a2uiWidgetDataSchemaMapForPlan(_planFor(node)),
        {
          'type': 'object',
          'properties': {
            'product': {
              'type': 'object',
              'properties': {
                'label': {'type': 'string'},
              },
              'required': ['label'],
            },
          },
          'required': ['product'],
        },
      );
    });
  });
}
