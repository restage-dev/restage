part of 'presentation_commit.dart';

/// Commits a presentation only after the guarded descendant paint succeeds.
///
/// The caller supplies an already resolved [MeasurementPresentationRouteHandle]
/// at the exact mounted publication boundary.
final class MeasurementPresentationCommitHook extends StatefulWidget {
  /// Creates a render-backed first-paint commit hook.
  const MeasurementPresentationCommitHook({
    super.key,
    required this.routeHandle,
    required this.child,
  });

  /// Opaque lifetime handle for the exact mounted publication.
  final MeasurementPresentationRouteHandle routeHandle;

  /// Mounted surface subtree whose first successful paint is observed.
  final Widget child;

  @override
  State<MeasurementPresentationCommitHook> createState() =>
      _MeasurementPresentationCommitHookState();
}

final class _MeasurementPresentationCommitHookState
    extends State<MeasurementPresentationCommitHook> {
  late FirstPaintLeaseTransaction _firstPaintTransaction;
  var _firstPaintAcknowledged = false;

  @override
  void initState() {
    super.initState();
    _createFirstPaintTransaction();
  }

  @override
  void didUpdateWidget(MeasurementPresentationCommitHook oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.routeHandle, widget.routeHandle)) return;
    oldWidget.routeHandle._abortForUnmount();
    _firstPaintTransaction.supersede();
    _firstPaintAcknowledged = false;
    _createFirstPaintTransaction();
  }

  @override
  void dispose() {
    widget.routeHandle._abortForUnmount();
    _firstPaintTransaction.supersede();
    super.dispose();
  }

  void _createFirstPaintTransaction() {
    _firstPaintTransaction = FirstPaintLeaseTransaction(
      canCommit: _alwaysCanCommit,
      commit: _noOp,
      onPainted: _acknowledgeFirstPaint,
      afterCommit: _noOp,
      afterRejection: _noOp,
    );
  }

  void _acknowledgeFirstPaint() {
    _firstPaintAcknowledged = true;
  }

  bool _takeFirstPaintAcknowledgement() {
    final acknowledged = _firstPaintAcknowledged;
    _firstPaintAcknowledged = false;
    return acknowledged;
  }

  @override
  Widget build(BuildContext context) => _MeasurementPresentationPaintBoundary(
        routeHandle: widget.routeHandle,
        takeFirstPaintAcknowledgement: _takeFirstPaintAcknowledgement,
        child: FirstPaintLeaseScope(
          transaction: _firstPaintTransaction,
          child: FirstPaintLeaseGuard(
            transaction: _firstPaintTransaction,
            armed: true,
            child: widget.child,
          ),
        ),
      );
}

bool _alwaysCanCommit() => true;

void _noOp() {}

final class _MeasurementPresentationPaintBoundary
    extends SingleChildRenderObjectWidget {
  const _MeasurementPresentationPaintBoundary({
    required this.routeHandle,
    required this.takeFirstPaintAcknowledgement,
    required super.child,
  });

  final MeasurementPresentationRouteHandle routeHandle;
  final bool Function() takeFirstPaintAcknowledgement;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasurementPresentationPaintBoundary(
        routeHandle,
        takeFirstPaintAcknowledgement,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasurementPresentationPaintBoundary renderObject,
  ) {
    renderObject
      ..routeHandle = routeHandle
      ..takeFirstPaintAcknowledgement = takeFirstPaintAcknowledgement;
  }
}

final class _RenderMeasurementPresentationPaintBoundary extends RenderProxyBox {
  _RenderMeasurementPresentationPaintBoundary(
    this._routeHandle,
    this._takeFirstPaintAcknowledgement,
  );

  MeasurementPresentationRouteHandle _routeHandle;
  bool Function() _takeFirstPaintAcknowledgement;

  set routeHandle(MeasurementPresentationRouteHandle value) {
    if (identical(_routeHandle, value)) return;
    _routeHandle = value;
    markNeedsPaint();
  }

  set takeFirstPaintAcknowledgement(bool Function() value) {
    _takeFirstPaintAcknowledgement = value;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canCommit = _routeHandle._canCommitAfterSuccessfulPaint;
    try {
      super.paint(context, offset);
    } on Object {
      if (canCommit) _routeHandle._rejectFailedPaint();
      rethrow;
    }

    final firstPaintAcknowledged = _takeFirstPaintAcknowledgement();
    if (!canCommit) return;
    if (!firstPaintAcknowledged) {
      _routeHandle._rejectFailedPaint();
      return;
    }
    _routeHandle._recordSuccessfulFirstPaint();
  }
}
