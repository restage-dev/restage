import 'dart:async' show Stream, StreamController, unawaited;

import 'package:flutter/foundation.dart' show immutable, listEquals, mapEquals;
import 'package:flutter/rendering.dart'
    show MatrixUtils, Offset, Rect, RenderBox, RenderObject, RenderView;
import 'package:flutter/scheduler.dart' show FrameCallback, SchedulerBinding;
import 'document_path_codec.dart';

/// Schedules one callback after the current Flutter frame.
typedef GeometryPostFrameScheduler = void Function(FrameCallback callback);

/// Supplies the render box whose coordinate space defines geometry snapshots.
typedef FrameRenderBoxProvider = RenderBox? Function();

/// One drawn instance of an authored node.
@immutable
final class GeometryInstance {
  /// Create an instance at [rect], optionally naming the [item] it draws.
  const GeometryInstance(this.rect, {this.item});

  /// Frame-relative bounds.
  final Rect rect;

  /// The data item this instance draws, when its marker names one.
  final String? item;

  @override
  bool operator ==(Object other) =>
      other is GeometryInstance && other.rect == rect && other.item == item;

  @override
  int get hashCode => Object.hash(rect, item);

  @override
  String toString() => 'GeometryInstance($rect, item: $item)';
}

/// Tracks marker render boxes and emits changed frame-relative rect snapshots.
///
/// Markers only register their render objects. This registry owns the
/// post-frame sweep so ancestor-driven movement (including transforms and
/// scrolling) is observed without layout or paint hooks on each marker.
final class GeometryRegistry {
  /// Create a registry for one preview frame.
  GeometryRegistry({
    required FrameRenderBoxProvider frameRenderBox,
    GeometryPostFrameScheduler schedulePostFrameCallback =
        _defaultSchedulePostFrameCallback,
  })  : _frameRenderBox = frameRenderBox,
        _schedulePostFrameCallback = schedulePostFrameCallback;

  final FrameRenderBoxProvider _frameRenderBox;
  final GeometryPostFrameScheduler _schedulePostFrameCallback;
  final Map<String, List<_Marker>> _markers = <String, List<_Marker>>{};
  final StreamController<Map<String, Rect>> _snapshots =
      StreamController<Map<String, Rect>>.broadcast(sync: true);
  final StreamController<Map<String, List<GeometryInstance>>> _instances =
      StreamController<Map<String, List<GeometryInstance>>>.broadcast(
    sync: true,
  );

  Map<String, List<GeometryInstance>> _previousInstances =
      const <String, List<GeometryInstance>>{};
  Map<String, Rect> _previousSnapshot = const <String, Rect>{};
  bool _sweepScheduled = false;
  bool _disposed = false;

  /// Changed geometry snapshots, coalesced to at most one per frame; a path
  /// drawn more than once reports its first instance.
  Stream<Map<String, Rect>> get snapshots => _snapshots.stream;

  /// Changed snapshots of every instance of every path, in drawn order.
  Stream<Map<String, List<GeometryInstance>>> get instanceSnapshots =>
      _instances.stream;

  /// Number of currently attached marker paths.
  int get registeredPathCount => _markers.length;

  /// Capture the markers currently laid out in this frame's coordinate space.
  ///
  /// The returned map is immutable. Calling this method does not emit a stream
  /// event; the regular post-frame sweep remains responsible for changed
  /// snapshot notifications.
  Map<String, Rect> capture() {
    if (_disposed) throw StateError('GeometryRegistry is disposed.');
    return Map<String, Rect>.unmodifiable(_firsts(_capture()));
  }

  /// Capture every instance of every path, in drawn order.
  Map<String, List<GeometryInstance>> captureInstances() {
    if (_disposed) throw StateError('GeometryRegistry is disposed.');
    return Map<String, List<GeometryInstance>>.unmodifiable(_capture());
  }

  /// Register [renderBox] as one instance of [path], drawing [item].
  void register(String path, RenderBox renderBox, {String? item}) {
    if (_disposed) throw StateError('GeometryRegistry is disposed.');
    DocumentPathCodec.decode(path);
    final instances = _markers.putIfAbsent(path, () => <_Marker>[]);
    final index =
        instances.indexWhere((marker) => identical(marker.box, renderBox));
    if (index >= 0) {
      if (instances[index].item == item) return;
      instances[index] = _Marker(renderBox, item);
    } else {
      instances.add(_Marker(renderBox, item));
    }
    _ensureSweep();
  }

