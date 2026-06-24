// Transition widgets come from two libraries: `CupertinoPageTransition` from
// the framework's Cupertino library and `SharedAxisTransition` from the
// Flutter-team `animations` package. Both are platform-motion sources isolated
// to these imports, so when the framework's Material/Cupertino libraries become
// standalone packages, swapping these import lines is the whole migration — no
// call-site changes.
import 'package:animations/animations.dart';
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

/// The platform-adaptive default flow transition: a Cupertino push on
/// iOS/macOS, a Material-3 shared-axis (horizontal) transition elsewhere.
///
/// Identical in light and dark. A host that wants a fixed transition regardless
/// of platform supplies its own [FlowTransitionBuilder].
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
      // The canonical Material-3 shared-axis (horizontal) transition. The
      // existing AnimationController drives [animation]/[secondaryAnimation] (so
      // the flow keeps duration control); the package owns the slide offset,
      // fade stagger, and curve, tracking the Material spec automatically. An
      // incoming screen has [secondaryAnimation] at 0 and an outgoing screen
      // has [animation] at 1, so each mounted screen plays exactly one role.
      return SharedAxisTransition(
        transitionType: SharedAxisTransitionType.horizontal,
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        // Transparent fill: each flow screen paints its own background, so the
        // package's default opaque `Theme.canvasColor` fill would flash through
        // the slide+fade between screens. (0x00000000 is fully transparent.)
        fillColor: const Color(0x00000000),
        child: child,
      );
  }
}
