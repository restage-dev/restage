import 'package:flutter/cupertino.dart'
    show CupertinoSheetTransition, kAlwaysDismissedAnimation;
import 'package:flutter/material.dart';

/// How [RestageModalSheet] chooses its platform presentation.
///
/// [adaptive] (the default) follows the ambient platform — the Material
/// bottom sheet on Android, the Cupertino card sheet on iOS/macOS.
/// [material] and [cupertino] pin the sheet to that library on every
/// platform, regardless of the ambient platform.
enum RestageSheetPresentation { adaptive, material, cupertino }

/// A modal bottom sheet that slides up over a scrim and can be dismissed
/// by dragging it down or tapping the scrim — expressed as a purely
/// declarative surface.
///
/// Visibility is driven by [open]: flip it to `true` and the sheet slides
/// in over a fading scrim; flip it to `false` (or let a drag / scrim-tap
/// fire [onSheetDismissed], which the caller wires back to `open = false`)
/// and it slides back out. The drag-to-dismiss gesture, the slide
/// animation, and the scrim all live inside this compiled widget; a
/// declarative composition supplies only the inert values (the open flag,
/// the styling) and the [child], and names the [onSheetDismissed] event —
/// never gesture or animation code.
///
/// Unlike Flutter's imperative `showModalBottomSheet`, this is an ordinary
/// widget in the tree: it owns its own animation controller and renders
/// the slide itself, so it needs no route and does not participate in the
/// host app's `Navigator` (the [RestagePager] posture). When [open] is
/// `false` and the close animation has finished, the sheet is not in the
/// tree at all — the surface beneath it is fully interactive.
///
/// The sheet rests flush against the bottom edge with rounded top corners
/// (the standard modal-sheet look, from the ambient bottom-sheet theme).
class RestageModalSheet extends StatefulWidget {
  /// Creates a declarative modal bottom sheet.
  const RestageModalSheet({
    super.key,
    required this.open,
    required this.child,
    this.isDismissible = true,
    this.enableDrag = true,
    this.showDragHandle,
    this.dragHandleColor,
    this.dragHandleSize,
    this.isScrollControlled = false,
    this.scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
    this.backgroundColor,
    this.elevation,
    this.shape,
    this.clipBehavior,
    this.constraints,
    this.useSafeArea = false,
    this.barrierColor,
    this.barrierLabel,
    this.anchorPoint,
    this.enterDuration,
    this.exitDuration,
    this.enterCurve,
    this.exitCurve,
    this.presentation = RestageSheetPresentation.adaptive,
    this.underlay,
    this.onSheetDismissed,
  })  : assert(
          elevation == null || elevation >= 0.0,
          'RestageModalSheet.elevation must be non-negative.',
        ),
        assert(
          scrollControlDisabledMaxHeightRatio > 0 &&
              scrollControlDisabledMaxHeightRatio <= 1,
          'RestageModalSheet.scrollControlDisabledMaxHeightRatio must be in '
          '(0, 1].',
        );

  /// Whether the sheet is shown. `true` slides it in; `false` slides it
  /// out (and, once the close animation finishes, removes it from the
  /// tree). The sole driver of visibility.
  ///
  /// `true` at initial mount shows the sheet instantly, with no slide-in
  /// animation; the slide-in only plays when [open] flips from `false` to
  /// `true` on an already-mounted widget.
  final bool open;

  /// The sheet body.
  final Widget child;

  /// When `true` (the default), tapping the scrim dismisses the sheet
  /// (fires [onSheetDismissed]).
  final bool isDismissible;

  /// When `true` (the default), the sheet can be dragged down and
  /// dismissed by swiping downward.
  final bool enableDrag;

  /// Whether a grab handle is shown at the top of the sheet. Null defers
  /// to the ambient bottom-sheet theme.
  final bool? showDragHandle;

  /// The grab handle's color. Null defers to the theme default.
  final Color? dragHandleColor;

  /// The grab handle's size. Null defers to the theme default.
  final Size? dragHandleSize;

  /// When `true`, the sheet may grow past half the available height to
  /// fit its content (e.g. a scrollable body). When `false` (the
  /// default), the sheet is capped at
  /// [scrollControlDisabledMaxHeightRatio] of the available height.
  final bool isScrollControlled;

  /// The fraction of the available height the sheet may occupy when
  /// [isScrollControlled] is `false`. Defaults to `9/16`.
  final double scrollControlDisabledMaxHeightRatio;

  /// The sheet's background color. Null defers to the theme default.
  final Color? backgroundColor;

