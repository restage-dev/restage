import 'dart:async';

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'restage_spring.dart';

/// Springs [child] into place when it first appears.
///
/// On mount, the child animates from an initial transform — a starting scale
/// ([fromScale]), opacity ([fromOpacity]), and/or translation ([fromOffset]) —
/// to its resting state, driven by a physical spring ([spring]). Unlike the
/// implicit `Animated*` widgets (which animate when a property *changes*), this
/// plays a one-shot entrance on appear, and its spring overshoots and settles
/// rather than easing along a curve — the difference is visible and is the
/// point of the widget.
///
/// This is a manual-adoption widget: a developer writes it directly in place of
/// an imperative `AnimationController` entrance. The animation controller lives
/// entirely inside this compiled widget; a paywall blob carries only the
/// declarative values (the preset, the optional overrides, the from-state, the
/// delay) and the child — never animation code.
///
/// For a simple opacity fade with no spring physics, see `RestageFadeIn`.
class RestageMotion extends StatefulWidget {
  /// Creates a spring entrance for [child].
  const RestageMotion({
    super.key,
    required this.child,
    this.spring = RestageSpring.smooth,
    this.duration,
    this.bounce,
    this.fromScale = 1.0,
    this.fromOpacity = 1.0,
    this.fromOffset = Offset.zero,
    this.delay,
    this.onEnd,
  });

  /// The widget that springs into place.
  final Widget child;

  /// The named spring feel. Defaults to [RestageSpring.smooth].
  final RestageSpring spring;

  /// Optional override for the preset's settle duration. Null keeps the
  /// preset's duration. Independent of [bounce] — overriding one leaves the
  /// other at the preset's value.
  final Duration? duration;

  /// Optional override for the preset's bounce (overshoot). Null keeps the
  /// preset's bounce. Independent of [duration]. Clamped internally so no value
  /// can produce a non-settling spring.
  final double? bounce;

  /// The scale the child animates from. `1.0` (the default) means no scale
  /// animation; `< 1.0` pops in, `> 1.0` shrinks in.
  final double fromScale;

  /// The opacity the child animates from. `1.0` (the default) means no fade;
  /// `0.0` fades in.
  final double fromOpacity;

  /// The translation (in logical pixels) the child animates from. `Offset.zero`
  /// (the default) means no slide; e.g. `Offset(0, 24)` rises into place.
  final Offset fromOffset;

  /// How long to wait after mount before the entrance starts. Null means no
  /// delay (start immediately).
  final Duration? delay;

  /// Fires once when the entrance settles. Never fires if the widget is
  /// disposed before settling.
  final VoidCallback? onEnd;

  @override
  State<RestageMotion> createState() => _RestageMotionState();
}

class _RestageMotionState extends State<RestageMotion>
    with SingleTickerProviderStateMixin {
  // Unbounded so the spring's overshoot past the target (value > 1) is not
  // clamped — the overshoot is the visible spring character.
  late final AnimationController _controller =
      AnimationController.unbounded(vsync: this);
  Timer? _delayTimer;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    final delay = widget.delay;
    if (delay != null && delay > Duration.zero) {
      _delayTimer = Timer(delay, _start);
    } else {
      _start();
    }
  }

  void _start() {
    if (!mounted) return;
    final simulation = SpringSimulation(
      springDescriptionFor(
        widget.spring,
        durationOverride: widget.duration,
        bounceOverride: widget.bounce,
      ),
      0,
      1,
      0,
    );
    // `orCancel` rejects if the ticker is canceled (the widget is disposed
    // mid-flight), so onEnd fires only on a genuine settle, exactly once.
    _controller.animateWith(simulation).orCancel.then(
      (_) => _handleEnd(),
      onError: (_) {/* canceled on dispose — no onEnd */},
    );
  }

  void _handleEnd() {
    if (_ended || !mounted) return;
    _ended = true;
    widget.onEnd?.call();
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        var result = child!;
        // Guard the value handed to each render primitive to be finite, so no
        // wire input renders garbage — whether non-finite directly, or a finite
        // extreme that overflows during interpolation under the spring's
        // overshoot. A non-finite value falls back to the identity.
        if (widget.fromOffset != Offset.zero) {
          final offset = widget.fromOffset * (1 - t);
          result = Transform.translate(
            offset: offset.isFinite ? offset : Offset.zero,
            child: result,
          );
        }
        if (widget.fromScale != 1.0) {
          final scale = widget.fromScale + (1 - widget.fromScale) * t;
          result = Transform.scale(
            scale: scale.isFinite ? scale : 1.0,
            child: result,
          );
        }
        if (widget.fromOpacity != 1.0) {
          final opacity = (widget.fromOpacity + (1 - widget.fromOpacity) * t)
              .clamp(0.0, 1.0);
          result = Opacity(
            opacity: opacity.isFinite ? opacity : 1.0,
            child: result,
          );
        }
        return result;
      },
      child: widget.child,
    );
  }
}
