import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// Customer-defined fixture that overlays a list of children. Exercises a
/// customer `List<Widget>` property through the generated factory pipeline.
@RestageWidget(
  name: 'AcmeStack',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.layout,
  description: 'Overlays a list of children in z-order.',
)
class AcmeStack extends StatelessWidget {
  /// Const constructor.
  const AcmeStack({super.key, required this.children});

  /// Overlay children discovered from this exact constructor property.
  @RestageProperty(description: 'Overlay children, top-most last.')
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(children: children);
}
