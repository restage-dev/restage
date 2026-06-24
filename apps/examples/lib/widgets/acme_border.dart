import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// Customer-defined fixture that wraps any child in a colored border.
/// Exercises `childrenSlot: ChildrenSlot.single` end-to-end through the
/// generated factory pipeline.
@RestageWidget(
  name: 'AcmeBorder',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.layout,
  description: 'Wraps a single child in a colored border.',
  childrenSlot: ChildrenSlot.single,
)
class AcmeBorder extends StatelessWidget {
  /// Const constructor.
  const AcmeBorder({super.key, required this.child, this.color});

  /// Wrapped child. Single canonical child slot.
  @RestageProperty(description: 'Wrapped child widget.', required: true)
  final Widget child;

  /// Border color. Defaults to the theme's primary container.
  @RestageProperty(
    description: 'Border color. Defaults to the primary container.',
    defaultBrandToken: 'primary',
  )
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: color ?? scheme.primary, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
