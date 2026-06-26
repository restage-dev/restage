import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A money value — a nested data class inside [Product]. Demonstrates that a
/// `@RestageWidget` property typed as a customer data class auto-generates a
/// rich A2UI schema (no shim types, no hand-authored schema).
class Money {
  /// Creates a money value.
  const Money({required this.amount, required this.currency});

  /// The numeric amount.
  final double amount;

  /// The ISO currency code (e.g. `'USD'`).
  final String currency;
}

/// One product feature — a data class held in a list-of-objects on [Product].
class Feature {
  /// Creates a feature row.
  const Feature({required this.label, required this.included});

  /// The feature label.
  final String label;

  /// Whether this plan includes the feature.
  final bool included;
}

/// A product — a customer data class exercising the rich A2UI data vocabulary
/// as nested fields: a nested data class ([price]), a scalar list ([tags]), a
/// list-of-objects ([features]), a String-keyed map ([attributes]), and a
/// named record ([size]). All reconstruct directly from the wire map.
class Product {
  /// Creates a product.
  const Product({
    required this.name,
    required this.price,
    required this.tags,
    required this.features,
    required this.attributes,
    required this.size,
  });

  /// The product name.
  final String name;

  /// The price — a nested data class.
  final Money price;

  /// Marketing tags — a scalar list.
  final List<String> tags;

  /// Feature rows — a list of objects.
  final List<Feature> features;

  /// Arbitrary attributes — a String-keyed map.
  final Map<String, String> attributes;

  /// The display size — a named record.
  final ({double width, double height}) size;
}

/// A card that renders a structured [Product]. The whole rich value arrives as
/// one `@RestageProperty`; the generated A2UI catalog carries a schema rich
/// enough to reconstruct it (nested object + scalar list + list-of-objects +
/// map + record) and render it.
@RestageWidget(
  name: 'ProductCard',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.decoration,
  description:
      'Renders a structured product (nested price, tags, features, '
      'attributes, size).',
)
class ProductCard extends StatelessWidget {
  /// Creates a card rendering [product].
  const ProductCard({required this.product, super.key});

  /// The structured product to render — a nested data class. The constructor
  /// requires it, so the generated A2UI catalog marks it required automatically
  /// — no redundant `required: true` on the annotation.
  @RestageProperty(description: 'The product to display.')
  final Product product;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: product.size.width,
      child: Column(
        key: const ValueKey('product-card'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(product.name, style: const TextStyle(fontSize: 20)),
          Text('${product.price.amount} ${product.price.currency}'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final tag in product.tags)
                Padding(padding: const EdgeInsets.all(2), child: Text('#$tag')),
            ],
          ),
          for (final feature in product.features)
            Text('${feature.included ? '✓' : '✗'} ${feature.label}'),
          for (final entry in product.attributes.entries)
            Text('${entry.key}: ${entry.value}'),
        ],
      ),
    );
  }
}
