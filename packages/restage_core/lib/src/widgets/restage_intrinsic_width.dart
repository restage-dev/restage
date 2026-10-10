// Copyright 2014 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Portions adapted from Flutter 3.47.0 rendering/proxy_box.dart.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// An [IntrinsicWidth] that keeps requested step arithmetic representable.
///
/// If an optional step cannot produce usable geometry for the current
/// operation, that operation uses the corresponding null-step behavior.
class RestageIntrinsicWidth extends IntrinsicWidth {
  /// Creates a widget that sizes its child to its intrinsic width.
  const RestageIntrinsicWidth({
    super.key,
    super.stepWidth,
    super.stepHeight,
    super.child,
  });

  @override
  RenderIntrinsicWidth createRenderObject(BuildContext context) {
    return _RenderRestageIntrinsicWidth(
      stepWidth: stepWidth == 0.0 ? null : stepWidth,
      stepHeight: stepHeight == 0.0 ? null : stepHeight,
    );
  }
}

class _RenderRestageIntrinsicWidth extends RenderIntrinsicWidth {
  _RenderRestageIntrinsicWidth({super.stepWidth, super.stepHeight});

  double _applyIntrinsicStep(double input, double? step) {
    if (step == null) {
      return input;
    }
    final double quotient = input / step;
    if (!quotient.isFinite) {
      return input;
    }
    final double result = quotient.ceil() * step;
    return result.isFinite ? result : input;
  }

  double? _applyLayoutStep(
    double input,
    double step,
    BoxConstraints constraints, {
    required Axis axis,
    required double? fallback,
  }) {
    final double quotient = input / step;
    if (!quotient.isFinite) {
      return fallback;
    }
    final double result = quotient.ceil() * step;
    if (result.isFinite) {
      return result;
    }
    final BoxConstraints tightened = switch (axis) {
      Axis.horizontal => constraints.tighten(width: result),
      Axis.vertical => constraints.tighten(height: result),
    };
    final (double min, double max) = switch (axis) {
      Axis.horizontal => (tightened.minWidth, tightened.maxWidth),
      Axis.vertical => (tightened.minHeight, tightened.maxHeight),
    };
    return min.isFinite && max.isFinite ? result : fallback;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return getMaxIntrinsicWidth(height);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    if (child == null) {
      return 0.0;
    }
    final double width = child!.getMaxIntrinsicWidth(height);
    return _applyIntrinsicStep(width, stepWidth);
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    if (child == null) {
      return 0.0;
    }
    if (!width.isFinite) {
      width = getMaxIntrinsicWidth(double.infinity);
    }
    assert(width.isFinite);
    final double height = child!.getMinIntrinsicHeight(width);
    return _applyIntrinsicStep(height, stepHeight);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    if (child == null) {
      return 0.0;
    }
    if (!width.isFinite) {
      width = getMaxIntrinsicWidth(double.infinity);
    }
    assert(width.isFinite);
    final double height = child!.getMaxIntrinsicHeight(width);
    return _applyIntrinsicStep(height, stepHeight);
  }

  BoxConstraints _childConstraints(
    RenderBox child,
    BoxConstraints constraints,
  ) {
    double? width;
    if (!constraints.hasTightWidth) {
      final double intrinsicWidth =
          child.getMaxIntrinsicWidth(constraints.maxHeight);
      width = stepWidth == null
          ? intrinsicWidth
          : _applyLayoutStep(
              intrinsicWidth,
              stepWidth!,
              constraints,
              axis: Axis.horizontal,
              fallback: intrinsicWidth,
            );
    }
    final double? height = stepHeight == null
        ? null
        : _applyLayoutStep(
            child.getMaxIntrinsicHeight(constraints.maxWidth),
            stepHeight!,
            constraints,
            axis: Axis.vertical,
            fallback: null,
          );
    return constraints.tighten(width: width, height: height);
  }

  Size _computeSize({
    required ChildLayouter layoutChild,
    required BoxConstraints constraints,
  }) {
    final RenderBox? child = this.child;
    return child == null
        ? constraints.smallest
        : layoutChild(child, _childConstraints(child, constraints));
  }

  @override
  @protected
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return _computeSize(
      layoutChild: ChildLayoutHelper.dryLayoutChild,
      constraints: constraints,
    );
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final RenderBox? child = this.child;
    return child?.getDryBaseline(
      _childConstraints(child, constraints),
      baseline,
    );
  }

  @override
  void performLayout() {
    size = _computeSize(
      layoutChild: ChildLayoutHelper.layoutChild,
      constraints: constraints,
    );
  }
}
