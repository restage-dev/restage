import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// Customer-defined pill-shaped label highlighting a promotion inside a
/// paywall.
@RestageWidget(
  name: 'PromoBadge',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.action,
  description: 'Pill-shaped promotional label.',
)
class PromoBadge extends StatelessWidget {
  /// Const constructor.
  const PromoBadge({super.key, required this.label, this.color});

  /// Visible label, e.g. `'2 weeks free'`.
  @RestageProperty(description: 'Visible label.', required: true)
  final String label;

  /// Background color. Defaults to the theme's primary container.
  @RestageProperty(
    description: 'Background color. Defaults to the primary container.',
    defaultBrandToken: 'primary',
  )
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
