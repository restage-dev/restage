// Copyright 2014 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Allocation traversal and dry baseline positioning adapted from Flutter
// 3.47.0 rendering/flex.dart.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [Row] that keeps derived allocations, sizes and positions representable.
class RestageRow extends Row with _RestageFlex {
  /// Creates a horizontal array of children.
  const RestageRow({
    super.key,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.textBaseline,
    super.spacing,
    super.children,
  });
}

/// A [Column] that keeps derived allocations, sizes and positions representable.
class RestageColumn extends Column with _RestageFlex {
  /// Creates a vertical array of children.
  const RestageColumn({
    super.key,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.textBaseline,
    super.spacing,
    super.children,
  });
}

mixin _RestageFlex on Flex {
  @override
  RenderFlex createRenderObject(BuildContext context) => _RenderRestageFlex(
        direction: direction,
        mainAxisAlignment: mainAxisAlignment,
        mainAxisSize: mainAxisSize,
        crossAxisAlignment: crossAxisAlignment,
        textDirection: getEffectiveTextDirection(context),
        verticalDirection: verticalDirection,
        textBaseline: textBaseline,
        clipBehavior: clipBehavior,
        spacing: spacing,
      );
}

class _NonFiniteFlexGeometry implements Exception {
  const _NonFiniteFlexGeometry();
}

class _FiniteFlexParentData extends FlexParentData {
  @override
  set offset(Offset value) {
    if (!value.dx.isFinite || !value.dy.isFinite) {
      throw const _NonFiniteFlexGeometry();
    }
    super.offset = value;
  }
}

class _RenderRestageFlex extends RenderFlex {
  _RenderRestageFlex({
    required super.direction,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.textBaseline,
    super.clipBehavior,
    super.spacing,
  });

  bool _zeroSpacing = false;