  /// Unregister [renderBox] when it detaches.
  void unregister(String path, RenderBox renderBox) {
    final instances = _markers[path];
    if (instances == null) return;
    final before = instances.length;
    instances.removeWhere((marker) => identical(marker.box, renderBox));
    if (instances.length == before) return;
    if (instances.isEmpty) _markers.remove(path);
    _ensureSweep();
  }

  /// Scrolls the [index]th drawn instance of [path] into view; false when
  /// there is no such instance.
  bool reveal(String path, {int index = 0}) {
    if (_disposed) return false;
    final instances = _markers[path];
    if (instances == null || index < 0 || index >= instances.length) {
      return false;
    }
    final frame = _frameRenderBox();
    if (frame != null && frame.attached && instances.length > 1) {
      _sortByDrawnOrder(frame);
    }
    final box = instances[index].box;
    if (!box.attached) return false;
    box.showOnScreen();
    _ensureSweep();
    return true;
  }

  /// Stop future sweeps and close the snapshot stream.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _markers.clear();
    unawaited(_snapshots.close());
    unawaited(_instances.close());
  }

  void _ensureSweep() {
    if (_disposed || _sweepScheduled) return;
    _sweepScheduled = true;
    _schedulePostFrameCallback(_onPostFrame);
  }

  void _onPostFrame(Duration _) {
    _sweepScheduled = false;
    if (_disposed) return;
    _sweep();
    if (_markers.isNotEmpty) _ensureSweep();
  }

  void _sweep() {
    final next = _capture();
    if (geometryInstancesEqual(next, _previousInstances)) return;
    final firsts = _firsts(next);
    final firstsChanged = !mapEquals(firsts, _previousSnapshot);
    _previousInstances = Map<String, List<GeometryInstance>>.unmodifiable(next);
    _instances.add(_previousInstances);
    if (!firstsChanged) return;
    final snapshot = Map<String, Rect>.unmodifiable(firsts);
    _previousSnapshot = snapshot;
    _snapshots.add(snapshot);
  }

  Map<String, List<GeometryInstance>> _capture() {
    final frame = _frameRenderBox();
    final next = <String, List<GeometryInstance>>{};
    if (frame == null || !frame.attached) return next;
    if (_markers.values.any((instances) => instances.length > 1)) {
      _sortByDrawnOrder(frame);
    }
    for (final entry in _markers.entries) {
      final instances = <GeometryInstance>[
        for (final marker in entry.value)
          if (marker.box.attached && marker.box.hasSize)
            GeometryInstance(
              geometryBoundsInFrame(marker.box, frame),
              item: marker.item,
            ),
      ];
      if (instances.isNotEmpty) {
        next[entry.key] = List<GeometryInstance>.unmodifiable(instances);
      }
    }
    return next;
  }

  /// Orders each repeated path's instances as a depth-first walk meets them.
  void _sortByDrawnOrder(RenderBox frame) {
    final order = geometryDrawnOrder(frame);
    for (final instances in _markers.values) {
      if (instances.length < 2) continue;
      instances.sort(
        (a, b) => (order[a.box] ?? order.length)
            .compareTo(order[b.box] ?? order.length),
      );
    }
  }
}

/// Logical frame-relative bounds using the render tree's paint transforms.
Rect geometryBoundsInFrame(RenderBox box, RenderObject frame) {
  var transform = box.getTransformTo(frame);
  if (frame is RenderView) {
    final logicalTransform = frame.configuration.toMatrix();
    if (logicalTransform.invert() == 0) {
      throw const FormatException('The Flutter view transform is singular.');
    }
    logicalTransform.multiply(transform);
    transform = logicalTransform;
  }
  return MatrixUtils.transformRect(transform, Offset.zero & box.size);
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

final class _Marker {
  const _Marker(this.box, this.item);

  final RenderBox box;
  final String? item;
}

Map<String, Rect> _firsts(Map<String, List<GeometryInstance>> instances) =>
    <String, Rect>{
      for (final entry in instances.entries) entry.key: entry.value.first.rect,
    };

/// Whether [a] and [b] hold the same instances for the same paths.
bool geometryInstancesEqual(
  Map<String, List<GeometryInstance>>? a,
  Map<String, List<GeometryInstance>>? b,
) {
  if (a == null || b == null) return identical(a, b);
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!listEquals(entry.value, b[entry.key])) return false;
  }
  return true;
}

void _defaultSchedulePostFrameCallback(FrameCallback callback) {
  SchedulerBinding.instance.addPostFrameCallback(callback);
}
