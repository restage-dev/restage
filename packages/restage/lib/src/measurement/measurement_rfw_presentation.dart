import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:restage_shared/restage_shared.dart'
    show kMeasurementPresentationRfwLibrary;
import 'package:rfw/rfw.dart';

import 'measurement_capture_edge.dart';
import 'measurement_worker.dart' show kMeasurementWorkerMaximumRouteCount;

/// SDK-local RFW namespace for the private Measurement presentation wrapper.
@internal
final LibraryName kMeasurementRfwPresentationLibrary = LibraryName(
  kMeasurementPresentationRfwLibrary.namespace.split('.'),
);
const String _pointTokensArgument = 'pointTokens';
const String _carriersArgument = 'carriers';
const String _childArgument = 'child';

/// Receives opaque final route carriers from a successfully painted RFW probe.
@internal
abstract interface class MeasurementRfwPresentationSink {
  /// Records one exact final route carrier for the mounted RFW occurrence.
  void recordPresentedCarrier(String rawCarrier);
}

/// Resolves compiler-emitted presentation tokens before a probe can paint.
///
/// The owner may inspect static delivered carrier metadata here, outside the
/// paint/action edge, then returns a prebound compact-only [MeasurementCaptureEdge].
@internal
abstract interface class MeasurementRfwPresentationCaptureBinder {
  /// Returns one exact compact-only edge, or `null` when the wrapper is not
  /// part of the admitted binding closure.
  MeasurementCaptureEdge? bindPresentation({
    required List<String> pointTokens,
    required List<String> routeCarriers,
  });
}

/// A binder whose target arrives after the surface first builds.
///
/// Probes under it keep their place in the tree and bind once [resolve] runs,
/// so the surface's widget state survives the session opening.
@internal
final class MeasurementDeferredPresentationBinder extends ChangeNotifier
    implements MeasurementRfwPresentationCaptureBinder {
  MeasurementRfwPresentationCaptureBinder? _target;
  var _resolved = false;

  /// Whether [resolve] has run.
  bool get isResolved => _resolved;

  /// Sets the binder probes bind through; null leaves them unbound.
  void resolve(MeasurementRfwPresentationCaptureBinder? target) {
    if (_resolved) return;
    _resolved = true;
    _target = target;
    notifyListeners();
  }

  @override
  MeasurementCaptureEdge? bindPresentation({
    required List<String> pointTokens,
    required List<String> routeCarriers,
  }) =>
      _target?.bindPresentation(
        pointTokens: pointTokens,
        routeCarriers: routeCarriers,
      );
}

/// Supplies the private presentation sink to an RFW runtime subtree.
@internal
final class MeasurementRfwPresentationScope extends InheritedWidget {
  /// Creates the internal scope used by a future host composition boundary.
  const MeasurementRfwPresentationScope({
    super.key,
    required this.sink,
    required super.child,
  });

  /// The downstream host-owned sink for opaque route carriers.
  final MeasurementRfwPresentationSink sink;

  /// Finds the nearest internal presentation sink for [context].
  static MeasurementRfwPresentationSink? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MeasurementRfwPresentationScope>()
          ?.sink;

  @override
  bool updateShouldNotify(MeasurementRfwPresentationScope oldWidget) =>
      !identical(sink, oldWidget.sink);
}

/// Supplies one compact-token capture edge to an RFW presentation subtree.
///
/// It also installs the surface's root paint boundary, so every presentation
/// probe beneath it has an enclosing boundary to report through.
@internal
final class MeasurementRfwPresentationCaptureScope extends StatelessWidget {
  /// Creates the internal scope for one already-prebound capture edge.
  const MeasurementRfwPresentationCaptureScope({
    super.key,
    required this.edge,
    required this.child,
  });

  /// Exact edge selected before this subtree can paint.
  final MeasurementCaptureEdge edge;

  /// The surface subtree.
  final Widget child;

  /// Finds the nearest prebound capture edge for [context].
  static MeasurementCaptureEdge? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_MeasurementRfwEdgeInherited>()
      ?.edge;

  @override
  Widget build(BuildContext context) => _MeasurementRfwEdgeInherited(
        edge: edge,
        child: _MeasurementRfwPresentationRootBoundary(child: child),
      );
}

final class _MeasurementRfwEdgeInherited extends InheritedWidget {
  const _MeasurementRfwEdgeInherited({
    required this.edge,
    required super.child,
  });

  final MeasurementCaptureEdge? edge;

  @override
  bool updateShouldNotify(_MeasurementRfwEdgeInherited oldWidget) =>
      !identical(edge, oldWidget.edge);
}

