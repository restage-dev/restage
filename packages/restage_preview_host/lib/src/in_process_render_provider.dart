import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, mapEquals;
import 'package:flutter/scheduler.dart' show FrameCallback, SchedulerBinding;
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' show RestageWidgetLibraryRegistration;
import 'package:restage_preview_host/src/geometry_registry.dart';
import 'package:restage_preview_host/src/protocol.dart';
import 'package:restage_preview_host/src/raw_rfw_render_surface.dart';
import 'package:rfw/rfw.dart' show RemoteEventHandler;

/// Native renderer adapter with the same event and geometry contract as a
/// transport-backed surface.
final class InProcessRenderProvider implements SurfaceRenderProvider {
  /// Creates a provider for one preview frame.
  InProcessRenderProvider({
    GeometryPostFrameScheduler schedulePostFrameCallback =
        _defaultSchedulePostFrameCallback,
  }) {
    geometryRegistry = GeometryRegistry(
      frameRenderBox: () =>
          _frameKey.currentContext?.findRenderObject() as RenderBox?,
      schedulePostFrameCallback: schedulePostFrameCallback,
    );
    _registrySubscription = geometryRegistry.snapshots.listen(_handleSnapshot);
  }

  /// Registry supplied to the corresponding render surface.
  late final GeometryRegistry geometryRegistry;

  final StreamController<GeometrySnapshot> _geometry =
      StreamController<GeometrySnapshot>.broadcast(sync: true);
  final StreamController<RenderEvent> _events =
      StreamController<RenderEvent>.broadcast(sync: true);
  final ValueNotifier<RenderRequest?> _request = ValueNotifier<RenderRequest?>(
    null,
  );
  final GlobalKey _frameKey = GlobalKey();
  late final StreamSubscription<Map<String, Rect>> _registrySubscription;

  int? _epoch;
  int _generation = -1;
  Map<String, Rect>? _lastEmittedRects;
  bool _settled = false;
  bool _terminal = false;
  bool _disposed = false;

  @override
  Stream<GeometrySnapshot> get geometry => _geometry.stream;

  @override
  Stream<RenderEvent> get events => _events.stream;

  @override
  Future<void> render(RenderRequest request) async {
    _ensureActive();
    final current = _epoch;
    if (current != null && request.epoch <= current) {
      throw ArgumentError.value(
        request.epoch,
        'epoch',
        'must be strictly monotonic',
      );
    }
    _epoch = request.epoch;
    _generation = -1;
    _lastEmittedRects = null;
    _settled = false;
    _terminal = false;
    _request.value = request;
  }

  void _handleRenderEvent(RenderEvent event) {
    if (_disposed) return;
    switch (event) {
      case Settled(epoch: final epoch):
        if (!_isCurrent(epoch) || _settled || _terminal) return;
        _settled = true;
        _events.add(event);
        _emitGeometry(geometryRegistry.capture());
      case RenderError(epoch: final epoch):
        if (!_isCurrent(epoch) || _terminal) return;
        _terminal = true;
        _events.add(event);
      case ProtocolError():
        _events.add(event);
    }
  }

  void _handleSnapshot(Map<String, Rect> rects) {
    if (!_settled || _terminal) return;
    _emitGeometry(rects);
  }

  void _emitGeometry(Map<String, Rect> rects) {
    final epoch = _epoch;
    if (epoch == null || mapEquals(rects, _lastEmittedRects)) return;
    _generation += 1;
    _lastEmittedRects = Map<String, Rect>.unmodifiable(rects);
    _geometry.add(
      GeometrySnapshot(
        epoch: epoch,
        generation: _generation,
        rects: _lastEmittedRects!,
      ),
    );
  }

  bool _isCurrent(int epoch) => epoch == _epoch;

  void _ensureActive() {
    if (_disposed) throw StateError('InProcessRenderProvider is disposed.');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _request.value = null;
    await _registrySubscription.cancel();
    geometryRegistry.dispose();
    await Future.wait<void>(<Future<void>>[_geometry.close(), _events.close()]);
    _request.dispose();
  }
}

/// Public in-process preview surface driven exclusively by [provider.render].
///
/// Host configuration such as the entry widget and local customer widget
/// registrations stays outside the transport-neutral [RenderRequest]. The
/// rendered blob, data, environment, epoch, lifecycle events, and geometry all
/// come from the provider's latest accepted request.
class InProcessPreviewSurface extends StatelessWidget {
  /// Creates the one mounted render surface paired with [provider].
  const InProcessPreviewSurface({
    required this.provider,
    required this.registrations,
    required this.entryWidgetName,
    required this.onRemoteEvent,
    super.key,
  });

  /// Provider whose accepted render requests drive this surface.
  final InProcessRenderProvider provider;

  /// Host-local widget registrations available to the rendered document.
  final List<RestageWidgetLibraryRegistration> registrations;

  /// Widget mounted from the request's RFW library.
  final String entryWidgetName;

  /// Receives events emitted by the rendered RFW document.
  final RemoteEventHandler onRemoteEvent;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RenderRequest?>(
      valueListenable: provider._request,
      builder: (context, request, child) {
        if (request == null) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: provider._frameKey,
            width: request.env.frame.width,
            height: request.env.frame.height,
            child: RawRfwRenderSurface(
              epoch: request.epoch,
              blob: request.blob,
              data: request.data,
              environment: request.env,
              registrations: registrations,
              entryWidgetName: entryWidgetName,
              onRemoteEvent: onRemoteEvent,
              onRenderEvent: provider._handleRenderEvent,
              geometryRegistry: provider.geometryRegistry,
            ),
          ),
        );
      },
    );
  }
}

void _defaultSchedulePostFrameCallback(FrameCallback callback) {
  SchedulerBinding.instance.addPostFrameCallback(callback);
}