  /// The sheet's elevation. Null defers to the theme default.
  final double? elevation;

  /// The sheet's shape. Null defers to the theme default (rounded top
  /// corners under Material 3).
  final ShapeBorder? shape;

  /// How to clip the sheet's content. Null defers to the theme default.
  final Clip? clipBehavior;

  /// Minimum and maximum sizes for the sheet. Null defers to the theme.
  final BoxConstraints? constraints;

  /// When `true`, the sheet avoids system intrusions on the top, left,
  /// and right. Defaults to `false` (edge-to-edge, flush to the bottom).
  final bool useSafeArea;

  /// The scrim color. Null defaults to a translucent black.
  final Color? barrierColor;

  /// Semantic label for the scrim, announced by assistive technology.
  final String? barrierLabel;

  /// The point used to disambiguate the sheet's placement on a display
  /// with hinges or folds. Null lets the framework choose.
  final Offset? anchorPoint;

  /// How long the slide-in takes on a programmatic open. Null uses the
  /// framework default (250ms).
  final Duration? enterDuration;

  /// How long the slide-out takes on a programmatic close. Null uses the
  /// framework default (200ms).
  final Duration? exitDuration;

  /// The easing curve for a programmatic open. Null uses the platform
  /// default (an eased curve); a drag always tracks the finger 1:1
  /// regardless. Set it to tune the open feel.
  final Curve? enterCurve;

  /// The easing curve for a programmatic close. Null uses the platform
  /// default. A drag always tracks the finger 1:1 regardless.
  final Curve? exitCurve;

  /// How the sheet chooses its platform presentation. Defaults to
  /// [RestageSheetPresentation.adaptive] (the Material bottom sheet on
  /// Android, the Cupertino card sheet on iOS/macOS). Set
  /// [RestageSheetPresentation.material] or
  /// [RestageSheetPresentation.cupertino] to pin the sheet to that library
  /// on every platform.
  final RestageSheetPresentation presentation;

  /// The surface shown *beneath* the sheet, owned by this widget. When
  /// non-null and the platform is iOS/macOS, it scales down and rounds as
  /// the sheet rises (the iOS card-sheet look); on other platforms it
  /// renders plain behind the sheet. Null (the default) is a pure overlay —
  /// the sheet floats over whatever is already behind it, with no owned
  /// surface and no scale-down.
  final Widget? underlay;

  /// Fires when the sheet is dismissed by a downward drag or a scrim tap.
  /// Distinct from the paywall-level dismiss: this is the *sheet* closing,
  /// not the surface that hosts it. Wire it back to `open = false`.
  final VoidCallback? onSheetDismissed;

  @override
  State<RestageModalSheet> createState() => _RestageModalSheetState();
}

// The eased curve for a programmatic (tap) open/close. Mirrors Flutter's
// `_modalBottomSheetCurve = Easing.legacyDecelerate` (`material/bottom_sheet.dart`),
// i.e. `Cubic(0.0, 0.0, 0.2, 1.0)` — fast start, gentle settle.
const Cubic _kMaterialProgrammaticCurve = Cubic(0, 0, 0.2, 1);

// Framework defaults for a null enter/exit duration (`_bottomSheetEnterDuration`
// / `_bottomSheetExitDuration` in `material/bottom_sheet.dart`).
const Duration _kEnterDuration = Duration(milliseconds: 250);
const Duration _kExitDuration = Duration(milliseconds: 200);

