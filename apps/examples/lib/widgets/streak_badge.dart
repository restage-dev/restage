import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// Custom-defined pill showing a streak count, whose fill deepens with the
/// count.
///
/// Its `build` computes the fill alpha at runtime (`clamp` and `withValues`),
/// so the build can't inline it. A paywall refers to it by name, and the SDK
/// renders it through the factory that `registerRestageWidgets()` registers.
@RestageWidget(
  name: 'StreakBadge',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'A pill showing a streak count, its fill deepening with it.',
)
class StreakBadge extends StatelessWidget {
  /// Const constructor — custom widgets must be const-constructible.
  const StreakBadge({super.key, required this.label, required this.count});

  /// The caption, e.g. `'Streak'`.
  @RestageProperty(description: 'Caption text.', required: true)
  final String label;

  /// The streak count.
  @RestageProperty(description: 'Streak count.', required: true)
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A runtime computation, so this widget renders from app code.
    final intensity = count.clamp(0, 10) / 10.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: intensity),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
