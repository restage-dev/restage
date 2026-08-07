import 'dart:async' show Stream, StreamController, unawaited;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/rendering.dart'
    show MatrixUtils, Offset, Rect, RenderBox;
import 'package:flutter/scheduler.dart' show FrameCallback, SchedulerBinding;
import 'package:restage_preview_host/src/document_path_codec.dart';

/// Schedules one callback after the current Flutter frame.
typedef GeometryPostFrameScheduler = void Function(FrameCallback callback);

/// Supplies the render box whose coordinate space defines geometry snapshots.
typedef FrameRenderBoxProvider = RenderBox? Function();

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
  final Map<String, RenderBox> _markers = <String, RenderBox>{};
  final StreamController<Map<String, Rect>> _snapshots =
      StreamController<Map<String, Rect>>.broadcast(sync: true);

  Map<String, Rect> _previousSnapshot = const <String, Rect>{};
  bool _sweepScheduled = false;
  bool _disposed = false;

  /// Changed geometry snapshots, coalesced to at most one per frame.
  Stream<Map<String, Rect>> get snapshots => _snapshots.stream;

  /// Number of currently attached marker paths.
  int get registeredPathCount => _markers.length;

  /// Capture the markers currently laid out in this frame's coordinate space.
  ///
  /// The returned map is immutable. Calling this method does not emit a stream
  /// event; the regular post-frame sweep remains responsible for changed
  /// snapshot notifications.
  Map<String, Rect> capture() {
    if (_disposed) throw StateError('GeometryRegistry is disposed.');
    return Map<String, Rect>.unmodifiable(_capture());
  }

  /// Register [renderBox] under its compact JSON [path].
  void register(String path, RenderBox renderBox) {
    if (_disposed) throw StateError('GeometryRegistry is disposed.');
    DocumentPathCodec.decode(path);
    final existing = _markers[path];
    if (identical(existing, renderBox)) return;
    if (existing != null) {
      throw StateError('Duplicate geometry marker path: $path');
    }
    _markers[path] = renderBox;
    _ensureSweep();
  }

  /// Unregister [renderBox] when it detaches.
  void unregister(String path, RenderBox renderBox) {
    if (!identical(_markers[path], renderBox)) return;
    _markers.remove(path);
    _ensureSweep();
  }

  /// Stop future sweeps and close the snapshot stream.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _markers.clear();
    unawaited(_snapshots.close());
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

    if (mapEquals(next, _previousSnapshot)) return;
    final snapshot = Map<String, Rect>.unmodifiable(next);
    _previousSnapshot = snapshot;
    _snapshots.add(snapshot);
  }

  Map<String, Rect> _capture() {
    final frame = _frameRenderBox();
    final next = <String, Rect>{};
    if (frame == null || !frame.attached) return next;
    for (final entry in _markers.entries) {
      final marker = entry.value;
      if (!marker.attached || !marker.hasSize) continue;
      next[entry.key] = MatrixUtils.transformRect(
        marker.getTransformTo(frame),
        Offset.zero & marker.size,
      );
    }
    return next;
  }
}

void _defaultSchedulePostFrameCallback(FrameCallback callback) {
  SchedulerBinding.instance.addPostFrameCallback(callback);
}
