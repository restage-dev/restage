import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// Customer-defined fixture that overlays a list of children. Exercises
/// `childrenSlot: ChildrenSlot.list` end-to-end through the generated
/// factory pipeline.
@RestageWidget(
  name: 'AcmeStack',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.layout,
  description: 'Overlays a list of children in z-order.',
  childrenSlot: ChildrenSlot.list,
)
class AcmeStack extends StatelessWidget {
  /// Const constructor.
  const AcmeStack({super.key, required this.children});

  /// Overlay children. Canonical children slot.
  @RestageProperty(description: 'Overlay children, top-most last.')
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(children: children);
}
