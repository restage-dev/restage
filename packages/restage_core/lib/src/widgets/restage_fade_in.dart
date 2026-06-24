import 'dart:async';

import 'package:flutter/widgets.dart';

import 'restage_spring.dart';

/// Fades [child] in (optionally rising into place) when it first appears.
///
/// The simplest, most discoverable entrance: the single most common pattern,
/// named so a developer finds it immediately. It is curve-based, not
/// spring-based — opacity has no visible overshoot, so a spring buys nothing
/// for a fade. For a spring-physics entrance (scale/offset that overshoots and
/// settles), use [RestageMotion].
///
/// The animation controller lives inside this compiled widget; a paywall blob
/// carries only the declarative values (duration, curve, from-state, delay) and
/// the child.
class RestageFadeIn extends StatefulWidget {
  /// Creates a fade-in entrance for [child].
  const RestageFadeIn({
    super.key,
    required this.child,
    this.duration,
    this.curve = Curves.easeOut,
    this.fromOpacity = 0.0,
    this.fromOffset = Offset.zero,
    this.delay,
    this.onEnd,
  });

  /// The default fade duration when [duration] is null.
  static const Duration defaultDuration = Duration(milliseconds: 300);

  /// The widget that fades in.
  final Widget child;

  /// How long the fade takes. Null uses [defaultDuration] (300ms).
  final Duration? duration;

  /// The easing of the fade. Defaults to [Curves.easeOut].
  final Curve curve;

  /// The opacity the child fades from. Defaults to `0.0` (fully transparent).
  final double fromOpacity;

  /// The translation (in logical pixels) the child rises from. `Offset.zero`
  /// (the default) means a pure fade; e.g. `Offset(0, 16)` fades + rises.
  final Offset fromOffset;

  /// How long to wait after mount before the fade starts. Null means no delay.
  final Duration? delay;

  /// Fires once when the fade settles. Never fires if the widget is disposed
  /// before settling.
  final VoidCallback? onEnd;

  @override
  State<RestageFadeIn> createState() => _RestageFadeInState();
}

class _RestageFadeInState extends State<RestageFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: sanitizeMotionDuration(
      widget.duration,
      fallback: RestageFadeIn.defaultDuration,
    ),
  );
  late final Animation<double> _t =
      CurvedAnimation(parent: _controller, curve: widget.curve);
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
    _controller.forward().orCancel.then(
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
      animation: _t,
      builder: (context, child) {
        final t = _t.value;
        var result = child!;
        // Guard the value handed to each render primitive to be finite, so no
        // wire input renders garbage — whether non-finite directly, or a finite
        // extreme that overflows during interpolation under an overshooting
        // curve. A non-finite value falls back to the identity.
        if (widget.fromOffset != Offset.zero) {
          final offset = widget.fromOffset * (1 - t);
          result = Transform.translate(
            offset: offset.isFinite ? offset : Offset.zero,
            child: result,
          );
        }
        final opacity =
            (widget.fromOpacity + (1 - widget.fromOpacity) * t).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity.isFinite ? opacity : 1.0,
          child: result,
        );
      },
      child: widget.child,
    );
  }
}
