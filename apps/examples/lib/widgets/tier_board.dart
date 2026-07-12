import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A single feature line within a [Tier].
class Feature {
  /// Creates a feature.
  const Feature({required this.label});

  /// The feature's display label.
  final String label;
}

/// A pricing tier: a name plus a list of the features it includes — a customer
/// data class that itself carries a `List<Feature>`, so a `List<Tier>` is a
/// two-level nested list of objects.
class Tier {
  /// Creates a tier.
  const Tier({required this.name, required this.features});

  /// The tier's display name.
  final String name;

  /// The features this tier includes (a nested list of data classes).
  final List<Feature> features;
}

/// A tier board that renders a list of [Tier]s, each with its own list of
/// [Feature]s — the example app's demonstration of a **nested** list-of-objects
/// (a `List<Tier>` whose item carries a `List<Feature>`), plus an optional
/// (nullable) bonus list.
@RestageWidget(
  name: 'TierBoard',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'Renders a list of pricing tiers, each with a nested feature '
      'list.',
)
class TierBoard extends StatelessWidget {
  /// Const constructor.
  const TierBoard({super.key, required this.tiers, this.bonusTiers});

  /// The tiers to render, in order (a required list of data classes, each
  /// carrying its own nested feature list).
  @RestageProperty(description: 'The tiers to render.', required: true)
  final List<Tier> tiers;

  /// Optional bonus tiers — a nullable list (absent on the wire → null, never a
  /// silently-empty list).
  @RestageProperty(description: 'Optional bonus tiers.')
  final List<Tier>? bonusTiers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tier in [...tiers, ...?bonusTiers])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tier.name, style: theme.textTheme.titleMedium),
                for (final feature in tier.features)
                  Text('• ${feature.label}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}
