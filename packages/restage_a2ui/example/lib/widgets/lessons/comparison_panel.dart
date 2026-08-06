import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A lesson comparison panel: a [heading] plus a [children] slot (a list of
/// nested widgets). Exercises the canonical `children` widget-list slot.
@RestageA2uiExample(
  name: 'Child collection',
  asset: 'lib/a2ui_examples/comparison_panel/child_collection.json',
)
@RestageWidget(
  name: 'ComparisonPanel',
  library: WidgetLibrary.custom('acme.lessons'),
  category: WidgetCategory.decoration,
  description: 'A headed panel that lays out a list of child widgets.',
)
class ComparisonPanel extends StatelessWidget {
  /// Creates a panel titled [heading] over [children].
  const ComparisonPanel({
    required this.heading,
    required this.children,
    super.key,
  });

  /// The panel heading.
  @RestageProperty(description: 'The panel heading.')
  final String heading;

  /// The child widgets — the canonical children slot.
  @RestageProperty(description: 'The compared child widgets.')
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('comparison-panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: const TextStyle(fontSize: 18)),
        ...children,
      ],
    );
  }
}
