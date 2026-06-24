import 'package:flutter/widgets.dart';

/// Multi-page surface that hosts a swipeable sequence of child widgets.
///
/// Wraps Flutter's `PageView` with a locally-owned `PageController` so
/// declarative compositions can express a paged layout without
/// participating in the host app's `Navigator`. Each entry in
/// [children] becomes one page; users swipe horizontally (or
/// vertically when [scrollDirection] is `Axis.vertical`) and
/// [onPageChanged] fires with the new page index when the page
/// settles.
///
/// The pages themselves are ordinary widgets composed locally; no
/// route transitions, no separate navigation stack.
class RestagePager extends StatefulWidget {
  /// Const constructor.
  const RestagePager({
    super.key,
    required this.children,
    this.initialPage = 0,
    this.viewportFraction = 1.0,
    this.scrollDirection = Axis.horizontal,
    this.pageSnapping = true,
    this.onPageChanged,
  })  : assert(children.length > 0, 'RestagePager.children must be non-empty.'),
        assert(
          initialPage >= 0,
          'RestagePager.initialPage must be non-negative.',
        ),
        assert(
          viewportFraction > 0 && viewportFraction <= 1,
          'RestagePager.viewportFraction must be in (0, 1].',
        );

  /// Pages displayed in order. Must be non-empty.
  final List<Widget> children;

  /// Index of the page shown when the pager first mounts. Defaults
  /// to `0`.
  final int initialPage;

  /// Fraction of the viewport occupied by each page. `1.0` (the
  /// default) shows one full page at a time; smaller values reveal
  /// adjacent pages at the edges of the viewport.
  final double viewportFraction;

  /// Direction users swipe to move between pages. Defaults to
  /// horizontal.
  final Axis scrollDirection;

  /// When `true` (the default), the pager snaps to whole-page
  /// boundaries instead of allowing partial offsets.
  final bool pageSnapping;

  /// Fires with the new page index when the visible page changes.
  final ValueChanged<int>? onPageChanged;

  @override
  State<RestagePager> createState() => _RestagePagerState();
}

class _RestagePagerState extends State<RestagePager> {
  late final PageController _controller = PageController(
    initialPage: widget.initialPage,
    viewportFraction: widget.viewportFraction,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _controller,
      scrollDirection: widget.scrollDirection,
      pageSnapping: widget.pageSnapping,
      onPageChanged: widget.onPageChanged,
      children: widget.children,
    );
  }
}
