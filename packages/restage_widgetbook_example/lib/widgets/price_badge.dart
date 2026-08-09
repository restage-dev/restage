import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show LiteralDefault;

/// A compact price pill — a formatted price followed by a billing period,
/// e.g. "\$9.99 / mo".
@RestageWidget(
  name: 'PriceBadge',
  library: WidgetLibrary.custom('restage_widgetbook_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'A compact price pill, e.g. "\$9.99 / mo".',
)
class PriceBadge extends StatelessWidget {
  /// Const constructor — catalog widgets are const-constructible.
  const PriceBadge({super.key, required this.price, required this.period});

  /// Formatted price, e.g. `"\$9.99"`.
  @RestageProperty(
    description: 'Formatted price, e.g. "\$9.99".',
    required: true,
    defaultSource: LiteralDefault(r'$9.99'),
  )
  final String price;

  /// Billing period suffix, e.g. `"mo"`.
  @RestageProperty(
    description: 'Billing period suffix, e.g. "mo".',
    required: true,
    defaultSource: LiteralDefault('mo'),
  )
  final String period;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            price,
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '/ $period',
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
