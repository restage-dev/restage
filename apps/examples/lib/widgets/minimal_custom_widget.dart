import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A minimal custom widget — your own Flutter widget, lowered into the catalog
/// so a server-driven surface can render it.
///
/// The recipe is two steps:
/// 1. Annotate the widget with [RestageWidget] and each configurable field with
///    [RestageProperty].
/// 2. Run `build_runner`.
///
/// Because `StatBadge`'s `build` is pure composition (catalog primitives + theme
/// reads, no imperative Flutter calls), the codegen **inlines** it into any
/// surface that uses it — so it travels inside the delivered blob and renders as
/// real Flutter widgets, even in the generic viewer, with no runtime code. See
/// `lib/onboarding/screens/starter_stats.dart` for it rendering from a blob.
///
/// Keep a `@RestageWidget`'s `build` declarative to stay blob-expressible:
/// no `Color.withValues(...)`, no `?? fallback` on an optional property in a
/// value position, no other runtime computation. Anything irreducibly imperative
/// is registered as a runtime factory instead (`registerRestageCustomerWidgets()`
/// in `lib/user_factories.g.dart`) and rendered in the host app.
@RestageWidget(
  name: 'StatBadge',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'A labelled value pill, e.g. "Streak · 7 days".',
)
class StatBadge extends StatelessWidget {
  /// Const constructor — custom widgets must be const-constructible.
  const StatBadge({super.key, required this.label, required this.value});

  /// The caption, e.g. `'Streak'`.
  @RestageProperty(description: 'Caption text.', required: true)
  final String label;

  /// The value, e.g. `'7 days'`.
  @RestageProperty(description: 'Value text.', required: true)
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
