import 'package:flutter/rendering.dart'
    show PipelineOwner, RenderBox, RenderProxyBox;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        SingleChildRenderObjectWidget,
        State,
        StatefulWidget,
        Widget;
import 'package:restage_preview_host/src/document_path_codec.dart';
import 'package:restage_preview_host/src/geometry_registry.dart';
import 'package:restage/restage.dart' show kReservedPreviewConstructorName;
import 'package:rfw/rfw.dart'
    show DataSource, LocalWidgetBuilder, LocalWidgetLibrary;

/// Build the preview-only `restage.editor` local widget library.
LocalWidgetLibrary buildMarkerWidgetLibrary(GeometryRegistry registry) {
  return LocalWidgetLibrary(<String, LocalWidgetBuilder>{
    kReservedPreviewConstructorName: (BuildContext context, DataSource source) {
      final path = source.v<String>(const <Object>['path']);
      if (path == null) {
        throw ArgumentError('marker.path must be a compact JSON path.');
      }
      try {
        DocumentPathCodec.decode(path);
      } on FormatException catch (error) {
        throw ArgumentError.value(path, 'path', error.message);
      }
      return _RenderlessGeometryMarker(
        path: path,
        registry: registry,
        child: source.child(const <Object>['child']),
      );
    },
  });
}

/// A layout- and paint-transparent wrapper for one authored preview node.
class GeometryMarker extends SingleChildRenderObjectWidget {
  /// Create a geometry marker.
  const GeometryMarker({
    super.key,
    required this.path,
    required this.registry,
    required super.child,
  });

  /// Compact JSON path identifying the authored node.
  final String path;

  /// Registry owned by this preview frame.
  final GeometryRegistry registry;

  @override
  RenderGeometryMarker createRenderObject(BuildContext context) {
    return RenderGeometryMarker(path: path, registry: registry);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGeometryMarker renderObject,
  ) {
    renderObject
      ..registry = registry
      ..path = path;
  }
}

/// Renderless marker used only by the RFW instrumentation library.
///
/// A component widget leaves ParentDataWidget ancestry intact while resolving
/// the authored subtree's current descendant RenderBox after each frame.
final class _RenderlessGeometryMarker extends StatefulWidget {
  const _RenderlessGeometryMarker({
    required this.path,
    required this.registry,
    required this.child,
  });

  final String path;
  final GeometryRegistry registry;
  final Widget child;

  @override
  State<_RenderlessGeometryMarker> createState() =>
      _RenderlessGeometryMarkerState();
}

final class _RenderlessGeometryMarkerState
    extends State<_RenderlessGeometryMarker> {
  RenderBox? _registeredRenderBox;
  bool _active = true;
  bool _resolutionScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleResolution();
  }

  @override
  void didUpdateWidget(_RenderlessGeometryMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path == widget.path &&
        identical(oldWidget.registry, widget.registry)) {
      return;
    }
    final previous = _registeredRenderBox;
    if (previous != null) {
      oldWidget.registry.unregister(oldWidget.path, previous);
      _registeredRenderBox = null;
    }
    _scheduleResolution();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    _scheduleResolution();
  }

  @override
  void deactivate() {
    _active = false;
    _unregisterCurrent();
    super.deactivate();
  }

  @override
  void dispose() {
    _active = false;
    _unregisterCurrent();
    super.dispose();
  }

  void _scheduleResolution() {
    if (!_active || _resolutionScheduled) return;
    _resolutionScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback(_resolveAndRearm);
  }

  void _resolveAndRearm(Duration _) {
    _resolutionScheduled = false;
    if (!mounted || !_active) return;
    final candidate = context.findRenderObject();
    final next =
        candidate is RenderBox && candidate.attached ? candidate : null;
    final previous = _registeredRenderBox;
    if (!identical(previous, next)) {
      if (previous != null) {
        widget.registry.unregister(widget.path, previous);
      }
      if (next != null) {
        widget.registry.register(widget.path, next);
      }
      _registeredRenderBox = next;
    }
    _scheduleResolution();
  }

  void _unregisterCurrent() {
    final previous = _registeredRenderBox;
    if (previous == null) return;
    widget.registry.unregister(widget.path, previous);
    _registeredRenderBox = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Pure proxy render object that registers only while attached.
final class RenderGeometryMarker extends RenderProxyBox {
  /// Create a render marker.
  RenderGeometryMarker({
    required String path,
    required GeometryRegistry registry,
    RenderBox? child,
  })  : _path = path,
        _registry = registry,
        super(child) {
    DocumentPathCodec.decode(path);
  }

  String _path;
  GeometryRegistry _registry;

  /// Compact JSON path identifying this render box.
  String get path => _path;

  set path(String value) {
    if (value == _path) return;
    DocumentPathCodec.decode(value);
    if (attached) _registry.register(value, this);
    final previous = _path;
    _path = value;
    if (attached) _registry.unregister(previous, this);
  }

  /// Registry owned by this preview frame.
  GeometryRegistry get registry => _registry;

  set registry(GeometryRegistry value) {
    if (identical(value, _registry)) return;
    if (attached) value.register(_path, this);
    final previous = _registry;
    _registry = value;
    if (attached) previous.unregister(_path, this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _registry.register(_path, this);
  }

  @override
  void detach() {
    _registry.unregister(_path, this);
    super.detach();
  }
}