/// Installs the pre-mount route binder and root paint boundary.
/// Kept separate from [MeasurementRfwPresentationCaptureScope] to prevent
/// invalid edge-and-binder construction.
@internal
final class MeasurementRfwPresentationBinderScope extends StatelessWidget {
  /// Creates one pre-mount compact-token binder scope.
  const MeasurementRfwPresentationBinderScope({
    super.key,
    required this.binder,
    required this.child,
  });

  /// Exact binder for compiler-delivered token/carrier pairs.
  final MeasurementRfwPresentationCaptureBinder binder;

  /// The surface subtree.
  final Widget child;

  /// Finds the nearest pre-mount binder for [context].
  static MeasurementRfwPresentationCaptureBinder? maybeOf(
    BuildContext context,
  ) =>
      context
          .dependOnInheritedWidgetOfExactType<_MeasurementRfwBinderInherited>()
          ?.binder;

  @override
  Widget build(BuildContext context) => _MeasurementRfwBinderInherited(
        binder: binder,
        child: _MeasurementRfwPresentationRootBoundary(child: child),
      );
}

final class _MeasurementRfwBinderInherited extends InheritedWidget {
  const _MeasurementRfwBinderInherited({
    required this.binder,
    required super.child,
  });

  final MeasurementRfwPresentationCaptureBinder binder;

  @override
  bool updateShouldNotify(_MeasurementRfwBinderInherited oldWidget) =>
      !identical(binder, oldWidget.binder);
}

final class _MeasurementRfwPresentationRootBoundary extends StatefulWidget {
  const _MeasurementRfwPresentationRootBoundary({required this.child});

  final Widget child;

  @override
  State<_MeasurementRfwPresentationRootBoundary> createState() =>
      _MeasurementRfwPresentationRootBoundaryState();
}

final class _MeasurementRfwPresentationRootBoundaryState
    extends State<_MeasurementRfwPresentationRootBoundary> {
  final _registry = _PaintObserverRegistry();

  @override
  Widget build(BuildContext context) => _MeasurementRfwPresentationPaintScope(
        registry: _registry,
        child: _MeasurementRfwPresentationPaintBoundary(
          registry: _registry,
          shouldObservePaint: () => _registry.hasPendingObserver,
          onSuccessfulPaint: _registry.reportSuccessfulPaint,
          child: widget.child,
        ),
      );
}

/// Builds the SDK-local RFW library that owns [MeasurementPresented].
@internal
LocalWidgetLibrary buildMeasurementRfwPresentationLocalWidgetLibrary() =>
    LocalWidgetLibrary(<String, LocalWidgetBuilder>{
      for (final constructor in kMeasurementPresentationRfwLibrary.constructors)
        constructor: _buildBoundMeasurementPresented,
    });

/// Installs the SDK-owned presentation library after app-defined libraries,
/// preserving its reserved namespace.
@internal
void installMeasurementRfwPresentationLibrary(Runtime runtime) {
  runtime.update(
    kMeasurementRfwPresentationLibrary,
    buildMeasurementRfwPresentationLocalWidgetLibrary(),
  );
}

/// Adds Measurement presentation support to an RFW runtime.
void registerMeasurementRfwPresentationLibrary(Runtime runtime) =>
    installMeasurementRfwPresentationLibrary(runtime);

Widget _buildBoundMeasurementPresented(
  BuildContext context,
  DataSource source,
) {
  final child = source.child(const <Object>[_childArgument]);
  final pointTokens = _validPointTokens(source);
  if (pointTokens.isEmpty) return child;
  final binder = MeasurementRfwPresentationBinderScope.maybeOf(context);
  if (binder is MeasurementDeferredPresentationBinder) {
    final routeCarriers = _validRouteCarriers(source);
    if (pointTokens.length != routeCarriers.length) return child;
    return _DeferredPresentationProbe(
      binder: binder,
      pointTokens: pointTokens,
      routeCarriers: routeCarriers,
      child: child,
    );
  }
  MeasurementCaptureEdge? edge;
  if (binder == null) {
    edge = MeasurementRfwPresentationCaptureScope.maybeOf(context);
  } else {
    final routeCarriers = _validRouteCarriers(source);
    if (pointTokens.length != routeCarriers.length) return child;
    edge = binder.bindPresentation(
      pointTokens: pointTokens,
      routeCarriers: routeCarriers,
    );
  }
  if (edge == null) return child;
  return _MeasurementRfwEdgeInherited(
    edge: edge,
    child: _MeasurementRfwPresentationProbe(
      pointTokens: pointTokens,
      child: child,
    ),
  );
}

/// Keeps one probe in place while its binder resolves, then binds it once.
final class _DeferredPresentationProbe extends StatefulWidget {
  const _DeferredPresentationProbe({
    required this.binder,
    required this.pointTokens,
    required this.routeCarriers,
    required this.child,
  });

