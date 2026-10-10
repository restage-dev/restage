// Copyright 2014 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Portions adapted from Flutter 3.47.0 rendering/shifted_box.dart and
// widgets/implicit_animations.dart.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

@internal
(double, double) restageSafeInsetAxis(double first, double second) {
  final double a = first.isFinite && first > 0.0 ? first : 0.0;
  final double b = second.isFinite && second > 0.0 ? second : 0.0;
  return (a + b).isFinite ? (a, b) : (0.0, 0.0);
}

@internal
EdgeInsets restageSafePhysicalInsets(EdgeInsets resolved) {
  final horizontal = restageSafeInsetAxis(resolved.left, resolved.right);
  final vertical = restageSafeInsetAxis(resolved.top, resolved.bottom);
  if (horizontal == (resolved.left, resolved.right) &&
      vertical == (resolved.top, resolved.bottom)) {
    return resolved;
  }
  return EdgeInsets.fromLTRB(
    horizontal.$1,
    vertical.$1,
    horizontal.$2,
    vertical.$2,
  );
}

@internal
EdgeInsetsGeometry restageSafeResolvedInsets(
  EdgeInsetsGeometry source,
  TextDirection? textDirection,
) {
  final EdgeInsets resolved = source.resolve(textDirection);
  final EdgeInsets repaired = restageSafePhysicalInsets(resolved);
  return identical(repaired, resolved) ? source : repaired;
}

@internal
EdgeInsetsGeometry restageRepairPoisonedInsetBegin(
  EdgeInsetsGeometry source,
) {
  if (source case final EdgeInsetsDirectional value) {
    if (value.start.isFinite &&
        value.top.isFinite &&
        value.end.isFinite &&
        value.bottom.isFinite) {
      return source;
    }
    final horizontal = restageSafeInsetAxis(value.start, value.end);
    final vertical = restageSafeInsetAxis(value.top, value.bottom);
    return EdgeInsetsDirectional.fromSTEB(
      horizontal.$1,
      vertical.$1,
      horizontal.$2,
      vertical.$2,
    );
  }
  if (source case final EdgeInsets value) {
    if (value.left.isFinite &&
        value.top.isFinite &&
        value.right.isFinite &&
        value.bottom.isFinite) {
      return source;
    }
    final horizontal = restageSafeInsetAxis(value.left, value.right);
    final vertical = restageSafeInsetAxis(value.top, value.bottom);
    return EdgeInsets.fromLTRB(
      horizontal.$1,
      vertical.$1,
      horizontal.$2,
      vertical.$2,
    );
  }
  return source;
}

/// A [Padding] that keeps its consumed layout geometry finite.
class RestagePadding extends Padding {
  /// Creates a guarded padding widget.
  const RestagePadding({required super.padding, super.child, super.key});

  @override
  RenderPadding createRenderObject(BuildContext context) =>
      _RestageRenderPadding(
        padding: restageSafeResolvedInsets(
          padding,
          Directionality.maybeOf(context),
        ),
        textDirection: Directionality.maybeOf(context),
      );

  @override
  void updateRenderObject(BuildContext context, RenderPadding renderObject) {
    final TextDirection? textDirection = Directionality.maybeOf(context);
    renderObject
      ..padding = restageSafeResolvedInsets(padding, textDirection)
      ..textDirection = textDirection;
  }
}

class _RestageRenderPadding extends RenderPadding {
  _RestageRenderPadding({
    required super.padding,
    super.textDirection,
  });

  EdgeInsets get _resolved => padding.resolve(textDirection);

  Never _fail() =>
      throw FlutterError('Padding cannot produce finite geometry.');

