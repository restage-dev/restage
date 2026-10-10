// Copyright 2014 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Dry baseline run positioning adapted from Flutter 3.47.0 rendering/wrap.dart.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [Wrap] that keeps derived sizes and positions representable.
class RestageWrap extends Wrap {
  /// Creates a wrap layout.
  const RestageWrap({
    super.key,
    super.direction,
    super.alignment,
    super.spacing,
    super.runAlignment,
    super.runSpacing,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.clipBehavior,
    super.children,
  });

  @override
  RenderWrap createRenderObject(BuildContext context) => _RenderRestageWrap(
        direction: direction,
        alignment: alignment,
        spacing: spacing,
        runAlignment: runAlignment,
        runSpacing: runSpacing,
        crossAxisAlignment: crossAxisAlignment,
        textDirection: textDirection ?? Directionality.maybeOf(context),
        verticalDirection: verticalDirection,
        clipBehavior: clipBehavior,
      );
}

class _NonFiniteWrapGeometry implements Exception {
  const _NonFiniteWrapGeometry(this.badX, this.badY);

  final bool badX;
  final bool badY;
}

class _FiniteWrapParentData extends WrapParentData {
  @override
  set offset(Offset value) {
    if (!value.isFinite) {
      throw _NonFiniteWrapGeometry(
        !value.dx.isFinite,
        !value.dy.isFinite,
      );
    }
    super.offset = value;
  }
}

class _WrapRun {
  _WrapRun(this.leadingChild, this.main, this.cross);

  RenderBox leadingChild;
  double main;
  double cross;
  int childCount = 1;
}

class _RenderRestageWrap extends RenderWrap {
  _RenderRestageWrap({
    super.direction,
    super.alignment,
    super.spacing,
    super.runAlignment,
    super.runSpacing,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.clipBehavior,
  });

  bool _zeroSpacing = false;
  bool _zeroRunSpacing = false;

  @override
  double get spacing => _zeroSpacing ? 0 : super.spacing;

