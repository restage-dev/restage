import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A lesson comparison panel with three independently named child-bearing
/// inputs. None uses a canonical `child` or `children` name.
@RestageWidget(
  name: 'ComparisonPanel',
  library: WidgetLibrary.custom('acme.lessons'),
  category: WidgetCategory.decoration,
  description: 'A headed panel with an introduction, examples, and conclusion.',
)
class ComparisonPanel extends StatelessWidget {
  /// Creates a panel titled [heading] around its composed lesson content.
  const ComparisonPanel({
    required this.heading,
    this.introduction,
    required this.examples,
    this.conclusion,
    super.key,
  });

  /// The panel heading.
  @RestageProperty(description: 'The panel heading.')
  final String heading;

  /// Optional content shown before the examples.
  @RestageProperty(description: 'Content shown before the lesson examples.')
  final Widget? introduction;

  /// The lesson examples shown in source order.
  @RestageProperty(description: 'The lesson example widgets.')
  final List<Widget> examples;

  /// Optional content shown after the examples.
  @RestageProperty(description: 'Content shown after the lesson examples.')
  final Widget? conclusion;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('comparison-panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: const TextStyle(fontSize: 18)),
        ?introduction,
        ...examples,
        ?conclusion,
      ],
    );
  }
}
