import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// Customer-defined pill showing a streak count, whose fill deepens with the
/// count.
///
/// Its `build` derives the fill alpha with a runtime computation (`clamp` +
/// `withValues`), which the codegen cannot fold into a delivered blob — so
/// StreakBadge is a non-inlinable ("4b") custom widget: a paywall references it
/// by name and the SDK resolves it through the registered runtime factory
/// (`registerRestageCustomerWidgets()`), rather than inlining its composition.
/// Contrast `StatBadge`, whose pure-composition `build` inlines into the blob.
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
    // Runtime-derived alpha — a computation, not blob-expressible, so this
    // widget renders through its registered runtime factory.
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
