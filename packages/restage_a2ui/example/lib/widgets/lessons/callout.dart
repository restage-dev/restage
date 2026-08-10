import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A lesson callout: a [message] plus optional wrapped [detail] content.
/// The arbitrary child-bearing name is preserved exactly. The input is
/// nullable, so an unresolved A2UI component-id reference remains optional.
@a2ui.Config.usage('Use for a short highlighted aside around optional content.')
@RestageWidget(
  name: 'Callout',
  library: WidgetLibrary.custom('acme.lessons'),
  category: WidgetCategory.decoration,
  description: 'A message callout that wraps an optional child.',
)
class Callout extends StatelessWidget {
  /// Creates a callout showing [message] above [detail].
  const Callout({required this.message, this.detail, super.key});

  /// The callout message.
  @RestageProperty(description: 'The callout message.')
  final String message;

  /// The optional wrapped detail content.
  @RestageProperty(description: 'The wrapped detail content.')
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('callout'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(message), ?detail],
    );
  }
}