  @override
  double get runSpacing => _zeroRunSpacing ? 0 : super.runSpacing;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FiniteWrapParentData) {
      child.parentData = _FiniteWrapParentData();
    }
  }

  @override
  set size(Size value) {
    if (!value.isFinite) {
      throw _NonFiniteWrapGeometry(
        !value.width.isFinite,
        !value.height.isFinite,
      );
    }
    super.size = value;
  }

  bool _selectFallback(_NonFiniteWrapGeometry failure) {
    final bool badMain =
        direction == Axis.horizontal ? failure.badX : failure.badY;
    final bool badCross =
        direction == Axis.horizontal ? failure.badY : failure.badX;
    if (badMain && !_zeroSpacing && super.spacing != 0) {
      _zeroSpacing = true;
      return true;
    }
    if (badCross && !_zeroRunSpacing && super.runSpacing != 0) {
      _zeroRunSpacing = true;
      return true;
    }
    if (badCross && !_zeroSpacing && super.spacing != 0) {
      _zeroSpacing = true;
      return true;
    }
    return false;
  }

  Never _fail() => throw FlutterError('Wrap cannot produce finite geometry.');

  void _clearFallbacks() {
    _zeroSpacing = false;
    _zeroRunSpacing = false;
  }

  @override
  void performLayout() {
    try {
      super.performLayout();
    } on _NonFiniteWrapGeometry catch (first) {
      if (!_selectFallback(first)) _fail();
      try {
        try {
          super.performLayout();
        } on _NonFiniteWrapGeometry catch (second) {
          if (!_selectFallback(second)) _fail();
          try {
            super.performLayout();
          } on _NonFiniteWrapGeometry {
            _fail();
          }
        }
      } finally {
        _clearFallbacks();
      }
    }
  }

  Size _checkedDryLayout(BoxConstraints constraints) {
    final Size value = super.computeDryLayout(constraints);
    if (!value.isFinite) {
      throw _NonFiniteWrapGeometry(
        !value.width.isFinite,
        !value.height.isFinite,
      );
    }
    return value;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    try {
      return _checkedDryLayout(constraints);
    } on _NonFiniteWrapGeometry catch (first) {
      if (!_selectFallback(first)) _fail();
      try {
        try {
          return _checkedDryLayout(constraints);
        } on _NonFiniteWrapGeometry catch (second) {
          if (!_selectFallback(second)) _fail();
          try {
            return _checkedDryLayout(constraints);
          } on _NonFiniteWrapGeometry {
            _fail();
          }
        }
      } finally {
        _clearFallbacks();
      }
    }
  }

  double _finiteIntrinsic(double value) {
    if (!value.isFinite) _fail();
    return value;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _finiteIntrinsic(super.computeMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _finiteIntrinsic(super.computeMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _finiteIntrinsic(super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _finiteIntrinsic(super.computeMaxIntrinsicHeight(width));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final double? value = super.computeDistanceToActualBaseline(baseline);
    return value == null || value.isFinite ? value : null;
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    try {
      return _positionedDryBaseline(constraints, baseline);
    } on _NonFiniteWrapGeometry catch (first) {
      if (!_selectFallback(first)) _fail();
      try {
        try {
          return _positionedDryBaseline(constraints, baseline);
        } on _NonFiniteWrapGeometry catch (second) {
          if (!_selectFallback(second)) _fail();
          try {
            return _positionedDryBaseline(constraints, baseline);
          } on _NonFiniteWrapGeometry {
            _fail();
          }
        }
      } finally {
        _clearFallbacks();
      }
    }
  }

  double _main(Size size) =>
      direction == Axis.horizontal ? size.width : size.height;

  double _cross(Size size) =>
      direction == Axis.horizontal ? size.height : size.width;

  Offset _offset(double main, double cross) =>
      direction == Axis.horizontal ? Offset(main, cross) : Offset(cross, main);

  (bool, bool) get _flippedAxes {
    final bool horizontal = textDirection == TextDirection.rtl;
    final bool vertical = verticalDirection == VerticalDirection.up;
    return direction == Axis.horizontal
        ? (horizontal, vertical)
        : (vertical, horizontal);
  }

  (double, double) _distribute(
    WrapAlignment value,
    double free,
    double itemSpacing,
    int count,
    bool flipped,
  ) =>
      switch (value) {
        WrapAlignment.start => (flipped ? free : 0, itemSpacing),
        WrapAlignment.end => (flipped ? 0 : free, itemSpacing),
        WrapAlignment.center => (free / 2, itemSpacing),
        WrapAlignment.spaceBetween when count < 2 => (
            flipped ? free : 0,
            itemSpacing
          ),
        WrapAlignment.spaceBetween => (0, free / (count - 1) + itemSpacing),
        WrapAlignment.spaceAround => (
            free / count / 2,
            free / count + itemSpacing
          ),
        WrapAlignment.spaceEvenly => (
            free / (count + 1),
            free / (count + 1) + itemSpacing,
          ),
      };

  double? _positionedDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    if (firstChild == null) return null;
    final BoxConstraints childConstraints = direction == Axis.horizontal
        ? BoxConstraints(maxWidth: constraints.maxWidth)
        : BoxConstraints(maxHeight: constraints.maxHeight);
    final double mainLimit = direction == Axis.horizontal
        ? constraints.maxWidth
        : constraints.maxHeight;
    final (bool flipMain, bool flipCross) = _flippedAxes;
    final runs = <_WrapRun>[];
    _WrapRun? current;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final Size childSize = child.getDryLayout(childConstraints);
      final double childMain = _main(childSize);
      final double childCross = _cross(childSize);
      if (current == null) {
        current = _WrapRun(child, childMain, childCross);
        continue;
      }
      if (current.main + childMain + spacing - mainLimit >
          precisionErrorTolerance) {
        runs.add(current);
        current = _WrapRun(child, childMain, childCross);
      } else {
        current
          ..main += childMain + spacing
          ..cross = math.max(current.cross, childCross)
          ..childCount += 1;
        if (flipMain) current.leadingChild = child;
      }
    }
    runs.add(current!);

    var childrenMain = 0.0;
    var childrenCross = 0.0;
    for (final run in runs.take(runs.length - 1)) {
      childrenMain = math.max(childrenMain, run.main);
      childrenCross += run.cross;
    }
    final _WrapRun lastRun = runs.last;
    childrenMain = math.max(childrenMain, lastRun.main);
    childrenCross += runSpacing * (runs.length - 1) + lastRun.cross;
    final Size childrenSize = direction == Axis.horizontal
        ? Size(childrenMain, childrenCross)
        : Size(childrenCross, childrenMain);
    final Size containerSize = constraints.constrain(childrenSize);
    if (!containerSize.isFinite) {
      throw _NonFiniteWrapGeometry(
        !containerSize.width.isFinite,
        !containerSize.height.isFinite,
      );
    }
    final double containerMain = _main(containerSize);
    final double crossFree = math.max(0, childrenCross);
    final WrapCrossAlignment effectiveCrossAlignment = flipCross
        ? switch (crossAxisAlignment) {
            WrapCrossAlignment.start => WrapCrossAlignment.end,
            WrapCrossAlignment.end => WrapCrossAlignment.start,
            WrapCrossAlignment.center => WrapCrossAlignment.center,
          }
        : crossAxisAlignment;
    final double crossFactor = switch (effectiveCrossAlignment) {
      WrapCrossAlignment.start => 0,
      WrapCrossAlignment.end => 1,
      WrapCrossAlignment.center => 0.5,
    };
    final (double runLeading, double runBetween) = _distribute(
      runAlignment,
      crossFree,
      runSpacing,
      runs.length,
      flipCross,
    );
    final Iterable<_WrapRun> orderedRuns = flipCross ? runs.reversed : runs;
    BaselineOffset result = BaselineOffset.noBaseline;
    var runCross = runLeading;
    for (final run in orderedRuns) {
      final double mainFree = math.max(0, containerMain - run.main);
      final (double childLeading, double childBetween) = _distribute(
        alignment,
        mainFree,
        spacing,
        run.childCount,
        flipMain,
      );
      var childMain = childLeading;
      var remaining = run.childCount;
      for (RenderBox? child = run.leadingChild;
          child != null && remaining > 0;
          child = flipMain ? childBefore(child) : childAfter(child)) {
        final Size childSize = child.getDryLayout(childConstraints);
        final double childCross = _cross(childSize);
        final Offset position = _offset(
          childMain,
          runCross + crossFactor * (run.cross - childCross),
        );
        if (!position.isFinite) {
          throw _NonFiniteWrapGeometry(
            !position.dx.isFinite,
            !position.dy.isFinite,
          );
        }
        result = result.minOf(
          BaselineOffset(child.getDryBaseline(childConstraints, baseline)) +
              position.dy,
        );
        childMain += _main(childSize) + childBetween;
        remaining -= 1;
      }
      runCross += run.cross + runBetween;
    }
    final double? value = result.offset;
    return value == null || value.isFinite ? value : null;
  }
}