  final MeasurementDeferredPresentationBinder binder;
  final List<String> pointTokens;
  final List<String> routeCarriers;
  final Widget child;

  @override
  State<_DeferredPresentationProbe> createState() =>
      _DeferredPresentationProbeState();
}

final class _DeferredPresentationProbeState
    extends State<_DeferredPresentationProbe> {
  MeasurementCaptureEdge? _edge;
  var _bound = false;

  @override
  void initState() {
    super.initState();
    widget.binder.addListener(_bindIfResolved);
    _bindIfResolved();
  }

  @override
  void dispose() {
    widget.binder.removeListener(_bindIfResolved);
    super.dispose();
  }

  void _bindIfResolved() {
    if (_bound || !widget.binder.isResolved) return;
    _bound = true;
    MeasurementCaptureEdge? edge;
    try {
      edge = widget.binder.bindPresentation(
        pointTokens: widget.pointTokens,
        routeCarriers: widget.routeCarriers,
      );
    } on Object {
      edge = null;
    }
    if (edge == null) return;
    if (mounted) setState(() => _edge = edge);
  }

  @override
  Widget build(BuildContext context) => _MeasurementRfwEdgeInherited(
        edge: _edge,
        child: _MeasurementRfwPresentationProbe(
          pointTokens: widget.pointTokens,
          child: widget.child,
        ),
      );
}

List<String> _validPointTokens(DataSource source) =>
    _validStringList(source, _pointTokensArgument);

List<String> _validRouteCarriers(DataSource source) =>
    _validStringList(source, _carriersArgument);

List<String> _validStringList(DataSource source, String argument) {
  final path = <Object>[argument];
  if (!source.isList(path)) return const <String>[];
  final length = source.length(path);
  if (length == 0 || length > kMeasurementWorkerMaximumRouteCount) {
    return const <String>[];
  }

  final values = <String>[];
  for (var index = 0; index < length; index += 1) {
    final value = source.v<String>(<Object>[argument, index]);
    if (value == null) return const <String>[];
    values.add(value);
  }
  return List<String>.unmodifiable(values);
}

final class _MeasurementRfwPresentationProbe extends StatefulWidget {
  const _MeasurementRfwPresentationProbe({
    required this.pointTokens,
    required this.child,
  });

  final List<String> pointTokens;
  final Widget child;

  @override
  State<_MeasurementRfwPresentationProbe> createState() =>
      _MeasurementRfwPresentationProbeState();
}

final class _MeasurementRfwPresentationProbeState
    extends State<_MeasurementRfwPresentationProbe> {
  late final List<String> _pointTokens = widget.pointTokens;
  late final _PaintObserver _observer = _PaintObserver(
    shouldObservePaint: _shouldObservePaint,
    onSuccessfulPaint: _reportAfterSuccessfulPaint,
  );
  MeasurementCaptureEdge? _edge;
  var _scopeResolved = false;
  var _attempted = false;

  /// Owned when this probe may sit between its child and the parent render
  /// object; `null` when the probe reports through an enclosing boundary.
  _PaintObserverRegistry? _ownRegistry;
  _PaintObserverRegistry? _enclosingRegistry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final edge = MeasurementRfwPresentationCaptureScope.maybeOf(context);
    if (!_scopeResolved) {
      _scopeResolved = true;
      _edge = edge;
      if (_slotAcceptsBoundary(context)) {
        _ownRegistry = _PaintObserverRegistry();
      }
    } else if (_edge == null && !_attempted && edge != null) {
      // A deferred binder resolved after the first build.
      _edge = edge;
      _ownRegistry?._boundary?.markNeedsPaint();
      _enclosingRegistry?._boundary?.markNeedsPaint();
    } else if (!identical(_edge, edge)) {
      _edge = null;
      _attempted = true;
    }
    if (_ownRegistry == null) {
      final enclosing = _MeasurementRfwPresentationPaintScope.maybeOf(context);
      if (!identical(enclosing, _enclosingRegistry)) {
        _enclosingRegistry?.remove(_observer);
        _enclosingRegistry = enclosing?..add(_observer);
      }
    }
  }

  @override
  void dispose() {
    _enclosingRegistry?.remove(_observer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = _ownRegistry;
    if (registry == null) return widget.child;
    return _MeasurementRfwPresentationPaintScope(
      registry: registry,
      child: _MeasurementRfwPresentationPaintBoundary(
        registry: registry,
        shouldObservePaint: () =>
            _shouldObservePaint() || registry.hasPendingObserver,
        onSuccessfulPaint: () {
          _reportAfterSuccessfulPaint();
          registry.reportSuccessfulPaint();
        },
        child: widget.child,
      ),
    );
  }

  bool _shouldObservePaint() => !_attempted && _edge?.isAvailable == true;

  void _reportAfterSuccessfulPaint() {
    final edge = _edge;
    if (_attempted || edge == null) return;
    _attempted = true;
    try {
      for (final pointToken in _pointTokens) {
        edge.appendPresentationToken(pointToken);
      }
      // A downstream measurement failure cannot affect the child.
      // ignore: avoid_catching_errors
    } on Object {
      edge.close();
    }
  }
}

