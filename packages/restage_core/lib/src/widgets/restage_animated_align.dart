// Copyright 2014 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Portions adapted from Flutter 3.47.0 widgets/implicit_animations.dart.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'restage_align.dart';

/// An [AnimatedAlign] that keeps interpolated layout geometry finite.
class RestageAnimatedAlign extends AnimatedAlign {
  /// Creates a widget that implicitly animates its alignment and size factors.
  const RestageAnimatedAlign({
    super.key,
    required super.alignment,
    super.child,
    super.heightFactor,
    super.widthFactor,
    super.curve,
    required super.duration,
    super.onEnd,
  });

  @override
  AnimatedWidgetBaseState<AnimatedAlign> createState() =>
      _RestageAnimatedAlignState();
}

class _RestageAnimatedAlignState
    extends AnimatedWidgetBaseState<AnimatedAlign> {
  AlignmentGeometryTween? _alignment;
  Tween<double>? _heightFactorTween;
  Tween<double>? _widthFactorTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _alignment = visitor(
      _alignment,
      widget.alignment,
      (dynamic value) =>
          AlignmentGeometryTween(begin: value as AlignmentGeometry),
    ) as AlignmentGeometryTween?;
    if (widget.heightFactor != null) {
      _heightFactorTween = visitor(
        _heightFactorTween,
        widget.heightFactor,
        (dynamic value) => Tween<double>(begin: value as double),
      ) as Tween<double>?;
    }
    if (widget.widthFactor != null) {
      _widthFactorTween = visitor(
        _widthFactorTween,
        widget.widthFactor,
        (dynamic value) => Tween<double>(begin: value as double),
      ) as Tween<double>?;
    }
  }

  @override
  void didUpdateWidget(AnimatedAlign oldWidget) {
    super.didUpdateWidget(oldWidget);
    final AlignmentGeometry? begin = _alignment?.begin;
    if (begin is AlignmentDirectional &&
        (!begin.start.isFinite || !begin.y.isFinite)) {
      _alignment!.begin = AlignmentDirectional(
        begin.start.isFinite ? begin.start : 0.0,
        begin.y.isFinite ? begin.y : 0.0,
      );
    }
  }

  double? _factor(Tween<double>? tween) {
    final double? value = tween?.evaluate(animation);
    return value == null || value.isFinite && value >= 0.0 ? value : null;
  }

  @override
  Widget build(BuildContext context) => RestageAlign(
        alignment: _alignment!.evaluate(animation)!,
        heightFactor: _factor(_heightFactorTween),
        widthFactor: _factor(_widthFactorTween),
        child: widget.child,
      );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder description) {
    super.debugFillProperties(description);
    description.add(
      DiagnosticsProperty<AlignmentGeometryTween>(
        'alignment',
        _alignment,
        defaultValue: null,
      ),
    );
    description.add(
      DiagnosticsProperty<Tween<double>>(
        'widthFactor',
        _widthFactorTween,
        defaultValue: null,
      ),
    );
    description.add(
      DiagnosticsProperty<Tween<double>>(
        'heightFactor',
        _heightFactorTween,
        defaultValue: null,
      ),
    );
  }
}
