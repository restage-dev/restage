import 'package:flutter/widgets.dart';

/// Binds a child widget tree to a configured product slot.
///
/// At runtime, [slot] is resolved against the host app's product
/// configuration; matched product information (price, display name,
/// trial details) is exposed to descendants of [child] via the
/// standard product-resolution helpers. Use [Package] to wrap any UI
/// region that should react to the product associated with a given
/// slot identifier — typically a tier card's price label and
/// call-to-action button.
///
/// [Package] returns its [child] verbatim; the slot binding is
/// enforced by the build-time transpiler and consumed by the
/// runtime's product layer.
class Package extends StatelessWidget {
  /// Const constructor.
  const Package({super.key, required this.slot, required this.child});

  /// Identifier matched against the host app's product configuration
  /// (for example `'primary'`, `'secondary'`, `'tertiary'`).
  final String slot;

  /// UI bound to the resolved product. Descendants may read price and
  /// metadata via the standard product-resolution helpers.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
