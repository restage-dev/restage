import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [FittedBox] that keeps derived layout geometry finite.
class RestageFittedBox extends FittedBox {
  /// Creates a widget that scales and positions its child within itself.
  const RestageFittedBox({
    super.key,
    super.fit = BoxFit.contain,
    super.alignment = Alignment.center,
    super.clipBehavior = Clip.none,
    super.child,
  });

  @override
  RenderFittedBox createRenderObject(BuildContext context) =>
      _RenderRestageFittedBox(
        fit: fit,
        alignment: alignment,
        textDirection: Directionality.maybeOf(context),
        clipBehavior: clipBehavior,
      );
}

class _FittedBoxConstraints extends BoxConstraints {
  _FittedBoxConstraints.from(BoxConstraints source)
      : super(
          minWidth: source.minWidth,
          maxWidth: source.maxWidth,
          minHeight: source.minHeight,
          maxHeight: source.maxHeight,
        );

  @override
  Size constrainSizeAndAttemptToPreserveAspectRatio(Size size) {
    final native = super.constrainSizeAndAttemptToPreserveAspectRatio(size);
    if (native.isFinite) {
      return native;
    }
    final fallback = super.constrain(size);
    if (!fallback.isFinite) {
      throw FlutterError(
        'FittedBox cannot produce finite geometry under expanding constraints.',
      );
    }
    return fallback;
  }

  @override
  _FittedBoxConstraints loosen() => _FittedBoxConstraints.from(super.loosen());
}

class _RenderRestageFittedBox extends RenderFittedBox {
  _RenderRestageFittedBox({
    required super.fit,
    required super.alignment,
    super.textDirection,
    super.clipBehavior,
  });

  BoxConstraints _wrap(BoxConstraints value) =>
      _FittedBoxConstraints.from(value);

  @override
  BoxConstraints get constraints => _wrap(super.constraints);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      super.computeDryLayout(_wrap(constraints));
}
