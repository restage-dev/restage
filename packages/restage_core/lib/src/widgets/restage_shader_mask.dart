import 'package:flutter/widgets.dart';

/// Fills or masks [child] with a gradient or a color.
class RestageShaderMask extends StatelessWidget {
  /// Creates a gradient mask or a color filter around [child].
  const RestageShaderMask({
    this.child,
    this.gradient,
    this.color,
    this.rotation = 0,
    this.blendMode = BlendMode.modulate,
    super.key,
  });

  /// The gradient evaluated in the child's bounds.
  final Gradient? gradient;

  /// A solid color filter, used when no gradient is set.
  final Color? color;

  /// The gradient rotation in radians.
  final double rotation;

  /// How the shader or color combines with the child.
  final BlendMode blendMode;

  /// The content to mask.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final fill = gradient;
    if (fill == null) {
      final tint = color;
      return tint == null
          ? child ?? const SizedBox.shrink()
          : ColorFiltered(
              colorFilter: ColorFilter.mode(tint, blendMode),
              child: child,
            );
    }
    final shader = rotation == 0 ? fill : _rotate(fill);
    return ShaderMask(
      blendMode: blendMode,
      shaderCallback: (bounds) => shader.createShader(
        bounds,
        textDirection: Directionality.maybeOf(context),
      ),
      child: child,
    );
  }

  Gradient _rotate(Gradient fill) {
    final transform = GradientRotation(rotation);
    return switch (fill) {
      LinearGradient() => LinearGradient(
          colors: fill.colors,
          stops: fill.stops,
          begin: fill.begin,
          end: fill.end,
          tileMode: fill.tileMode,
          transform: transform,
        ),
      RadialGradient() => RadialGradient(
          colors: fill.colors,
          stops: fill.stops,
          center: fill.center,
          radius: fill.radius,
          focal: fill.focal,
          focalRadius: fill.focalRadius,
          tileMode: fill.tileMode,
          transform: transform,
        ),
      SweepGradient() => SweepGradient(
          colors: fill.colors,
          stops: fill.stops,
          center: fill.center,
          startAngle: fill.startAngle,
          endAngle: fill.endAngle,
          tileMode: fill.tileMode,
          transform: transform,
        ),
      _ => fill,
    };
  }
}
