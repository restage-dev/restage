// Copyright 2014 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Portions adapted from Flutter 3.47.0 rendering/stack.dart.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'restage_shifted_box.dart';

/// A [Stack] that keeps derived child geometry finite.
class RestageStack extends Stack {
  /// Creates a stack layout widget.
  const RestageStack({
    super.key,
    super.alignment,
    super.textDirection,
    super.fit,
    super.clipBehavior,
    super.children,
  });

  @override
  RenderStack createRenderObject(BuildContext context) => _RestageRenderStack(
        alignment: alignment,
        textDirection: textDirection ?? Directionality.maybeOf(context),
        fit: fit,
        clipBehavior: clipBehavior,
      );
}

class _RestageStackParentData extends StackParentData {
  _RestageStackParentData(this.owner, this.child);

  final _RestageRenderStack owner;
  final RenderBox child;

  double? _finiteOrNull(double? value) =>
      value == null || value.isFinite ? value : null;

  @override
  set left(double? value) => super.left = _finiteOrNull(value);

  @override
  set top(double? value) => super.top = _finiteOrNull(value);

  @override
  set right(double? value) => super.right = _finiteOrNull(value);

  @override
  set bottom(double? value) => super.bottom = _finiteOrNull(value);

  @override
  set width(double? value) => super.width = _finiteOrNull(value);

  @override
  set height(double? value) => super.height = _finiteOrNull(value);

  double? _dimension(
    double stackExtent,
    double? leading,
    double? trailing,
    double? explicitExtent,
  ) {
    if (leading == null || trailing == null) {
      return explicitExtent == null ? null : math.max(0.0, explicitExtent);
    }
    final double result = math.max(0.0, stackExtent - trailing - leading);
    return result.isFinite
        ? result
        : explicitExtent == null
            ? null
            : math.max(0.0, explicitExtent);
  }

  @override
  BoxConstraints positionedChildConstraints(Size stackSize) {
    assert(isPositioned);
    return BoxConstraints.tightFor(
      width: _dimension(stackSize.width, left, right, width),
      height: _dimension(stackSize.height, top, bottom, height),
    );
  }

  @override
  set offset(Offset value) {
    if (value.isFinite) {
      super.offset = value;
      return;
    }
    final Offset fallback = owner.alignedOffset(owner.size, child.size);
    super.offset = Offset(
      value.dx.isFinite ? value.dx : fallback.dx,
      value.dy.isFinite ? value.dy : fallback.dy,
    );
  }
}

class _RestageRenderStack extends RenderStack {
  _RestageRenderStack({
    super.alignment,
    super.textDirection,
    super.fit,
    super.clipBehavior,
  });

  bool _hasRepairedVisualOverflow = false;
  final LayerHandle<ClipRectLayer> _clipRectLayer =
      LayerHandle<ClipRectLayer>();

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RestageStackParentData) {
      child.parentData = _RestageStackParentData(this, child);
    }
  }

  Offset alignedOffset(Size stackSize, Size childSize) =>
      RestageResolvedAlignment(alignment.resolve(textDirection))
          .alongOffset(stackSize - childSize as Offset);

  @override
  void performLayout() {
    super.performLayout();
    _hasRepairedVisualOverflow = false;
    for (RenderBox? child = firstChild;
        child != null;
        child = childAfter(child)) {
      final parentData = child.parentData! as StackParentData;
      if (parentData.isPositioned) {
        final Offset offset = parentData.offset;
        _hasRepairedVisualOverflow = _hasRepairedVisualOverflow ||
            offset.dx < 0.0 ||
            offset.dx + child.size.width > size.width ||
            offset.dy < 0.0 ||
            offset.dy + child.size.height > size.height;
      }
    }
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final double? result = super.computeDistanceToActualBaseline(baseline);
    return result == null || result.isFinite ? result : null;
  }

  double? _dryBaselineForChild(
    RenderBox child,
    Size stackSize,
    BoxConstraints nonPositionedConstraints,
    TextBaseline baseline,
  ) {
    final parentData = child.parentData! as StackParentData;
    final BoxConstraints childConstraints = parentData.isPositioned
        ? parentData.positionedChildConstraints(stackSize)
        : nonPositionedConstraints;
    final double? childBaseline =
        child.getDryBaseline(childConstraints, baseline);
    if (childBaseline == null) {
      return null;
    }
    final double y;
    if (parentData.top case final double top?) {
      y = top;
    } else {
      final Size childSize = child.getDryLayout(childConstraints);
      if (parentData.bottom case final double bottom?) {
        final double result = stackSize.height - bottom - childSize.height;
        y = result.isFinite ? result : alignedOffset(stackSize, childSize).dy;
      } else {
        y = alignedOffset(stackSize, childSize).dy;
      }
    }
    return childBaseline + y;
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final BoxConstraints nonPositionedConstraints = switch (fit) {
      StackFit.loose => constraints.loosen(),
      StackFit.expand => BoxConstraints.tight(constraints.biggest),
      StackFit.passthrough => constraints,
    };
    final Size stackSize = getDryLayout(constraints);
    BaselineOffset result = BaselineOffset.noBaseline;
    for (RenderBox? child = firstChild;
        child != null;
        child = childAfter(child)) {
      result = result.minOf(
        BaselineOffset(
          _dryBaselineForChild(
            child,
            stackSize,
            nonPositionedConstraints,
            baseline,
          ),
        ),
      );
    }
    final double? offset = result.offset;
    return offset == null || offset.isFinite ? offset : null;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (clipBehavior != Clip.none && _hasRepairedVisualOverflow) {
      _clipRectLayer.layer = context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        paintStack,
        clipBehavior: clipBehavior,
        oldLayer: _clipRectLayer.layer,
      );
    } else {
      _clipRectLayer.layer = null;
      paintStack(context, offset);
    }
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      clipBehavior != Clip.none && _hasRepairedVisualOverflow
          ? Offset.zero & size
          : null;

  @override
  void dispose() {
    _clipRectLayer.layer = null;
    super.dispose();
  }
}
