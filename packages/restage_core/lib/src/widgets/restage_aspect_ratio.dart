import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// An [AspectRatio] that rejects non-finite derived geometry.
class RestageAspectRatio extends AspectRatio {
  /// Creates a widget with a specific aspect ratio.
  const RestageAspectRatio({
    super.key,
    required super.aspectRatio,
    super.child,
  });

  @override
  RenderAspectRatio createRenderObject(BuildContext context) =>
      _RenderRestageAspectRatio(aspectRatio: aspectRatio);
}

class _RenderRestageAspectRatio extends RenderAspectRatio {
  _RenderRestageAspectRatio({required super.aspectRatio});

  Never _fail(String operation) =>
      throw FlutterError('AspectRatio produced a non-finite $operation.');

  Size _finiteSize(Size result, String operation) =>
      result.isFinite ? result : _fail(operation);

  double _finiteScalar(double result, String operation) =>
      result.isFinite ? result : _fail(operation);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _finiteSize(super.computeDryLayout(constraints), 'layout size');

  @override
  double computeMinIntrinsicWidth(double height) => _finiteScalar(
        super.computeMinIntrinsicWidth(height),
        'minimum intrinsic width',
      );

  @override
  double computeMaxIntrinsicWidth(double height) => _finiteScalar(
        super.computeMaxIntrinsicWidth(height),
        'maximum intrinsic width',
      );

  @override
  double computeMinIntrinsicHeight(double width) => _finiteScalar(
        super.computeMinIntrinsicHeight(width),
        'minimum intrinsic height',
      );

  @override
  double computeMaxIntrinsicHeight(double width) => _finiteScalar(
        super.computeMaxIntrinsicHeight(width),
        'maximum intrinsic height',
      );
}
