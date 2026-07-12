import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A lesson callout: a [message] plus an optional wrapped [child] slot.
/// Exercises the canonical single-`child` slot (a customer widget nested inside
/// a customer widget) alongside a scalar. The child slot is nullable — an A2UI
/// child is a component-id reference that need not resolve, so the generated
/// catalog lowers the slot to an optional child.
@RestageWidget(
  name: 'Callout',
  library: WidgetLibrary.custom('acme.lessons'),
  category: WidgetCategory.decoration,
  description: 'A message callout that wraps an optional child.',
  usage: 'Use for a short highlighted aside around optional content.',
)
class Callout extends StatelessWidget {
  /// Creates a callout showing [message] above [child].
  const Callout({required this.message, this.child, super.key});

  /// The callout message.
  @RestageProperty(description: 'The callout message.')
  final String message;

  /// The wrapped child — the canonical single-child slot (optional).
  @RestageProperty(description: 'The wrapped child content.')
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('callout'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(message), ?child],
    );
  }
}
