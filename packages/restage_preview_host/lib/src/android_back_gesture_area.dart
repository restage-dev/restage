import 'package:flutter/widgets.dart';

/// How far in from either edge a drag must START to read as system back.
///
/// Android reserves a narrow strip at each edge for its own gesture and leaves
/// everything inboard of it to the app; 24 is that strip.
const double _kEdgeWidth = 24;

/// How far across the screen the drag must travel to commit, as a fraction of
/// the screen's width.
const double _kCommitFraction = 0.25;

/// The inward speed, in logical pixels per second, that commits a short drag —
/// a fling, which Android accepts without the full travel.
const double _kCommitVelocity = 700;

/// How far the screen shrinks at full drag, mirroring Android's predictive
/// back preview. A hint that the surface is about to leave, not an animation
/// of it leaving.
const double _kPeekScale = 0.06;

/// Emulates Android's system back gesture over a previewed Android device.
///
/// On a phone the OS owns the edge gesture and delivers it to the app as
/// system back; the app never sees the drag. A preview has no OS, so the drag
/// is recognised here and delivered as a pop of [navigator] — the same route
/// the gesture would pop on a device, so the SDK's own `PopScope` decides what
/// happens exactly as it would there.
///
/// Only the two edge strips take drags. Everything inboard of them is left
/// alone, so a scrolling or swiping surface behaves as it does on a device.
class AndroidBackGestureArea extends StatefulWidget {
  /// Construct an [AndroidBackGestureArea].
  const AndroidBackGestureArea({
    required this.navigator,
    required this.child,
    super.key,
  });

  /// The navigator the gesture pops.
  final GlobalKey<NavigatorState> navigator;

  /// The previewed surface.
  final Widget child;

  @override
  State<AndroidBackGestureArea> createState() => _AndroidBackGestureAreaState();
}

class _AndroidBackGestureAreaState extends State<AndroidBackGestureArea> {
  /// How far the live drag has come, as a fraction of the screen's width.
  final ValueNotifier<double> _peek = ValueNotifier<double>(0);

  double _travelled = 0;

  @override
  void dispose() {
    _peek.dispose();
    super.dispose();
  }

  void _start() => _travelled = 0;

  void _update(double inward, double width) {
    _travelled += inward;
    _peek.value = width <= 0 ? 0 : (_travelled / width).clamp(0.0, 1.0);
  }

  void _end(double inwardVelocity, double width) {
    final committed = _travelled > width * _kCommitFraction ||
        inwardVelocity > _kCommitVelocity;
    _cancel();
    if (committed) widget.navigator.currentState?.maybePop();
  }

  void _cancel() {
    _travelled = 0;
    _peek.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: ValueListenableBuilder<double>(
                valueListenable: _peek,
                builder: (context, peek, child) => Transform.scale(
                  scale: 1 - peek * _kPeekScale,
                  child: child,
                ),
                child: widget.child,
              ),
            ),
            _edge(fromLeft: true, width: width),
            _edge(fromLeft: false, width: width),
          ],
        );
      },
    );
  }

  Widget _edge({required bool fromLeft, required double width}) {
    // Inward is rightward from the left edge and leftward from the right one,
    // so one sign convention covers both strips.
    double inward(double dx) => fromLeft ? dx : -dx;
    return Positioned(
      top: 0,
      bottom: 0,
      left: fromLeft ? 0 : null,
      right: fromLeft ? null : 0,
      width: _kEdgeWidth,
      child: GestureDetector(
        // Translucent: the strip takes drags without swallowing the taps that
        // land under it, so a control at the screen's edge still works.
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _start(),
        onHorizontalDragUpdate: (details) =>
            _update(inward(details.delta.dx), width),
        onHorizontalDragEnd: (details) =>
            _end(inward(details.velocity.pixelsPerSecond.dx), width),
        onHorizontalDragCancel: _cancel,
      ),
    );
  }
}
