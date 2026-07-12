import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/widgets/pricing_card.dart' show Plan;

/// A customer-defined pricing table that renders a *list* of [Plan] data-class
/// values — the example app's demonstration of a customer **list-of-objects**
/// property rendering natively as real Flutter widgets from a server-delivered
/// blob.
///
/// Each [Plan] in [plans] is the same nested data class [PricingCard] renders
/// singly; here the whole list is decoded from the wire (a list of field-name-
/// keyed maps) and reconstructed element by element by the generated factory,
/// in order, with no hand-written plumbing.
@RestageWidget(
  name: 'PricingTable',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'Renders a list of subscription plans (a list-of-data-class '
      'property).',
)
class PricingTable extends StatelessWidget {
  /// Const constructor.
  const PricingTable({super.key, required this.plans});

  /// The plans to render, in order (a customer list-of-data-class property).
  @RestageProperty(
    description: 'The plans to render, in order.',
    required: true,
  )
  final List<Plan> plans;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final plan in plans)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${plan.name} — ${plan.price.currency} '
              '${(plan.price.amount / 100).toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium,
            ),
          ),
      ],
    );
  }
}
