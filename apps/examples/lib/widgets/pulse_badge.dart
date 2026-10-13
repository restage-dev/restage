import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// Custom-defined badge whose scale pulses, driven by an [AnimationController].
///
/// An animation controller is code, so this widget can't be inlined into a
/// delivered surface. A surface refers to it by name, and the SDK renders it
/// through the factory that `registerRestageWidgets()` registers. Compare
/// [StatBadge], which the build inlines.
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
  // The controller is why this widget renders from app code.
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
