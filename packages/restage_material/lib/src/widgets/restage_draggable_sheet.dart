import 'package:flutter/widgets.dart';

/// A persistent, resizable bottom sheet the user drags between a peek size
/// and a fully-expanded size — expressed as a purely declarative surface.
/// Unlike [RestageModalSheet] it never dismisses: it bottoms out at
/// [minChildSize] and stays in the layout.
///
/// The sheet starts at [initialChildSize] (the peek). The user can drag it up
/// to [maxChildSize] and back down to [minChildSize]; once expanded, the
/// [child] scrolls. Flip [expanded] to `true` to animate the sheet to
/// [maxChildSize] (a controller-driven expand, e.g. from a "see plans" button
/// whose `onTap` sets the bound state field); flip it back to `false` to
/// animate to [initialChildSize] (the peek). The drag / snap / fling physics
/// and the scroll-coordination all live inside this compiled widget (Flutter's
/// `DraggableScrollableSheet`); a declarative composition supplies only the
/// inert detents, the [expanded] flag, and the [child] — never gesture or
/// animation code.
///
/// It is an ordinary widget in the tree: no route, and it does not participate
/// in the host app's `Navigator` (the [RestagePager] posture). It draws nothing
/// of its own — it owns the live `ScrollController` that `DraggableScrollableSheet`
/// hands its builder and threads it into a [SingleChildScrollView] wrapping the
/// [child], so the whole sheet is draggable and long content scrolls once
/// expanded. The [child] supplies its own surface (background, rounded top,
/// grab handle), exactly as a `DraggableScrollableSheet`'s builder result does.
///
/// **Child contract — ordinary (non-scrollable) content.** This widget wraps
/// the [child] in the single [SingleChildScrollView] that the drag controller
/// drives, so the whole sheet is draggable. A [child] that is *itself* a
/// scrollable (`ListView`, `GridView`, `CustomScrollView`) or that contains an
/// unbounded `Expanded`/`Flexible` is **not** supported by this wrapper alone:
/// nesting it under the wrapper's scroll view would nest vertical viewports (a
/// layout error) or leave the inner scrollable on its own controller — so the
/// drag/scroll hand-off would not match native `DraggableScrollableSheet`,
/// whose contract is that the builder's own scroll view uses the supplied
/// controller. Composing the body so the controller reaches the real
/// scrollable is the job of the generated lowering, which threads the
/// controller into a scrollable child or defers — never silently mis-renders.
///
/// **Detents are read at mount.** [initialChildSize], [minChildSize], and
/// [maxChildSize] fix the resting/peek size and the drag range when the widget
/// is first built; [expanded] flips drive the sheet between [initialChildSize]
/// and [maxChildSize] at runtime, but changing a detent *value* on an
/// already-mounted widget is not reflected. Server-driven detents are inert
/// literals fixed per render, so this matches their lifecycle.
class RestageDraggableSheet extends StatefulWidget {
  /// Creates a declarative draggable (persistent, non-closeable) sheet.
  const RestageDraggableSheet({
    super.key,
    required this.child,
    this.initialChildSize = 0.5,
    this.minChildSize = 0.25,
    this.maxChildSize = 1.0,
    this.expand = true,
    this.snap = false,
    this.snapSizes,
    this.snapAnimationDuration,
    this.expanded = false,
    this.expandDuration,
    this.expandCurve,
  })  : assert(
          minChildSize >= 0.0,
          'RestageDraggableSheet.minChildSize must be >= 0.',
        ),
        assert(
          maxChildSize <= 1.0,
          'RestageDraggableSheet.maxChildSize must be <= 1.',
        ),
        assert(
          minChildSize <= initialChildSize,
          'RestageDraggableSheet.minChildSize must be <= initialChildSize.',
        ),
        assert(
          initialChildSize <= maxChildSize,
          'RestageDraggableSheet.initialChildSize must be <= maxChildSize.',
        );

  /// The sheet body. Wrapped in a [SingleChildScrollView] bound to the sheet's
  /// drag controller, so the whole sheet is draggable and the body scrolls once
  /// the sheet is fully expanded.
  final Widget child;

