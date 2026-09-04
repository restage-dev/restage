// `CupertinoPageTransition` comes from the framework's Cupertino library, the
// only platform-motion import here, so when that library becomes a standalone
// package swapping the import line is the whole migration.
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

/// Builds the transition between two flow screens.
///
/// Mirrors the `PageRouteBuilder` transition shape. [animation] is this
/// screen's own enter animation (0 → 1 as it becomes current); [secondaryAnimation]
/// drives how it is displaced as a later screen is pushed on top of it. The two
/// are mirror images for forward vs back: [isForward] is `true` for a push.
typedef FlowTransitionBuilder = Widget Function(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
  bool isForward,
);

/// A platform-adaptive flow transition: a Cupertino push on iOS/macOS, a
/// horizontal shared-axis motion elsewhere.
///
/// Flow screens are routes, so with no [FlowTransitionBuilder] supplied they
/// already move with the app's `pageTransitionsTheme`. Pass this builder to
/// pin the motion to a shared-axis push regardless of the app's theme.
/// Identical in light and dark.
Widget defaultFlowTransitionBuilder(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
  bool isForward,
) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return CupertinoPageTransition(
        primaryRouteAnimation: animation,
        secondaryRouteAnimation: secondaryAnimation,
        linearTransition: false,
        child: child,
      );
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      // A horizontal shared-axis motion in which only the entering screen
      // fades. Each flow screen paints its own background, so the screen
      // beneath stays opaque while the one above slides and fades over it and
      // nothing shows through between them.
      return _SharedAxisOverlay(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
  }
}

/// Horizontal shared-axis motion for one flow screen.
///
/// The entering screen slides in from the trailing edge and fades in over the
/// screen it covers, which stays put at full opacity, so nothing behind the
/// pair ever shows through. Run in reverse the same motion plays a back.
class _SharedAxisOverlay extends StatelessWidget {
  const _SharedAxisOverlay({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;

  /// Unused: the covered screen does not move.
  final Animation<double> secondaryAnimation;
  final Widget child;

  static const double _shift = 0.08;
  static const Curve _curve = Curves.easeInOutCubicEmphasized;

  @override
  Widget build(BuildContext context) {
    final enter = CurvedAnimation(parent: animation, curve: _curve);
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(_shift, 0),
        end: Offset.zero,
      ).animate(enter),
      child: FadeTransition(opacity: enter, child: child),
    );
  }
}