  double _intrinsic(double childResult, double additiveInset) {
    final double result = childResult + additiveInset;
    if (result.isFinite) return result;
    return childResult.isFinite ? childResult : _fail();
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final EdgeInsets insets = _resolved;
    final RenderBox? child = this.child;
    if (child == null) return insets.horizontal;
    return _intrinsic(
      child.getMinIntrinsicWidth(math.max(0.0, height - insets.vertical)),
      insets.horizontal,
    );
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final EdgeInsets insets = _resolved;
    final RenderBox? child = this.child;
    if (child == null) return insets.horizontal;
    return _intrinsic(
      child.getMaxIntrinsicWidth(math.max(0.0, height - insets.vertical)),
      insets.horizontal,
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final EdgeInsets insets = _resolved;
    final RenderBox? child = this.child;
    if (child == null) return insets.vertical;
    return _intrinsic(
      child.getMinIntrinsicHeight(math.max(0.0, width - insets.horizontal)),
      insets.vertical,
    );
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final EdgeInsets insets = _resolved;
    final RenderBox? child = this.child;
    if (child == null) return insets.vertical;
    return _intrinsic(
      child.getMaxIntrinsicHeight(math.max(0.0, width - insets.horizontal)),
      insets.vertical,
    );
  }

  Size _finiteSize(
    Size result,
    BoxConstraints constraints,
    Size? childSize,
  ) {
    if (result.isFinite) return result;
    if (childSize == null || !childSize.isFinite) return _fail();
    final Size repaired = Size(
      result.width.isFinite
          ? result.width
          : constraints.constrainWidth(childSize.width),
      result.height.isFinite
          ? result.height
          : constraints.constrainHeight(childSize.height),
    );
    return repaired.isFinite ? repaired : _fail();
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final EdgeInsets insets = _resolved;
    final RenderBox? child = this.child;
    if (child == null) {
      return constraints.constrain(
        Size(insets.horizontal, insets.vertical),
      );
    }
    final BoxConstraints innerConstraints = constraints.deflate(insets);
    final Size childSize = child.getDryLayout(innerConstraints);
    final Size result = constraints.constrain(
      Size(
        insets.horizontal + childSize.width,
        insets.vertical + childSize.height,
      ),
    );
    return _finiteSize(result, constraints, childSize);
  }

  @override
  set size(Size value) =>
      super.size = _finiteSize(value, constraints, child?.size);

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final RenderBox? child = this.child;
    if (child == null) return null;
    final EdgeInsets insets = _resolved;
    final double? childBaseline = child.getDryBaseline(
      constraints.deflate(insets),
      baseline,
    );
    if (childBaseline == null) return null;
    final double result = childBaseline + insets.top;
    return result.isFinite ? result : null;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final double? result = super.computeDistanceToActualBaseline(baseline);
    return result == null || result.isFinite ? result : null;
  }
}

/// An [AnimatedPadding] that keeps interpolated inset geometry finite.
class RestageAnimatedPadding extends AnimatedPadding {
  /// Creates a guarded implicitly animated padding widget.
  RestageAnimatedPadding({
    super.key,
    required super.padding,
    super.child,
    super.curve,
    required super.duration,
    super.onEnd,
  });

  @override
  AnimatedWidgetBaseState<AnimatedPadding> createState() =>
      _RestageAnimatedPaddingState();
}

class _RestageAnimatedPaddingState
    extends AnimatedWidgetBaseState<AnimatedPadding> {
  EdgeInsetsGeometryTween? _padding;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _padding = visitor(
      _padding,
      widget.padding,
      (dynamic value) =>
          EdgeInsetsGeometryTween(begin: value as EdgeInsetsGeometry),
    ) as EdgeInsetsGeometryTween?;
  }

  @override
  void didUpdateWidget(AnimatedPadding oldWidget) {
    super.didUpdateWidget(oldWidget);
    final EdgeInsetsGeometry? begin = _padding?.begin;
    if (begin == null) return;
    final EdgeInsetsGeometry repaired = restageRepairPoisonedInsetBegin(begin);
    if (!identical(begin, repaired)) _padding!.begin = repaired;
  }

  @override
  Widget build(BuildContext context) => RestagePadding(
        padding: _padding!.evaluate(animation).clamp(
              EdgeInsets.zero,
              EdgeInsetsGeometry.infinity,
            ),
        child: widget.child,
      );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder description) {
    super.debugFillProperties(description);
    description.add(
      DiagnosticsProperty<EdgeInsetsGeometryTween>(
        'padding',
        _padding,
        defaultValue: null,
      ),
    );
  }
}
