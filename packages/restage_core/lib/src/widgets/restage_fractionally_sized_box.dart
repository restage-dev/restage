import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'restage_shifted_box.dart';

/// Sizes and aligns [child] using fractions of the incoming maximum dimensions.
/// Null factors and calculations that produce non-finite sizes pass the incoming
/// constraints through on that axis. [alignment] positions the child.
class RestageFractionallySizedBox extends SingleChildRenderObjectWidget {
  /// Creates a widget that sizes its child to a fraction of the available
  /// space.
  ///
  /// If non-null, [widthFactor] and [heightFactor] must be non-negative.
  const RestageFractionallySizedBox({
    super.key,
    this.alignment = Alignment.center,
    this.widthFactor,
    this.heightFactor,
    super.child,
  })  : assert(widthFactor == null || widthFactor >= 0.0),
        assert(heightFactor == null || heightFactor >= 0.0);

  /// The fraction of the incoming maximum width given to the child.
  ///
  /// A null value passes the incoming width constraints through unchanged.
  final double? widthFactor;

  /// The fraction of the incoming maximum height given to the child.
  ///
  /// A null value passes the incoming height constraints through unchanged.
  final double? heightFactor;

  /// How to align the child within this box.
  final AlignmentGeometry alignment;

  @override
  RenderFractionallySizedOverflowBox createRenderObject(BuildContext context) {
    return _RenderRestageFractionallySizedBox(
      alignment: alignment,
      widthFactor: widthFactor,
      heightFactor: heightFactor,
      textDirection: Directionality.maybeOf(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFractionallySizedOverflowBox renderObject,
  ) {
    renderObject
      ..alignment = alignment
      ..widthFactor = widthFactor
      ..heightFactor = heightFactor
      ..textDirection = Directionality.maybeOf(context);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<AlignmentGeometry>('alignment', alignment),
    );
    properties.add(
      DoubleProperty('widthFactor', widthFactor, defaultValue: null),
    );
    properties.add(
      DoubleProperty('heightFactor', heightFactor, defaultValue: null),
    );
  }
}

class _RenderRestageFractionallySizedBox
    extends RenderFractionallySizedOverflowBox with RestageAlignedShiftedBox {
  _RenderRestageFractionallySizedBox({
    required super.alignment,
    super.widthFactor,
    super.heightFactor,
    super.textDirection,
  });

  BoxConstraints _getInnerConstraints(BoxConstraints constraints) {
    double minWidth = constraints.minWidth;
    double maxWidth = constraints.maxWidth;
    if (widthFactor != null) {
      final double width = maxWidth * widthFactor!;
      if (width.isFinite) {
        minWidth = width;
        maxWidth = width;
      }
    }
    double minHeight = constraints.minHeight;
    double maxHeight = constraints.maxHeight;
    if (heightFactor != null) {
      final double height = maxHeight * heightFactor!;
      if (height.isFinite) {
        minHeight = height;
        maxHeight = height;
      }
    }
    return BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
    );
  }

  double _intrinsicArgument(double value, double factor) {
    final double result = value * factor;
    return result.isNaN ? value : result;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    if (child == null) {
      final double width = super.computeMinIntrinsicWidth(height);
      return width.isFinite ? width : 0.0;
    }
    final double result = child!.getMinIntrinsicWidth(
      _intrinsicArgument(height, heightFactor ?? 1.0),
    );
    assert(result.isFinite);
    final double width = result / (widthFactor ?? 1.0);
    return width.isFinite ? width : result;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    if (child == null) {
      final double width = super.computeMaxIntrinsicWidth(height);
      return width.isFinite ? width : 0.0;
    }
    final double result = child!.getMaxIntrinsicWidth(
      _intrinsicArgument(height, heightFactor ?? 1.0),
    );
    assert(result.isFinite);
    final double width = result / (widthFactor ?? 1.0);
    return width.isFinite ? width : result;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    if (child == null) {
      final double height = super.computeMinIntrinsicHeight(width);
      return height.isFinite ? height : 0.0;
    }
    final double result = child!.getMinIntrinsicHeight(
      _intrinsicArgument(width, widthFactor ?? 1.0),
    );
    assert(result.isFinite);
    final double height = result / (heightFactor ?? 1.0);
    return height.isFinite ? height : result;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    if (child == null) {
      final double height = super.computeMaxIntrinsicHeight(width);
      return height.isFinite ? height : 0.0;
    }
    final double result = child!.getMaxIntrinsicHeight(
      _intrinsicArgument(width, widthFactor ?? 1.0),
    );
    assert(result.isFinite);
    final double height = result / (heightFactor ?? 1.0);
    return height.isFinite ? height : result;
  }

  @override
  @protected
  Size computeDryLayout(covariant BoxConstraints constraints) {
    if (child != null) {
      final Size childSize = child!.getDryLayout(
        _getInnerConstraints(constraints),
      );
      return constraints.constrain(childSize);
    }
    return constraints.constrain(
      _getInnerConstraints(constraints).constrain(Size.zero),
    );
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final RenderBox? child = this.child;
    if (child == null) {
      return null;
    }
    final BoxConstraints childConstraints = _getInnerConstraints(constraints);
    final double? result = child.getDryBaseline(childConstraints, baseline);
    if (result == null) {
      return null;
    }
    final Size childSize = child.getDryLayout(childConstraints);
    final Size size = getDryLayout(constraints);
    final double alignedBaseline =
        result + resolvedAlignment.alongOffset(size - childSize as Offset).dy;
    return alignedBaseline.isFinite ? alignedBaseline : null;
  }

  @override
  void performLayout() {
    if (child != null) {
      child!.layout(
        _getInnerConstraints(constraints),
        parentUsesSize: true,
      );
      size = constraints.constrain(child!.size);
      alignChild();
    } else {
      size = constraints.constrain(
        _getInnerConstraints(constraints).constrain(Size.zero),
      );
    }
  }
}