/// Whether a render object may be inserted at [context] without taking the
/// slot a parent-data widget (Expanded, Positioned, ...) needs.
bool _slotAcceptsBoundary(BuildContext context) {
  var accepts = false;
  context.visitAncestorElements((ancestor) {
    if (ancestor.widget is ParentDataWidget) {
      accepts = true;
      return false;
    }
    if (ancestor is RenderObjectElement) {
      accepts = ancestor.renderObject is RenderObjectWithChildMixin;
      return false;
    }
    return true;
  });
  return accepts;
}

final class _PaintObserver {
  const _PaintObserver({
    required this.shouldObservePaint,
    required this.onSuccessfulPaint,
  });

  final bool Function() shouldObservePaint;
  final VoidCallback onSuccessfulPaint;
}

/// Probes that cannot own a boundary report through the nearest one.
final class _PaintObserverRegistry {
  final Set<_PaintObserver> _observers = <_PaintObserver>{};
  RenderObject? _boundary;

  bool get hasPendingObserver =>
      _observers.any((observer) => observer.shouldObservePaint());

  void add(_PaintObserver observer) {
    if (_observers.add(observer)) _boundary?.markNeedsPaint();
  }

  void remove(_PaintObserver observer) => _observers.remove(observer);

  void reportSuccessfulPaint() {
    for (final observer in List.of(_observers)) {
      if (observer.shouldObservePaint()) observer.onSuccessfulPaint();
    }
  }
}

final class _MeasurementRfwPresentationPaintScope extends InheritedWidget {
  const _MeasurementRfwPresentationPaintScope({
    required this.registry,
    required super.child,
  });

  final _PaintObserverRegistry registry;

  static _PaintObserverRegistry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<
          _MeasurementRfwPresentationPaintScope>()
      ?.registry;

  @override
  bool updateShouldNotify(_MeasurementRfwPresentationPaintScope oldWidget) =>
      !identical(registry, oldWidget.registry);
}

final class _MeasurementRfwPresentationPaintBoundary
    extends SingleChildRenderObjectWidget {
  const _MeasurementRfwPresentationPaintBoundary({
    required this.registry,
    required this.shouldObservePaint,
    required this.onSuccessfulPaint,
    required super.child,
  });

  final _PaintObserverRegistry registry;
  final bool Function() shouldObservePaint;
  final VoidCallback onSuccessfulPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasurementRfwPresentationPaintBoundary(
        registry,
        onSuccessfulPaint,
        shouldObservePaint,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasurementRfwPresentationPaintBoundary renderObject,
  ) {
    renderObject
      ..onSuccessfulPaint = onSuccessfulPaint
      ..shouldObservePaint = shouldObservePaint;
  }
}

final class _RenderMeasurementRfwPresentationPaintBoundary
    extends RenderProxyBox {
  _RenderMeasurementRfwPresentationPaintBoundary(
    this._registry,
    this._onSuccessfulPaint,
    this._shouldObservePaint,
  );

  final _PaintObserverRegistry _registry;
  VoidCallback _onSuccessfulPaint;
  bool Function() _shouldObservePaint;

  set onSuccessfulPaint(VoidCallback value) => _onSuccessfulPaint = value;

  set shouldObservePaint(bool Function() value) => _shouldObservePaint = value;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _registry._boundary = this;
  }

  @override
  void detach() {
    if (identical(_registry._boundary, this)) _registry._boundary = null;
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_shouldObservePaint()) {
      super.paint(context, offset);
      return;
    }
    final previousOnError = FlutterError.onError;
    var descendantPaintFailed = false;
    void observingOnError(FlutterErrorDetails details) {
      descendantPaintFailed = true;
      if (previousOnError == null) {
        FlutterError.presentError(details);
      } else {
        previousOnError(details);
      }
    }

    FlutterError.onError = observingOnError;
    var returnedNormally = false;
    try {
      super.paint(context, offset);
      returnedNormally = true;
    } finally {
      if (identical(FlutterError.onError, observingOnError)) {
        FlutterError.onError = previousOnError;
      }
    }
    if (!returnedNormally || descendantPaintFailed) return;
    _onSuccessfulPaint();
  }
}
