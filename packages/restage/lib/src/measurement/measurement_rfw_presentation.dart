import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:rfw/rfw.dart';

import 'measurement_capture_edge.dart';
import 'measurement_worker.dart' show kMeasurementWorkerMaximumRouteCount;

/// SDK-local RFW namespace for the private Measurement presentation wrapper.
@internal
const LibraryName kMeasurementRfwPresentationLibrary = LibraryName(<String>[
  'restage',
  'measurement',
]);

const String _measurementPresentedConstructor = 'MeasurementPresented';
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
@internal
final class MeasurementRfwPresentationCaptureScope extends InheritedWidget {
  /// Creates the internal scope for one already-prebound capture edge.
  const MeasurementRfwPresentationCaptureScope({
    super.key,
    required this.edge,
    required super.child,
  });

  /// Exact edge selected before this subtree can paint.
  final MeasurementCaptureEdge edge;

  /// Finds the nearest prebound capture edge for [context].
  static MeasurementCaptureEdge? maybeOf(BuildContext context) =>
      maybeScopeOf(context)?.edge;

  /// Finds the nearest prebound capture scope for [context].
  static MeasurementRfwPresentationCaptureScope? maybeScopeOf(
    BuildContext context,
  ) =>
      context.dependOnInheritedWidgetOfExactType<
          MeasurementRfwPresentationCaptureScope>();

  @override
  bool updateShouldNotify(MeasurementRfwPresentationCaptureScope oldWidget) =>
      !identical(edge, oldWidget.edge);
}

/// Supplies the only pre-mount route binder to an RFW presentation subtree.
///
/// It is deliberately a separate widget type from
/// [MeasurementRfwPresentationCaptureScope], making the invalid
/// edge-and-binder constructor shape impossible in product builds.
@internal
final class MeasurementRfwPresentationBinderScope extends InheritedWidget {
  /// Creates one pre-mount compact-token binder scope.
  const MeasurementRfwPresentationBinderScope({
    super.key,
    required this.binder,
    required super.child,
  });

  /// Exact binder for compiler-delivered token/carrier pairs.
  final MeasurementRfwPresentationCaptureBinder binder;

  /// Finds the nearest pre-mount binder for [context].
  static MeasurementRfwPresentationCaptureBinder? maybeOf(
    BuildContext context,
  ) =>
      context
          .dependOnInheritedWidgetOfExactType<
              MeasurementRfwPresentationBinderScope>()
          ?.binder;

  @override
  bool updateShouldNotify(MeasurementRfwPresentationBinderScope oldWidget) =>
      !identical(binder, oldWidget.binder);
}

/// Builds the SDK-local RFW library that owns [MeasurementPresented].
@internal
LocalWidgetLibrary buildMeasurementRfwPresentationLocalWidgetLibrary() =>
    LocalWidgetLibrary(<String, LocalWidgetBuilder>{
      _measurementPresentedConstructor: _buildMeasurementPresented,
    });

/// Installs the private presentation library on one renderer runtime.
///
/// Renderer callers invoke this after applying customer libraries so an
/// impossible stale customer entry for the reserved namespace cannot replace
/// the SDK-owned implementation.
@internal
void installMeasurementRfwPresentationLibrary(Runtime runtime) {
  runtime.update(
    kMeasurementRfwPresentationLibrary,
    buildMeasurementRfwPresentationLocalWidgetLibrary(),
  );
}

Widget _buildMeasurementPresented(BuildContext context, DataSource source) {
  final child = source.child(const <Object>[_childArgument]);
  final pointTokens = _validPointTokens(source);
  if (pointTokens.isEmpty) return child;
  final edge = MeasurementRfwPresentationCaptureScope.maybeOf(context) ??
      MeasurementRfwPresentationBinderScope.maybeOf(context)?.bindPresentation(
        pointTokens: pointTokens,
        routeCarriers: _validRouteCarriers(source),
      );
  if (edge == null) return child;
  return MeasurementRfwPresentationCaptureScope(
    edge: edge,
    child: _MeasurementRfwPresentationProbe(
      pointTokens: pointTokens,
      child: child,
    ),
  );
}

List<String> _validPointTokens(DataSource source) {
  const path = <Object>[_pointTokensArgument];
  if (!source.isList(path)) return const <String>[];
  final length = source.length(path);
  if (length == 0 || length > kMeasurementWorkerMaximumRouteCount) {
    return const <String>[];
  }

  final pointTokens = <String>[];
  for (var index = 0; index < length; index += 1) {
    final pointToken = source.v<String>(<Object>[_pointTokensArgument, index]);
    if (pointToken != null) pointTokens.add(pointToken);
  }
  return List<String>.unmodifiable(pointTokens);
}

List<String> _validRouteCarriers(DataSource source) {
  const path = <Object>[_carriersArgument];
  if (!source.isList(path)) return const <String>[];
  final length = source.length(path);
  if (length == 0 || length > kMeasurementWorkerMaximumRouteCount) {
    return const <String>[];
  }

  final carriers = <String>[];
  for (var index = 0; index < length; index += 1) {
    final carrier = source.v<String>(<Object>[_carriersArgument, index]);
    if (carrier == null) return const <String>[];
    carriers.add(carrier);
  }
  return List<String>.unmodifiable(carriers);
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
  MeasurementCaptureEdge? _edge;
  var _scopeResolved = false;
  var _attempted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final edge = MeasurementRfwPresentationCaptureScope.maybeOf(context);
    if (!_scopeResolved) {
      _scopeResolved = true;
      _edge = edge;
      return;
    }
    if (!identical(_edge, edge)) {
      _edge = null;
      _attempted = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_edge == null) return widget.child;
    return _MeasurementRfwPresentationPaintBoundary(
      shouldObservePaint: _shouldObservePaint,
      onSuccessfulPaint: _reportAfterSuccessfulPaint,
      child: widget.child,
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

final class _MeasurementRfwPresentationPaintBoundary
    extends SingleChildRenderObjectWidget {
  const _MeasurementRfwPresentationPaintBoundary({
    required this.shouldObservePaint,
    required this.onSuccessfulPaint,
    required super.child,
  });

  final bool Function() shouldObservePaint;
  final VoidCallback onSuccessfulPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasurementRfwPresentationPaintBoundary(
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
    this._onSuccessfulPaint,
    this._shouldObservePaint,
  );

  VoidCallback _onSuccessfulPaint;
  bool Function() _shouldObservePaint;

  set onSuccessfulPaint(VoidCallback value) => _onSuccessfulPaint = value;

  set shouldObservePaint(bool Function() value) => _shouldObservePaint = value;

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
