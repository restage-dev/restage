import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A lesson section header: a [title] scalar. A pure leaf widget, so it can sit
/// inside another lesson widget's child slot.
@RestageWidget(
  name: 'SectionHeader',
  library: WidgetLibrary.custom('acme.lessons'),
  category: WidgetCategory.decoration,
  description: 'A titled section header.',
)
class SectionHeader extends StatelessWidget {
  /// Creates a header showing [title].
  const SectionHeader({required this.title, super.key});

  /// The header text.
  @RestageProperty(description: 'The header title.')
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      key: const ValueKey('section-header'),
      style: const TextStyle(fontSize: 22),
    );
  }
}
