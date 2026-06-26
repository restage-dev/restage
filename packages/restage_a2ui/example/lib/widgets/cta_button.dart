import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A call-to-action button — a [label] plus a [onPressed] `VoidCallback` that
/// dispatches an outward action (no value to write back). The A2UI catalog
/// lowers the callback to an event the surface can handle.
@RestageWidget(
  name: 'CtaButton',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.action,
  description: 'A call-to-action button that dispatches a tap event.',
  fires: [WidgetEventName.onPressed],
)
class CtaButton extends StatelessWidget {
  /// Creates a button showing [label] and dispatching [onPressed] when tapped.
  const CtaButton({required this.label, required this.onPressed, super.key});

  /// The button's caption.
  @RestageProperty(description: 'The button caption.')
  final String label;

  /// Fired when the button is tapped — the dispatch callback.
  @RestageProperty(description: 'Dispatches the button tap.')
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('cta-button'),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        color: const Color(0xFF2D6CDF),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16),
        ),
      ),
    );
  }
}
