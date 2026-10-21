import 'package:flutter/material.dart' show AppBar, kToolbarHeight;
import 'package:flutter/widgets.dart';

/// The Material toolbar height, used when the slot's content declares no
/// height of its own.
const double kRestagePreferredSlotHeight = kToolbarHeight;

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
  }) : _preferredSize = null;

  /// Preserves native AppBar sizing, including the themed toolbar default.
  ///
  /// Scaffold recognizes the size returned by AppBar and, when [toolbarHeight]
  /// is null, applies its theme's toolbar height before adding [bottomHeight].
  RestagePreferredSizeSlot.appBar({
    double? toolbarHeight,
    required double bottomHeight,
    super.key,
    required this.child,
  })  : preferredHeight = (toolbarHeight ?? kToolbarHeight) + bottomHeight,
        _preferredSize = AppBar(
          toolbarHeight: toolbarHeight,
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(bottomHeight),
            child: const SizedBox.shrink(),
          ),
        ).preferredSize;

  /// The height reported to the consuming widget.
  final double preferredHeight;

  final Size? _preferredSize;

  /// The widget rendered in the slot.
  final Widget child;

  @override
  Size get preferredSize => _preferredSize ?? Size.fromHeight(preferredHeight);

  @override
  Widget build(BuildContext context) => child;
}