class _RestageModalSheetState extends State<RestageModalSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      BottomSheet.createAnimationController(
    this,
    sheetAnimationStyle: AnimationStyle(
      duration: widget.enterDuration ?? _kEnterDuration,
      reverseDuration: widget.exitDuration ?? _kExitDuration,
    ),
  );

  // The curve applied to the slide *position*. Mirrors Flutter's
  // `_ModalBottomSheetState.animationCurve` (`material/bottom_sheet.dart`): the
  // programmatic curve for a tap open/close, `Curves.linear` during a drag so
  // the sheet tracks the finger 1:1, and a `Split` that resumes smoothly from
  // the drag-release position. The scrim alpha is keyed to the raw controller
  // value, not this curve.
  late ParametricCurve<double> _slideCurve = _programmaticCurve(opening: true);

  // The dev-set curve for the given direction, falling back to the platform
  // default (Material's eased curve; the iOS path uses its own curve).
  Curve _programmaticCurve({required bool opening}) =>
      (opening ? widget.enterCurve : widget.exitCurve) ??
      _kMaterialProgrammaticCurve;

  // Guards [onSheetDismissed] to a single fire per open→dismiss cycle: the
  // dismiss path is reachable from both the scrim and a drag, so without
  // this a single dismiss could notify more than once. Re-armed whenever
  // the sheet opens.
  bool _dismissing = false;

  // True while the user is actively dragging the sheet. The iOS path keys
  // `CupertinoSheetTransition.linearTransition` off this for a 1:1 drag.
  bool _dragging = false;

  // True from a drag-release until the resulting settle (a fling-close or a
  // snap-back-open) reaches its terminal status. While set, both platform
  // paths keep the SAME continuous slide mapping the drag used — they do NOT
  // swap to the programmatic curve — so the sheet never snaps at the
  // drag→settle boundary. Drag-only: a scrim-tap / programmatic close never
  // sets it, so those keep the eased curve.
  bool _settlingFromDrag = false;

  // Clears the drag-settle, dropping the terminal-status listener. Idempotent
  // (a removeStatusListener for an unregistered listener is a no-op).
  void _clearSettle() {
    _settlingFromDrag = false;
    _controller.removeStatusListener(_clearSettleOnTerminal);
  }

  // Ends the drag-settle once the controller comes to rest at either end
  // (dismissed after a fling-close, completed after a snap-back-open).
  void _clearSettleOnTerminal(AnimationStatus status) {
    if (status == AnimationStatus.dismissed ||
        status == AnimationStatus.completed) {
      _clearSettle();
    }
  }

  // Applies a dev-set curve to the iOS slide. Used only when `enterCurve` /
  // `exitCurve` is set and not while dragging, so the override never fights
  // the 1:1 drag; otherwise `CupertinoSheetTransition` uses its own curve.
  late final CurvedAnimation _iosCurve = CurvedAnimation(
    parent: _controller,
    curve: widget.enterCurve ?? Curves.linear,
    reverseCurve: widget.exitCurve ?? Curves.linear,
  );

  bool get _hasCurveOverride =>
      widget.enterCurve != null || widget.exitCurve != null;

  // The effective platform path. [RestageSheetPresentation.material] /
  // [RestageSheetPresentation.cupertino] pin the library regardless of
  // platform; [RestageSheetPresentation.adaptive] respects a
  // `ThemeData.platform` override, like Material's `.adaptive` constructors.
  bool _isCupertino(BuildContext context) {
    switch (widget.presentation) {
      case RestageSheetPresentation.material:
        return false;
      case RestageSheetPresentation.cupertino:
        return true;
      case RestageSheetPresentation.adaptive:
        final TargetPlatform platform = Theme.of(context).platform;
        return platform == TargetPlatform.iOS ||
            platform == TargetPlatform.macOS;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      _controller.value = 1.0;
      _dismissing = false;
    }
  }

  @override
  void didUpdateWidget(RestageModalSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enterCurve != oldWidget.enterCurve) {
      _iosCurve.curve = widget.enterCurve ?? Curves.linear;
    }
    if (widget.exitCurve != oldWidget.exitCurve) {
      _iosCurve.reverseCurve = widget.exitCurve ?? Curves.linear;
    }
    if (widget.open != oldWidget.open) {
      if (widget.open) {
        // A programmatic open eases and cancels any in-flight drag settle.
        _slideCurve = _programmaticCurve(opening: true);
        _clearSettle();
        _dismissing = false;
        _controller.forward();
      } else if (_controller.status != AnimationStatus.reverse) {
        // A programmatic / scrim-tap close — nothing is already driving the
        // controller down — so ease and drive it as the sole driver.
        _slideCurve = _programmaticCurve(opening: false);
        _controller.reverse();
      }
      // Else (status == reverse): a drag-close fling is already the single
      // driver and the Split keeps the slide continuous — don't reset the
      // curve or re-base the in-flight animation with a redundant reverse().
    }
  }

  // Track the user's finger 1:1 while dragging (no easing on the slide); a
  // fresh drag supersedes any in-flight drag settle.
  void _handleDragStart(DragStartDetails details) {
    _dragging = true;
    _slideCurve = Curves.linear;
    _clearSettle();
  }

  // Resume the slide smoothly from the drag-release position. The `Split` keeps
  // the Material slide continuous (linear up to the release point, then the
  // settle's curve); `_settlingFromDrag` keeps BOTH paths continuous through
  // the settle the BottomSheet just started (a fling-close or a snap-back-open)
  // by suppressing the programmatic curve/driver swap until it comes to rest.
  void _handleDragEnd(DragEndDetails details, {required bool isClosing}) {
    _dragging = false;
    _slideCurve = Split(
      _controller.value,
      endCurve: _programmaticCurve(opening: !isClosing),
    );
    _settlingFromDrag = true;
    _controller
      ..removeStatusListener(_clearSettleOnTerminal)
      ..addStatusListener(_clearSettleOnTerminal);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_clearSettleOnTerminal);
    _iosCurve.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissing) {
      return;
    }
    _dismissing = true;
    widget.onSheetDismissed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) {
        // Closed and the close animation has finished: the sheet + scrim are
        // gone. If we own an underlay, keep rendering it (full size, fully
        // interactive) so the surface stays visible; otherwise render nothing,
        // leaving the surface beneath fully interactive.
        if (!widget.open && _controller.isDismissed) {
          return widget.underlay ?? const SizedBox.shrink();
        }
        final double t = _controller.value.clamp(0.0, 1.0);
        final bool cupertino = _isCupertino(context);
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (widget.underlay != null)
              Positioned.fill(
                // iOS/macOS scale the owned underlay down behind the rising
                // sheet (the card-sheet look); other platforms render it plain.
                child: cupertino
                    ? _IosUnderlayScaleDown(
                        progress: _controller,
                        child: widget.underlay!,
                      )
                    : widget.underlay!,
              ),
            // With an owned iOS underlay the dim comes from the scale-down, so
            // the scrim is a transparent tap-dismiss layer; otherwise it dims.
            Positioned.fill(
              child: _buildScrim(
                t,
                dimless: cupertino && widget.underlay != null,
              ),
            ),
            Positioned.fill(
              child:
                  cupertino ? _buildCupertinoSheet() : _buildMaterialSheet(t),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScrim(double t, {bool dimless = false}) {
    final Color base = dimless
        ? const Color(0x00000000)
        : (widget.barrierColor ?? Colors.black54);
    // Fully closed (alpha 0): never intercept taps to the surface beneath,
    // even while still mounted (e.g. mid-reverse before the unmount guard
    // fires, or when the sheet drives itself shut while [open] stays true).
    return IgnorePointer(
      ignoring: t == 0.0,
      child: ModalBarrier(
        color: base.withValues(alpha: base.a * t),
        dismissible: widget.isDismissible,
        onDismiss: _dismiss,
        semanticsLabel: widget.barrierLabel,
      ),
    );
  }

  // The iOS/macOS card-sheet path: the slide is the public Cupertino sheet
  // transition (driven by our controller), the drag + onClosing come from the
  // Material BottomSheet underneath. Route-free.
  //
  // The slide *visual* matches the platform sheet transition exactly (the
  // controller is rendered with `linearTransition` during a drag and its
  // settle, easing only on a programmatic open/close — mirroring how the
  // platform's own sheet drives the transition). The drag *gesture* itself is
  // the Material `BottomSheet`'s, because the platform's native sheet-drag
  // gesture controller is private; so a drag-release currently settles with
  // Material's release physics rather than the platform sheet's. A future
  // route-free reproduction of the platform drag gesture will align the
  // release physics too.
  Widget _buildCupertinoSheet() {
    // During a drag AND through its settle, drive the transition with the raw
    // controller (1:1, linearTransition) so the slide is continuous across the
    // drag→settle boundary — no swap to the eased curve mid-close (the jitter).
    // For a programmatic / scrim-tap open/close, use the dev override curve if
    // set, else let the Cupertino transition apply its own platform curve.
    final bool dragLike = _dragging || _settlingFromDrag;
    final bool useOverride = _hasCurveOverride && !dragLike;
    final Widget sheet = CupertinoSheetTransition(
      primaryRouteAnimation: useOverride ? _iosCurve : _controller,
      secondaryRouteAnimation: kAlwaysDismissedAnimation,
      linearTransition: dragLike || _hasCurveOverride,
      child: _buildBottomSheet(),
    );
    return _wrapInsets(sheet);
  }

  // The Material BottomSheet — the drag + onClosing primitive both platform
  // paths render underneath their own slide treatment.
  BottomSheet _buildBottomSheet() {
    return BottomSheet(
      animationController: _controller,
      enableDrag: widget.enableDrag,
      onDragStart: _handleDragStart,
      onDragEnd: _handleDragEnd,
      onClosing: _dismiss,
      showDragHandle: widget.showDragHandle,
      dragHandleColor: widget.dragHandleColor,
      dragHandleSize: widget.dragHandleSize,
      backgroundColor: widget.backgroundColor,
      elevation: widget.elevation,
      shape: widget.shape,
      clipBehavior: widget.clipBehavior,
      constraints: widget.constraints,
      builder: (BuildContext context) => widget.child,
    );
  }

  // SafeArea + display-feature wrapping shared by both platform paths.
  Widget _wrapInsets(Widget sheet) {
    var wrapped = sheet;
    if (widget.useSafeArea) {
      wrapped = SafeArea(bottom: false, child: wrapped);
    }
    if (widget.anchorPoint != null) {
      wrapped = DisplayFeatureSubScreen(
        anchorPoint: widget.anchorPoint,
        child: wrapped,
      );
    }
    return wrapped;
  }

  Widget _buildMaterialSheet(double t) {
    Widget sheet = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxHeight = widget.isScrollControlled
            ? constraints.maxHeight
            : constraints.maxHeight *
                widget.scrollControlDisabledMaxHeightRatio;
        // The slide position eases on a programmatic open/close and tracks the
        // finger 1:1 during a drag (the scrim stays keyed to the raw value).
        final double tSlide = _slideCurve.transform(t).clamp(0.0, 1.0);
        return Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: FractionalTranslation(
            // Fully below the bottom edge at t == 0, flush at t == 1.
            translation: Offset(0, 1 - tSlide),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: _buildBottomSheet(),
            ),
          ),
        );
      },
    );
    return _wrapInsets(sheet);
  }
}

