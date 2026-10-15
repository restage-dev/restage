import 'package:flutter/rendering.dart'
    show
        Matrix4,
        MatrixUtils,
        Offset,
        Rect,
        RenderBox,
        RenderObject,
        RenderView;
import 'package:flutter/scheduler.dart' show FrameCallback, SchedulerBinding;

/// Schedules one callback after the current Flutter frame.
typedef GeometryPostFrameScheduler = void Function(FrameCallback callback);

/// Logical frame-relative bounds using the render tree's paint transforms.
Rect geometryBoundsInFrame(RenderBox box, RenderObject frame) =>
    MatrixUtils.transformRect(
      geometryTransformToFrame(box, frame),
      Offset.zero & box.size,
    );

/// The transform from [object] to [frame] in logical pixels.
Matrix4 geometryTransformToFrame(RenderObject object, RenderObject frame) {
  final transform = object.getTransformTo(frame);
  if (frame is! RenderView) return transform;
  final logicalTransform = frame.configuration.toMatrix();
  if (logicalTransform.invert() == 0) {
    throw const FormatException('The Flutter view transform is singular.');
  }
  return logicalTransform..multiply(transform);
}

/// Depth-first render order, retaining every drawn occurrence.
Map<RenderObject, int> geometryDrawnOrder(RenderObject frame) {
  final order = <RenderObject, int>{};
  void visit(RenderObject node) {
    order[node] = order.length;
    node.visitChildren(visit);
  }

  visit(frame);
  return order;
}

/// Resolves a component's render box without inserting a render object.
final class GeometryRenderBoxBinding {
  /// Starts observing the current descendant after each painted frame.
  GeometryRenderBoxBinding({
    required RenderObject? Function() renderObject,
    required void Function(RenderBox? previous, RenderBox? next) onChanged,
    void Function(RenderBox? box)? onFrame,
    GeometryPostFrameScheduler schedulePostFrameCallback =
        _defaultSchedulePostFrameCallback,
  })  : _renderObject = renderObject,
        _onChanged = onChanged,
        _onFrame = onFrame,
        _schedulePostFrameCallback = schedulePostFrameCallback {
    _schedulePostFrameCallback(_resolve);
  }

  final RenderObject? Function() _renderObject;
  final void Function(RenderBox? previous, RenderBox? next) _onChanged;
  final void Function(RenderBox? box)? _onFrame;
  final GeometryPostFrameScheduler _schedulePostFrameCallback;
  RenderBox? _box;
  bool _disposed = false;

  void _resolve(Duration _) {
    if (_disposed) return;
    final candidate = _renderObject();
    final next =
        candidate is RenderBox && candidate.attached ? candidate : null;
    if (!identical(next, _box)) {
      final previous = _box;
      _box = next;
      _onChanged(previous, next);
    }
    _onFrame?.call(next);
    if (!_disposed) _schedulePostFrameCallback(_resolve);
  }

  /// Unregisters the current box and stops observing future frames.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final previous = _box;
    _box = null;
    if (previous != null) _onChanged(previous, null);
  }
}

void _defaultSchedulePostFrameCallback(FrameCallback callback) {
  SchedulerBinding.instance.addPostFrameCallback(callback);
}
