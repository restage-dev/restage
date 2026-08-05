import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/widgets/pricing_card.dart' show Plan, PlanTier;

/// A customer-defined plan board that renders *maps* of [Plan] data-class
/// values — the example app's demonstration of a customer **map-of-objects**
/// property rendering natively as real Flutter widgets from a server-delivered
/// blob.
///
/// This is the map counterpart of the pricing table: the same nested [Plan]
/// data class, reached through a keyed container instead of an ordered one.
/// Each map
/// travels the wire as a **list of entry objects**, one `key`/`value` pair per
/// entry, so both the membership and the author's ordering survive — a keyed
/// container is not otherwise enumerable by the primitives the render substrate
/// provides. The generated factory reconstructs each entry and accumulates it,
/// with no hand-written plumbing.
///
/// [plans] is keyed by a plain string. [highlights] is keyed by the [PlanTier]
/// **enum**, which takes the identical entry list with each key carrying the
/// constant's name. An enum key is read strictly: a key that names no declared
/// constant fails the whole property rather than falling back to a default,
/// because a defaulted key would silently move the author's entry to a key they
/// never sent.
@RestageWidget(
  name: 'PlanBoard',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'Renders plans keyed by slug plus a highlighted plan per '
      'billing tier (map-of-data-class properties).',
)
class PlanBoard extends StatelessWidget {
  /// Const constructor.
  const PlanBoard({
    super.key,
    required this.plans,
    required this.highlights,
  });

  /// The plans to render, keyed by slug, in the author's order (a customer
  /// map-of-data-class property with a string key).
  @RestageProperty(
    description: 'The plans to render, keyed by slug.',
    required: true,
  )
  final Map<String, Plan> plans;

  /// The highlighted plan for each billing tier (a customer map-of-data-class
  /// property with an *enum* key).
  @RestageProperty(
    description: 'The highlighted plan for each billing tier.',
    required: true,
  )
  final Map<PlanTier, Plan> highlights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    String priceOf(Plan plan) => '${plan.price.currency} '
        '${(plan.price.amount / 100).toStringAsFixed(2)}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in plans.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${entry.key} — ${entry.value.name}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    priceOf(entry.value),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          for (final entry in highlights.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Best in ${entry.key.name}: ${entry.value.name}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