// iOS behind-page scale-down constants, replicated from Flutter's
// `CupertinoSheetTransition.delegateTransition` (`package:flutter/src/cupertino/
// sheet.dart`). That machinery is route-bound (it calls `Navigator.of`), so we
// reproduce its motion route-free here. If Flutter retunes these, ours drift —
// tracked as a `[follow-up]`.
const double _kIosUnderlayScale = 1 - 0.0835; // _kSheetScaleFactor = 0.0835
const Offset _kIosUnderlaySlideDown = Offset(0, 0.07); // _kTopDownTween end
const double _kIosUnderlayDim = 0.10; // _kOpacityTween end
const double _kIosUnderlayCorner = 12; // delegateTransition radius end

/// Scales, slides, dims, and rounds the [child] (the sheet's owned underlay)
/// as [progress] rises 0→1 — the iOS card-sheet "background recedes" motion,
/// reproduced **route-free and Navigator-free** so it renders on every surface
/// (including the editor canvas, which guarantees no `Navigator`). Pure
/// controller-driven Scale / Slide / dim / corner-round; no `Navigator.of`.
class _IosUnderlayScaleDown extends StatefulWidget {
  const _IosUnderlayScaleDown({required this.progress, required this.child});

  final Animation<double> progress;
  final Widget child;

