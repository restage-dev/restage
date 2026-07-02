import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// Declares the example widget library's capability version.
///
/// A library with a widget that renders a customer data-class property (here
/// [PricingCard], via its [Plan] property) is *structured-admitting*, so it
/// must declare a monotonic `capabilityVersion`. The delivery pipeline records
/// it as the library's floor: a hosted blob authored against a newer library
/// is rejected before render on an app built against an older one, rather than
/// mis-rendering. A library with only simple widgets needs no declaration.
@RestageLibrary(
  library: WidgetLibrary.custom('restage_example.widgets'),
  capabilityVersion: 1,
)
const restageExampleWidgetLibrary = 0;

/// The billing tier a [Plan] belongs to.
enum PlanTier {
  /// The entry tier.
  starter,

  /// The mid tier.
  pro,

  /// The top tier.
  team,
}

/// A price: an integer [amount] in the currency's minor units plus the ISO
/// currency code.
///
/// The constructor is intentionally *mixed* — [amount] is positional and
/// [currency] is named with a default — to exercise every constructor-argument
/// shape the generated reconstructor supports.
class Price {
  /// Creates a price.
  const Price(this.amount, {this.currency = 'USD'});

  /// The amount in the currency's minor units (e.g. cents).
  final int amount;

  /// The ISO-4217 currency code. Defaults to `'USD'` when the wire omits it.
  final String currency;
}

/// A subscription plan rendered inside a [PricingCard] — a customer data class
/// with a nested [Price], an optional badge, and an enum tier.
class Plan {
  /// Creates a plan.
  const Plan({
    required this.name,
    required this.price,
    this.badge,
    this.tier = PlanTier.starter,
  });

  /// The plan's display name.
  final String name;

  /// The plan's price (a nested data class — a two-level structured graph).
  final Price price;

  /// An optional highlight badge (e.g. `'Most popular'`); `null` when the wire
  /// omits it.
  final String? badge;

  /// The billing tier. Defaults to [PlanTier.starter] when the wire omits it.
  final PlanTier tier;
}

/// A customer-defined pricing card that renders a nested [Plan] data class.
///
/// This is the example app's demonstration of a customer *structured* property
/// rendering natively as real Flutter widgets from a server-delivered blob —
/// the plan is decoded from the wire and reconstructed by the generated
/// factory, no hand-written plumbing.
@RestageWidget(
  name: 'PricingCard',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'Renders a subscription plan (a nested data-class property).',
)
class PricingCard extends StatelessWidget {
  /// Const constructor.
  const PricingCard({super.key, required this.plan});

  /// The plan to render (a customer data-class property).
  @RestageProperty(description: 'The plan to render.', required: true)
  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final major = (plan.price.amount / 100).toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (plan.badge case final badge?)
            Text(
              badge,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          Text(plan.name, style: theme.textTheme.titleLarge),
          Text(
            '${plan.price.currency} $major',
            style: theme.textTheme.headlineSmall,
          ),
          Text(plan.tier.name, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
