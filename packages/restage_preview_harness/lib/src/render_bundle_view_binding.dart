import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:restage_preview_host/restage_preview_host.dart';

/// Bundle-internal raster-density controller.
///
/// The shell still owns screen-space zoom. This controller only increases the
/// Flutter view's backing density while preserving the frozen logical frame.
abstract interface class RenderBundleRasterController {
  /// Applies [environment.zoom] and completes when the backing metrics match.
  ///
  /// A false result means this target was superseded before it could paint.
  Future<bool> prepare(RenderEnv environment);

  /// Completes any pending target without changing browser or wire state.
  void cancelPending();
}

/// Derives the bundle view used to re-raster a committed shell zoom.
ViewConfiguration renderBundleViewConfiguration(
  ViewConfiguration browserConfiguration, {
  required double zoom,
  Size? frame,
}) {
  if (!zoom.isFinite || zoom <= 0) {
    throw ArgumentError.value(zoom, 'zoom', 'must be positive and finite');
  }
  if (frame == null) {
    if (zoom == 1) return browserConfiguration;
    final effectiveDevicePixelRatio =
        browserConfiguration.devicePixelRatio * zoom;
    return ViewConfiguration(
      physicalConstraints: browserConfiguration.physicalConstraints,
      logicalConstraints:
          browserConfiguration.physicalConstraints / effectiveDevicePixelRatio,
      devicePixelRatio: effectiveDevicePixelRatio,
    );
  }
  if (!frame.width.isFinite ||
      !frame.height.isFinite ||
      frame.width <= 0 ||
      frame.height <= 0) {
    throw ArgumentError.value(frame, 'frame', 'must be finite and positive');
  }
  final effectiveDevicePixelRatio =
      browserConfiguration.devicePixelRatio * zoom;
  if (!effectiveDevicePixelRatio.isFinite || effectiveDevicePixelRatio <= 0) {
    throw ArgumentError.value(
      effectiveDevicePixelRatio,
      'effectiveDevicePixelRatio',
      'must be positive and finite',
    );
  }
  return ViewConfiguration(
    physicalConstraints: BoxConstraints.tightFor(
      width: frame.width * effectiveDevicePixelRatio,
      height: frame.height * effectiveDevicePixelRatio,
    ),
    logicalConstraints: BoxConstraints.tightFor(
      width: frame.width,
      height: frame.height,
    ),
    devicePixelRatio: effectiveDevicePixelRatio,
  );
}

/// Latest-target gate used to prevent settle before resized metrics arrive.
final class RenderBundleViewportGate {
  Completer<bool>? _pending;
  Size? _frame;
  double? _expectedDevicePixelRatio;

  /// Starts one target, superseding any older target.
  Future<bool> begin({
    required Size frame,
    required double zoom,
    required double browserDevicePixelRatio,
  }) {
    if (!zoom.isFinite || zoom <= 0) {
      throw ArgumentError.value(zoom, 'zoom', 'must be positive and finite');
    }
    if (!browserDevicePixelRatio.isFinite || browserDevicePixelRatio <= 0) {
      throw ArgumentError.value(
        browserDevicePixelRatio,
        'browserDevicePixelRatio',
        'must be positive and finite',
      );
    }
    if (!frame.width.isFinite ||
        !frame.height.isFinite ||
        frame.width <= 0 ||
        frame.height <= 0) {
      throw ArgumentError.value(frame, 'frame', 'must be finite and positive');
    }
    final expectedDevicePixelRatio = browserDevicePixelRatio * zoom;
    if (!expectedDevicePixelRatio.isFinite) {
      throw ArgumentError.value(
        expectedDevicePixelRatio,
        'effectiveDevicePixelRatio',
        'must be positive and finite',
      );
    }
    _pending?.complete(false);
    _frame = frame;
    _expectedDevicePixelRatio = expectedDevicePixelRatio;
    final completer = Completer<bool>();
    _pending = completer;
    return completer.future;
  }

