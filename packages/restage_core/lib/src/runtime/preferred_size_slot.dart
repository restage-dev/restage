import 'package:flutter/widgets.dart';

/// The Material toolbar height, used when the slot's content declares no
/// height of its own. Duplicated as a literal so this library stays free
/// of the Material import.
const double kRestagePreferredSlotHeight = 56;

/// Presents a rendered slot value in a `PreferredSizeWidget` argument.
///
/// A slot's content is built by the runtime and never implements the
/// interface itself, so the wrapper carries the preferred height the
/// consuming widget lays the slot out at.
class RestagePreferredSizeSlot extends StatelessWidget
    implements PreferredSizeWidget {
  /// Wraps [child] so it can fill a `PreferredSizeWidget` argument.
  const RestagePreferredSizeSlot({
    this.preferredHeight = kRestagePreferredSlotHeight,
    super.key,
    required this.child,
  });

  /// The height reported to the consuming widget.
  final double preferredHeight;

  /// The widget rendered in the slot.
  final Widget child;

  @override
  Size get preferredSize => Size.fromHeight(preferredHeight);

  @override
  Widget build(BuildContext context) => child;
}
