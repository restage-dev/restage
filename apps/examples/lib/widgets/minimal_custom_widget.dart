import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A minimal custom widget: your own Flutter widget, added to the catalog with
/// `@RestageWidget` so a delivered surface can use it.
///
/// Its `build` only composes catalog widgets and theme reads, so the build
/// inlines it into each surface that uses it. `starter_stats.dart` shows it in
/// a surface. A widget that needs runtime computation, such as
/// `Color.withValues(...)`, is registered by `registerRestageWidgets()` and
/// renders from your app's code.
@RestageWidget(
  name: 'StatBadge',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'A labelled value pill, e.g. "Streak · 7 days".',
)
class StatBadge extends StatelessWidget {
  /// The unnamed public generative catalog constructor.
  const StatBadge({super.key, required this.label, required this.value});

  /// The caption, e.g. `'Streak'`.
  final String label;

  /// The value, e.g. `'7 days'`.
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: scheme.onSecondaryContainer,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: scheme.primary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