  /// Accepts the current target only at the same rounded physical pixels.
  bool accepts(ViewConfiguration configuration) {
    final pending = _pending;
    final frame = _frame;
    final expectedDevicePixelRatio = _expectedDevicePixelRatio;
    if (pending == null ||
        frame == null ||
        expectedDevicePixelRatio == null ||
        pending.isCompleted) {
      return false;
    }
    final constraints = configuration.logicalConstraints;
    final devicePixelRatio = configuration.devicePixelRatio;
    if (!_sameDevicePixelRatio(
          devicePixelRatio,
          expectedDevicePixelRatio,
        ) ||
        !_samePhysicalExtent(
          constraints.minWidth,
          frame.width,
          devicePixelRatio,
        ) ||
        !_samePhysicalExtent(
          constraints.maxWidth,
          frame.width,
          devicePixelRatio,
        ) ||
        !_samePhysicalExtent(
          constraints.minHeight,
          frame.height,
          devicePixelRatio,
        ) ||
        !_samePhysicalExtent(
          constraints.maxHeight,
          frame.height,
          devicePixelRatio,
        )) {
      return false;
    }
    pending.complete(true);
    _pending = null;
    _frame = null;
    _expectedDevicePixelRatio = null;
    return true;
  }

  /// Supersedes any pending target.
  void cancel() {
    _pending?.complete(false);
    _pending = null;
    _frame = null;
    _expectedDevicePixelRatio = null;
  }
}

const _doubleMachineEpsilon = 2.220446049250313e-16;

bool _sameDevicePixelRatio(double actual, double expected) {
  if (!actual.isFinite || !expected.isFinite) return false;
  final magnitude = math.max(1, math.max(actual.abs(), expected.abs()));
  return (actual - expected).abs() <= _doubleMachineEpsilon * magnitude;
}

bool _samePhysicalExtent(
  double actualLogical,
  double targetLogical,
  double devicePixelRatio,
) {
  if (!actualLogical.isFinite ||
      !targetLogical.isFinite ||
      !devicePixelRatio.isFinite ||
      devicePixelRatio <= 0) {
    return false;
  }
  final actualPhysical = actualLogical * devicePixelRatio;
  final targetPhysical = targetLogical * devicePixelRatio;
  if (!actualPhysical.isFinite || !targetPhysical.isFinite) return false;
  if (actualPhysical.round() != targetPhysical.round()) return false;
  final magnitude = math.max(
    1,
    math.max(actualPhysical.abs(), targetPhysical.abs()),
  );
  final roundingSlack = _doubleMachineEpsilon * magnitude;
  return (actualPhysical - targetPhysical).abs() <= 0.5 + roundingSlack;
}

/// Applies bundle-owned view configurations without redispatching platform
/// metric notifications to every [WidgetsBindingObserver].
///
/// This mirrors the render-view update and frame scheduling performed by
/// [RendererBinding.handleMetricsChanged], but is private to a bundle
/// render request. Genuine browser metric events still use the binding
/// override below and notify observers normally.
@visibleForTesting
void applyRenderBundleViewConfigurations({
  required Iterable<RenderView> renderViews,
  required ViewConfiguration Function(RenderView renderView) configurationFor,
  required VoidCallback scheduleForcedFrame,
  required VoidCallback cancelPending,
}) {
  try {
    var forceFrame = false;
    for (final renderView in renderViews) {
      forceFrame = forceFrame || renderView.child != null;
      renderView.configuration = configurationFor(renderView);
    }
    if (forceFrame) scheduleForcedFrame();
  } on Object {
    cancelPending();
    rethrow;
  }
}

/// Production binding installed only by the isolated render-bundle entrypoint.
final class RenderBundleViewBinding extends WidgetsFlutterBinding
    implements RenderBundleRasterController {
  final RenderBundleViewportGate _gate = RenderBundleViewportGate();
  Size? _frame;
  double _zoom = 1;

  @override
  ViewConfiguration createViewConfigurationFor(RenderView renderView) {
    return renderBundleViewConfiguration(
      ViewConfiguration.fromView(renderView.flutterView),
      zoom: _zoom,
      frame: _frame,
    );
  }

  @override
  void handleMetricsChanged() {
    super.handleMetricsChanged();
    _acceptCurrentMetrics();
  }

  @override
  Future<bool> prepare(RenderEnv environment) {
    final browserDevicePixelRatio =
        renderViews.single.flutterView.devicePixelRatio;
    final target = _gate.begin(
      frame: environment.frame,
      zoom: environment.zoom,
      browserDevicePixelRatio: browserDevicePixelRatio,
    );
    _frame = environment.frame;
    _zoom = environment.zoom;
    applyRenderBundleViewConfigurations(
      renderViews: renderViews,
      configurationFor: createViewConfigurationFor,
      scheduleForcedFrame: scheduleForcedFrame,
      cancelPending: _gate.cancel,
    );
    _acceptCurrentMetrics();
    return target;
  }

  void _acceptCurrentMetrics() {
    for (final renderView in renderViews) {
      if (_gate.accepts(renderView.configuration)) return;
    }
  }

  @override
  void cancelPending() => _gate.cancel();
}