  @override
  State<_IosUnderlayScaleDown> createState() => _IosUnderlayScaleDownState();
}

class _IosUnderlayScaleDownState extends State<_IosUnderlayScaleDown> {
  late CurvedAnimation _curve;
  late Animation<Offset> _slide;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  late Animation<BorderRadius?> _radius;

  @override
  void initState() {
    super.initState();
    _curve = _makeCurve();
    _bindAnimations();
  }

  CurvedAnimation _makeCurve() => CurvedAnimation(
        parent: widget.progress,
        curve: Curves.linearToEaseOut,
        reverseCurve: Curves.easeInToLinear,
      );

  // Driven off the (constant-endpoint) tweens once, so the per-frame build
  // just references them rather than reallocating four Animations per tick.
  void _bindAnimations() {
    _slide = _curve.drive(
      Tween<Offset>(begin: Offset.zero, end: _kIosUnderlaySlideDown),
    );
    _scale = _curve.drive(Tween<double>(begin: 1, end: _kIosUnderlayScale));
    _opacity = _curve.drive(Tween<double>(begin: 0, end: _kIosUnderlayDim));
    _radius = _curve.drive(BorderRadiusTween(
      begin: BorderRadius.zero,
      end: BorderRadius.circular(_kIosUnderlayCorner),
    ));
  }

  @override
  void didUpdateWidget(covariant _IosUnderlayScaleDown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _curve.dispose();
      _curve = _makeCurve();
      _bindAnimations();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.medium,
        child: AnimatedBuilder(
          animation: _radius,
          builder: (BuildContext context, Widget? child) => ClipRSuperellipse(
            borderRadius: _radius.value ?? BorderRadius.zero,
            child: Stack(
              fit: StackFit.passthrough,
              children: <Widget>[
                child!,
                Positioned.fill(
                  child: FadeTransition(
                    opacity: _opacity,
                    child: const ColoredBox(color: Color(0xFF000000)),
                  ),
                ),
              ],
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
