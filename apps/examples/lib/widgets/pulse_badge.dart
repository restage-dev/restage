import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// Customer-defined badge whose scale pulses, driven by an [AnimationController].
///
/// Its animation is driven imperatively by an [AnimationController] created in a
/// `State` field and torn down in [State.dispose] — machinery a declarative blob
/// can never author (a controller is executable behaviour, not inert data). So
/// PulseBadge is a *categorical* ("dead-end") non-inlinable 4b custom widget: no
/// transpiler increment can fold it into a delivered blob, ever. A surface
/// references it by name and the SDK resolves it through the registered runtime
/// factory (`registerRestageCustomerWidgets()`).
///
/// Contrast [StreakBadge], whose 4b-ness rests only on a not-yet-lowered value
/// computation (a `reducible` deferral) — and [StatBadge], whose pure
/// composition inlines into the blob.
@RestageWidget(
  name: 'PulseBadge',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'A badge that pulses, driven by an AnimationController.',
)
class PulseBadge extends StatefulWidget {
  /// Const constructor — custom widgets must be const-constructible.
  const PulseBadge({super.key, required this.label, required this.count});

  /// The caption, e.g. `'Streak'`.
  @RestageProperty(description: 'Caption text.', required: true)
  final String label;

  /// The count shown after the caption.
  @RestageProperty(
      description: 'Count shown after the caption.', required: true)
  final int count;

  @override
  State<PulseBadge> createState() => _PulseBadgeState();
}

class _PulseBadgeState extends State<PulseBadge>
    with SingleTickerProviderStateMixin {
  // An imperative AnimationController — this is what makes PulseBadge a
  // categorical 4b: it cannot be expressed as inert, declarative blob data.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  @override
  void initState() {
    super.initState();
    // A one-shot imperative scale entrance, driven by the controller.
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ScaleTransition(
      scale: Tween<double>(begin: 0.92, end: 1).animate(_controller),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '${widget.label}: ${widget.count}',
          style: TextStyle(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
