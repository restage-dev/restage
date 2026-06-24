import 'package:flutter/widgets.dart';

import 'restage_motion.dart';
import 'restage_spring.dart';

/// Reveals a vertical list of [children] with a cascading entrance — each child
/// springs into place ([RestageMotion]'s entrance), delayed by [delayBetween]
/// times its index, so the list flows in rather than appearing at once.
///
/// A genuine gap over the implicit `Animated*` suite, which has no notion of a
/// staggered group. Children are laid out in a [Column] (the canonical vertical
/// list reveal); a horizontal variant is a future addition.
///
/// The default entrance is a staggered fade ([fromOpacity] `0`); set
/// [fromOffset] for a fade-and-rise. Composes the entrance widget, so the same
/// controller-inside-the-widget, values-only-on-the-wire contract applies.
class RestageStagger extends StatelessWidget {
  /// Creates a staggered reveal of [children].
  const RestageStagger({
    super.key,
    required this.children,
    this.delayBetween,
    this.spring = RestageSpring.smooth,
    this.fromOffset = Offset.zero,
    this.fromOpacity = 0.0,
    this.fromScale = 1.0,
  });

  /// The default per-child delay when [delayBetween] is null.
  static const Duration defaultDelayBetween = Duration(milliseconds: 60);

  /// The children revealed in order, top to bottom.
  final List<Widget> children;

  /// The delay added per child — child `i` starts after `delayBetween * i`.
  /// Null uses [defaultDelayBetween] (60ms). Clamped to a safe range so a
  /// pathological value cannot overflow the per-child delay.
  final Duration? delayBetween;

  /// The spring feel each child enters with. Defaults to [RestageSpring.smooth].
  final RestageSpring spring;

  /// The translation (in logical pixels) each child enters from. Defaults to
  /// `Offset.zero` (a pure fade stagger).
  final Offset fromOffset;

  /// The opacity each child enters from. Defaults to `0.0` (fade in).
  final double fromOpacity;

  /// The scale each child enters from. Defaults to `1.0` (no scale).
  final double fromScale;

  @override
  Widget build(BuildContext context) {
    // Clamp the step to the shared safe range before multiplying by the child
    // index, so a pathological wire delayBetween cannot overflow Int64 to a
    // negative delay (which would break the stagger order). child 0 stays at
    // zero delay since `step * 0` is always zero.
    final step = sanitizeMotionDuration(
      delayBetween,
      fallback: defaultDelayBetween,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++)
          RestageMotion(
            spring: spring,
            fromOffset: fromOffset,
            fromOpacity: fromOpacity,
            fromScale: fromScale,
            delay: step * i,
            child: children[i],
          ),
      ],
    );
  }
}
