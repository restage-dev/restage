// Copyright 2014 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Portions adapted from Flutter 3.47.0 rendering/shifted_box.dart.

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

@internal
class RestageResolvedAlignment extends Alignment {
  RestageResolvedAlignment(this.delegate) : super(delegate.x, delegate.y);

  final Alignment delegate;

  @override
  Offset alongOffset(Offset other) {
    final Offset result = delegate.alongOffset(other);
    if (result.dx.isFinite && result.dy.isFinite) {
      return result;
    }
    final Offset centered = other / 2.0;
    final Offset repaired = Offset(
      result.dx.isFinite ? result.dx : centered.dx,
      result.dy.isFinite ? result.dy : centered.dy,
    );
    if (!repaired.dx.isFinite || !repaired.dy.isFinite) {
      throw FlutterError('Alignment cannot produce a finite child offset.');
    }
    return repaired;
  }
}

@internal
mixin RestageAlignedShiftedBox on RenderAligningShiftedBox {
  @override
  @protected
  Alignment get resolvedAlignment {
    final Alignment value = super.resolvedAlignment;
    return RestageResolvedAlignment(value);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final double? result = super.computeDistanceToActualBaseline(baseline);
    return result == null || result.isFinite ? result : null;
  }
}

@internal
class RestageRenderPositionedBox extends RenderPositionedBox
    with RestageAlignedShiftedBox {
  RestageRenderPositionedBox({
    super.child,
    super.widthFactor,
    super.heightFactor,
    super.alignment,
    super.textDirection,
  });

  Size _finiteSize(
    Size result,
    BoxConstraints constraints,
    Size? childSize,
  ) {
    if (result.isFinite) {
      return result;
    }
    if (childSize == null || !childSize.isFinite) {
      throw FlutterError('Align cannot produce a finite layout size.');
    }
    final Size repaired = Size(
      result.width.isFinite
          ? result.width
          : constraints.constrainWidth(childSize.width),
      result.height.isFinite
          ? result.height
          : constraints.constrainHeight(childSize.height),
    );
    if (!repaired.isFinite) {
      throw FlutterError('Align cannot produce a finite layout size.');
    }
    return repaired;
  }

  @override
  set size(Size value) =>
      super.size = _finiteSize(value, constraints, child?.size);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final Size result = super.computeDryLayout(constraints);
    return result.isFinite
        ? result
        : _finiteSize(
            result,
            constraints,
            child?.getDryLayout(constraints.loosen()),
          );
  }

  double _intrinsic(double value, double? factor) {
    final double result = value * (factor ?? 1.0);
    return result.isFinite ? result : value;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _intrinsic(child?.getMinIntrinsicWidth(height) ?? 0.0, widthFactor);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _intrinsic(child?.getMaxIntrinsicWidth(height) ?? 0.0, widthFactor);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsic(child?.getMinIntrinsicHeight(width) ?? 0.0, heightFactor);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsic(child?.getMaxIntrinsicHeight(width) ?? 0.0, heightFactor);

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final RenderBox? child = this.child;
    if (child == null) {
      return null;
    }
    final BoxConstraints childConstraints = constraints.loosen();
    final double? childBaseline =
        child.getDryBaseline(childConstraints, baseline);
    if (childBaseline == null) {
      return null;
    }
    final Size childSize = child.getDryLayout(childConstraints);
    final Size size = getDryLayout(constraints);
    final double result = childBaseline +
        resolvedAlignment.alongOffset(size - childSize as Offset).dy;
    return result.isFinite ? result : null;
  }
}
