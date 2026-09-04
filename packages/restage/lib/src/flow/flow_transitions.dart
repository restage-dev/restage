import 'package:flutter/widgets.dart';

/// Builds the transition between two flow screens.
///
/// Mirrors the `PageRouteBuilder` transition shape. [animation] is this
/// screen's own enter animation (0 → 1 as it becomes current); [secondaryAnimation]
/// drives how it is displaced as a later screen is pushed on top of it. The two
/// are mirror images for forward vs back: [isForward] is `true` for a push.
///
/// With no builder supplied, flow screens move with the app's
/// `pageTransitionsTheme` like any other route.
typedef FlowTransitionBuilder = Widget Function(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
  bool isForward,
);
