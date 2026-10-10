// Copyright 2014 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Portions adapted from Flutter 3.47.0 widgets/animated_size.dart.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'restage_shifted_box.dart';

/// An [AnimatedSize] that keeps animated layout geometry finite.
class RestageAnimatedSize extends AnimatedSize {
  /// Creates a widget that animates its size to match [child].
  const RestageAnimatedSize({
    super.key,
    super.child,
    super.alignment,
    super.curve,
    required super.duration,
    super.reverseDuration,
    super.clipBehavior,
    super.onEnd,
  });

  @override
  State<AnimatedSize> createState() => _RestageAnimatedSizeState();
}

class _RestageAnimatedSizeState extends State<AnimatedSize>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => _RestageAnimatedSizeRenderObjectWidget(
        alignment: widget.alignment,
        curve: widget.curve,
        duration: widget.duration,
        reverseDuration: widget.reverseDuration,
        vsync: this,
        clipBehavior: widget.clipBehavior,
        onEnd: widget.onEnd,
        child: widget.child,
      );
}

class _RestageAnimatedSizeRenderObjectWidget
    extends SingleChildRenderObjectWidget {
  const _RestageAnimatedSizeRenderObjectWidget({
    super.child,
    this.alignment = Alignment.center,
    this.curve = Curves.linear,
    required this.duration,
    this.reverseDuration,
    required this.vsync,
    this.clipBehavior = Clip.hardEdge,
    this.onEnd,
  });

  final AlignmentGeometry alignment;
  final Curve curve;
  final Duration duration;
  final Duration? reverseDuration;
  final TickerProvider vsync;
  final Clip clipBehavior;
  final VoidCallback? onEnd;

  @override
  _RestageRenderAnimatedSize createRenderObject(BuildContext context) =>
      _RestageRenderAnimatedSize(
        alignment: alignment,
        duration: duration,
        reverseDuration: reverseDuration,
        curve: curve,
        vsync: vsync,
        textDirection: Directionality.maybeOf(context),
        clipBehavior: clipBehavior,
        onEnd: onEnd,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RestageRenderAnimatedSize renderObject,
  ) {
    renderObject
      ..alignment = alignment
      ..duration = duration
      ..reverseDuration = reverseDuration
      ..curve = curve
      ..vsync = vsync
      ..textDirection = Directionality.maybeOf(context)
      ..clipBehavior = clipBehavior
      ..onEnd = onEnd;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<AlignmentGeometry>(
        'alignment',
        alignment,
        defaultValue: Alignment.topCenter,
      ),
    );
    properties
        .add(IntProperty('duration', duration.inMilliseconds, unit: 'ms'));
    properties.add(
      IntProperty(
        'reverseDuration',
        reverseDuration?.inMilliseconds,
        unit: 'ms',
        defaultValue: null,
      ),
    );
  }
}

/// A [RenderAnimatedSize] that keeps final sizes and shifted geometry finite.
class _RestageRenderAnimatedSize extends RenderAnimatedSize
    with RestageAlignedShiftedBox {
  /// Creates a render object that animates its size to match its child.
  _RestageRenderAnimatedSize({
    required super.vsync,
    required super.duration,
    super.reverseDuration,
    super.curve,
    super.alignment,
    super.textDirection,
    super.clipBehavior,
    super.onEnd,
  });

  Size _finiteSize(Size result, BoxConstraints constraints, Size target) {
    final Size repaired = constraints.constrainDimensions(
      result.width.isFinite ? result.width : target.width,
      result.height.isFinite ? result.height : target.height,
    );
    if (!repaired.isFinite) {
      throw FlutterError('AnimatedSize cannot produce a finite layout size.');
    }
    return repaired;
  }

  @override
  set size(Size value) {
    if (value.isFinite) {
      super.size = value;
      return;
    }
    final RenderBox? child = this.child;
    if (child == null || constraints.isTight) {
      throw FlutterError('AnimatedSize cannot produce a finite layout size.');
    }
    super.size = _finiteSize(value, constraints, child.size);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final Size result = super.computeDryLayout(constraints);
    if (result.isFinite) {
      return result;
    }
    final RenderBox? child = this.child;
    if (child == null || constraints.isTight) {
      throw FlutterError('AnimatedSize cannot produce a finite dry size.');
    }
    return _finiteSize(result, constraints, child.getDryLayout(constraints));
  }
}