  /// The fraction of the parent's height the sheet occupies at rest (the
  /// peek). Defaults to `0.5`.
  final double initialChildSize;

  /// The minimum fraction the sheet can be dragged to — the persistent floor.
  /// The sheet never dismisses below it. Defaults to `0.25`.
  final double minChildSize;

  /// The maximum fraction the sheet expands to. Defaults to `1.0`.
  final double maxChildSize;

  /// Whether the sheet expands to fill the available space in its parent.
  /// Defaults to `true`.
  final bool expand;

  /// Whether the sheet snaps between [snapSizes] when the user lifts their
  /// finger during a drag. Defaults to `false`.
  final bool snap;

  /// Extra fractional sizes the sheet snaps to, between [minChildSize] and
  /// [maxChildSize] in ascending order. [minChildSize] and [maxChildSize] are
  /// implicit. Null snaps between the min and max only.
  final List<double>? snapSizes;

  /// The duration of a snap animation. Null lets the framework derive it from
  /// the fling velocity.
  final Duration? snapAnimationDuration;

  /// Whether the sheet is expanded. Flip to `true` to animate the sheet to
  /// [maxChildSize]; flip to `false` to animate back to [initialChildSize]
  /// (the peek). This is the sole programmatic driver; a manual drag is
  /// independent. `true` at initial mount shows the sheet expanded instantly,
  /// with no animation.
  final bool expanded;

  /// How long the [expanded]-driven expand/collapse takes. Null uses the
  /// framework default (250ms).
  final Duration? expandDuration;

  /// The easing curve for the [expanded]-driven expand/collapse. Null uses the
  /// framework default (an eased curve). A manual drag is unaffected.
  final Curve? expandCurve;

  @override
  State<RestageDraggableSheet> createState() => _RestageDraggableSheetState();
}

// Framework defaults for a null expand duration / curve.
const Duration _kExpandDuration = Duration(milliseconds: 250);
const Curve _kExpandCurve = Curves.easeOut;

class _RestageDraggableSheetState extends State<RestageDraggableSheet> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  // The size shown on the first frame: the expanded ceiling if [expanded] is
  // set at mount (instant, no flash), else the peek. Computed once and kept
  // stable across rebuilds so the wrapped sheet's initialChildSize never
  // churns; runtime [expanded] flips are driven by animateTo, not by this.
  late final double _mountChildSize =
      widget.expanded ? widget.maxChildSize : widget.initialChildSize;

  @override
  void didUpdateWidget(RestageDraggableSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != oldWidget.expanded) {
      _animateToExpanded(expanded: widget.expanded);
    }
  }

  // Drive the sheet to the expanded ceiling or back to the peek. A no-op until
  // the controller is attached to a built sheet, so an early flip can't throw.
  void _animateToExpanded({required bool expanded}) {
    if (!_controller.isAttached) {
      return;
    }
    _controller.animateTo(
      expanded ? widget.maxChildSize : widget.initialChildSize,
      duration: widget.expandDuration ?? _kExpandDuration,
      curve: widget.expandCurve ?? _kExpandCurve,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: _mountChildSize,
      minChildSize: widget.minChildSize,
      maxChildSize: widget.maxChildSize,
      expand: widget.expand,
      snap: widget.snap,
      snapSizes: widget.snapSizes,
      snapAnimationDuration: widget.snapAnimationDuration,
      // Persistent + non-closeable: the sheet bottoms out at minChildSize and
      // never asks a parent to close — there is no route to close, this is an
      // ordinary in-layout widget.
      shouldCloseOnMinExtent: false,
      builder: (BuildContext context, ScrollController scrollController) {
        // The inert child can't receive the live controller, so the wrapper
        // owns the scrollable and threads it: the whole sheet is draggable and
        // long content scrolls once the sheet is fully expanded.
        return SingleChildScrollView(
          controller: scrollController,
          child: widget.child,
        );
      },
    );
  }
}
