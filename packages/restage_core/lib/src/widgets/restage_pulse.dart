import 'package:flutter/widgets.dart';

import 'restage_spring.dart';

/// Continuously pulses [child] between [minScale] and [maxScale] to draw
/// attention — a subtle "breathing" effect for a call-to-action.
///
/// This is the one motion widget that loops: unlike the implicit `Animated*`
/// widgets (which run once per property change) and the entrance widgets (which
/// run once on appear), the pulse repeats indefinitely until the widget is
/// disposed. It is tween-based, not spring-based — a smooth, even oscillation
/// rather than a physical settle.
///
/// The animation controller lives inside this compiled widget; a paywall blob
/// carries only the scale range, the period, and the child.
class RestagePulse extends StatefulWidget {
  /// Creates a looping pulse around [child].
  const RestagePulse({
    super.key,
    required this.child,
    this.minScale = 0.97,
    this.maxScale = 1.03,
    this.period,
    this.curve = Curves.easeInOut,
  });

  /// The default sweep duration when [period] is null.
  static const Duration defaultPeriod = Duration(milliseconds: 1200);

  /// The widget that pulses.
  final Widget child;

  /// The smallest scale in the pulse. Defaults to a subtle `0.97`.
  final double minScale;

  /// The largest scale in the pulse. Defaults to a subtle `1.03`.
  final double maxScale;

  /// The duration of a single sweep between [minScale] and [maxScale]; a full
  /// pulse (out and back) takes two sweeps. Null uses [defaultPeriod] (1200ms).
  final Duration? period;

  /// The easing of each sweep. Defaults to [Curves.easeInOut].
  final Curve curve;

  @override
  State<RestagePulse> createState() => _RestagePulseState();
}

class _RestagePulseState extends State<RestagePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: sanitizeMotionDuration(
      widget.period,
      fallback: RestagePulse.defaultPeriod,
    ),
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween<double>(
    begin: widget.minScale,
    end: widget.maxScale,
  ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // An AnimatedBuilder (rather than ScaleTransition) so the scale handed to
    // Transform is guarded finite — a NaN/Infinity wire scale bound, or a
    // finite extreme, otherwise renders garbage. A non-finite value falls back
    // to the identity.
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) {
        final scale = _scale.value;
        return Transform.scale(
          scale: scale.isFinite ? scale : 1.0,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