  @override
  double get spacing => _zeroSpacing ? 0 : super.spacing;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FiniteFlexParentData) {
      child.parentData = _FiniteFlexParentData();
    }
  }

  @override
  set size(Size value) => super.size = _finiteSize(value);

  Size _finiteSize(Size value) {
    if (!value.isFinite) throw const _NonFiniteFlexGeometry();
    return value;
  }

  double _finiteIntrinsic(double value) {
    if (!value.isFinite) throw const _NonFiniteFlexGeometry();
    return value;
  }

  T _withSpacing<T>(T Function() operation) {
    try {
      return operation();
    } on _NonFiniteFlexGeometry {
      if (spacing == 0 || childCount < 2) {
        throw FlutterError('Flex cannot produce finite geometry.');
      }
      final bool previous = _zeroSpacing;
      _zeroSpacing = true;
      try {
        return operation();
      } on _NonFiniteFlexGeometry {
        throw FlutterError('Flex cannot produce finite geometry.');
      } finally {
        _zeroSpacing = previous;
      }
    }
  }

  int _flex(RenderBox child) => (child.parentData! as FlexParentData).flex ?? 0;

  double _main(Size value) =>
      direction == Axis.horizontal ? value.width : value.height;

  bool get _baselineAligned =>
      direction == Axis.horizontal &&
      crossAxisAlignment == CrossAxisAlignment.baseline;

  BoxConstraints _nonFlexConstraints(BoxConstraints value) {
    final bool stretch = crossAxisAlignment == CrossAxisAlignment.stretch;
    return switch (direction) {
      Axis.horizontal => stretch
          ? BoxConstraints.tightFor(height: value.maxHeight)
          : BoxConstraints(maxHeight: value.maxHeight),
      Axis.vertical => stretch
          ? BoxConstraints.tightFor(width: value.maxWidth)
          : BoxConstraints(maxWidth: value.maxWidth),
    };
  }

  ({int total, RenderBox? first}) _flexState(BoxConstraints constraints) {
    var total = 0;
    RenderBox? first;
    if (_main(constraints.biggest).isFinite) {
      for (var child = firstChild; child != null; child = childAfter(child)) {
        final int flex = _flex(child);
        if (flex > 0) {
          total += flex;
          first ??= child;
        }
      }
    }
    return (total: total, first: first);
  }

  bool _badAllocation(
    double space,
    ({int total, RenderBox? first}) state, {
    required bool baselineHelpers,
  }) {
    final double perFlex = space / state.total;
    var remaining = state.total;
    for (var child = state.first;
        child != null && (baselineHelpers || remaining > 0);
        child = childAfter(child)) {
      final int flex = _flex(child);
      if (baselineHelpers ? flex <= 0 : flex == 0) continue;
      remaining -= flex;
      final double extent = perFlex * flex;
      if (!extent.isFinite || extent < 0) return true;
    }
    return false;
  }

  double _nonFlexMain(BoxConstraints constraints, ChildLayouter layoutChild) {
    var accumulated = spacing * (childCount - 1);
    final bool bounded = _main(constraints.biggest).isFinite;
    final BoxConstraints childConstraints = _nonFlexConstraints(constraints);
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (!bounded || _flex(child) <= 0) {
        accumulated += _main(layoutChild(child, childConstraints));
      }
    }
    return accumulated;
  }

  void _checkAllocation(
    BoxConstraints constraints,
    ChildLayouter layoutChild, {
    bool baselineHelpers = false,
  }) {
    final state = _flexState(constraints);
    final double maxMain = _main(constraints.biggest);
    if (state.first == null ||
        !_badAllocation(maxMain, state, baselineHelpers: baselineHelpers)) {
      return;
    }
    final double space = math.max(
      0.0,
      maxMain - _nonFlexMain(constraints, layoutChild),
    );
    if (_badAllocation(space, state, baselineHelpers: baselineHelpers)) {
      throw FlutterError(
          'Flex cannot produce a finite nonnegative allocation.');
    }
  }

  void _checkCrossIntrinsic(double width, {required bool minimum}) {
    if (!_baselineAligned) return;
    _checkAllocation(BoxConstraints(maxWidth: width), (child, constraints) {
      final double main = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : child.getMaxIntrinsicWidth(double.infinity);
      return Size(
        main,
        minimum
            ? child.getMinIntrinsicHeight(main)
            : child.getMaxIntrinsicHeight(main),
      );
    });
  }

  @override
  void performLayout() => _withSpacing(() {
        _checkAllocation(constraints, ChildLayoutHelper.layoutChild);
        super.performLayout();
      });

  @override
  Size computeDryLayout(BoxConstraints constraints) => _withSpacing(() {
        _checkAllocation(constraints, ChildLayoutHelper.dryLayoutChild);
        return _finiteSize(super.computeDryLayout(constraints));
      });

  @override
  double computeMinIntrinsicWidth(double height) => _withSpacing(
        () => _finiteIntrinsic(super.computeMinIntrinsicWidth(height)),
      );

  @override
  double computeMaxIntrinsicWidth(double height) => _withSpacing(
        () => _finiteIntrinsic(super.computeMaxIntrinsicWidth(height)),
      );

  @override
  double computeMinIntrinsicHeight(double width) => _withSpacing(() {
        _checkCrossIntrinsic(width, minimum: true);
        return _finiteIntrinsic(super.computeMinIntrinsicHeight(width));
      });

  @override
  double computeMaxIntrinsicHeight(double width) => _withSpacing(() {
        _checkCrossIntrinsic(width, minimum: false);
        return _finiteIntrinsic(super.computeMaxIntrinsicHeight(width));
      });

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final double? value = super.computeDistanceToActualBaseline(baseline);
    return value == null || value.isFinite ? value : null;
  }

  @override
  double? computeDryBaseline(
          BoxConstraints constraints, TextBaseline baseline) =>
      _withSpacing(() {
        _checkAllocation(constraints, ChildLayoutHelper.dryLayoutChild);
        // This is the identical sizing prefix used by native dry baseline.
        final Size raw = _finiteSize(super.computeDryLayout(constraints));
        if (!_baselineAligned) {
          _checkAllocation(
            constraints,
            ChildLayoutHelper.dryLayoutChild,
            baselineHelpers: true,
          );
        }
        final double? value =
            _positionedDryBaseline(constraints, baseline, _main(raw));
        return value == null || value.isFinite ? value : null;
      });

  double? _horizontalDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
    Map<RenderBox, BoxConstraints> finalConstraints,
  ) {
    final double? value = super.computeDryBaseline(constraints, baseline);
    if (_baselineAligned && value != null) {
      // Only use constraints constructed by the native sizing traversal.
      for (final entry in finalConstraints.entries) {
        final double? childBaseline =
            entry.key.getDryBaseline(entry.value, textBaseline!);
        if (childBaseline != null && !(value - childBaseline).isFinite) {
          throw const _NonFiniteFlexGeometry();
        }
      }
    }
    return value;
  }

  BoxConstraints _flexConstraints(
    RenderBox child,
    BoxConstraints constraints,
    double extent,
  ) {
    final data = child.parentData! as FlexParentData;
    final bool stretch = crossAxisAlignment == CrossAxisAlignment.stretch;
    final double minimum =
        (data.fit ?? FlexFit.tight) == FlexFit.tight ? extent : 0;
    if (direction == Axis.horizontal) {
      return BoxConstraints(
        minWidth: minimum,
        maxWidth: extent,
        minHeight: stretch ? constraints.maxHeight : 0,
        maxHeight: constraints.maxHeight,
      );
    }
    return BoxConstraints(
      minWidth: stretch ? constraints.maxWidth : 0,
      maxWidth: constraints.maxWidth,
      minHeight: minimum,
      maxHeight: extent,
    );
  }

  double? _positionedDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
    double mainSize,
  ) {
    final state = _flexState(constraints);
    final BoxConstraints nonFlex = _nonFlexConstraints(constraints);
    final bool bounded = _main(constraints.biggest).isFinite;
    final finalConstraints = <RenderBox, BoxConstraints>{};
    var accumulated = spacing * (childCount - 1);
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (!bounded || _flex(child) <= 0) {
        finalConstraints[child] = nonFlex;
        accumulated += _main(child.getDryLayout(nonFlex));
      }
    }
    final double? perFlex = state.first == null
        ? null
        : math.max(0.0, _main(constraints.biggest) - accumulated) / state.total;
    var remaining = state.total;
    for (var child = state.first;
        child != null && remaining > 0;
        child = childAfter(child)) {
      final int flex = _flex(child);
      if (flex == 0) continue;
      remaining -= flex;
      final BoxConstraints childConstraints =
          _flexConstraints(child, constraints, perFlex! * flex);
      finalConstraints[child] = childConstraints;
      accumulated += _main(child.getDryLayout(childConstraints));
    }
    if (direction == Axis.horizontal && finalConstraints.length != childCount) {
      return _horizontalDryBaseline(constraints, baseline, finalConstraints);
    }
    BoxConstraints constraintsForChild(RenderBox child) =>
        perFlex != null && _flex(child) > 0
            ? _flexConstraints(child, constraints, _flex(child) * perFlex)
            : nonFlex;

    final double free = math.max(0.0, mainSize - accumulated);
    final bool flipped = firstChild != null &&
        (direction == Axis.horizontal
            ? textDirection == TextDirection.rtl
            : verticalDirection == VerticalDirection.up);
    final (double leading, double between) = switch (mainAxisAlignment) {
      MainAxisAlignment.start => (flipped ? free : 0.0, spacing),
      MainAxisAlignment.end => (flipped ? 0.0 : free, spacing),
      MainAxisAlignment.center => (free / 2.0, spacing),
      MainAxisAlignment.spaceBetween when childCount < 2 => (
          flipped ? free : 0.0,
          spacing
        ),
      MainAxisAlignment.spaceAround when childCount == 0 => (
          flipped ? free : 0.0,
          spacing
        ),
      MainAxisAlignment.spaceBetween => (
          0.0,
          free / (childCount - 1) + spacing
        ),
      MainAxisAlignment.spaceAround => (
          free / childCount / 2,
          free / childCount + spacing
        ),
      MainAxisAlignment.spaceEvenly => (
          free / (childCount + 1),
          free / (childCount + 1) + spacing
        ),
    };
    final positions = <RenderBox, double>{};
    var position = leading;
    for (var child = flipped ? lastChild : firstChild;
        child != null;
        child = flipped ? childBefore(child) : childAfter(child)) {
      if (!position.isFinite) throw const _NonFiniteFlexGeometry();
      positions[child] = position;
      position += _main(child.getDryLayout(direction == Axis.horizontal
              ? finalConstraints[child]!
              : constraintsForChild(child))) +
          between;
    }
    if (direction == Axis.horizontal) {
      return _horizontalDryBaseline(constraints, baseline, finalConstraints);
    }
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final double? value = child.getDryBaseline(
        constraintsForChild(child),
        baseline,
      );
      if (value != null) return value + positions[child]!;
    }
    return null;
  }
}
