import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'first_paint_lease_guard.dart';

/// Contains failures thrown by [child]'s subtree and routes them to [onError].
///
/// Every Flutter error still reaches the app's [FlutterError.onError] handler,
/// synchronously and exactly once; the boundary only replaces the failed
/// subtree with [errorReplacement]. While at least one boundary is mounted it
/// chains process-wide [FlutterError.onError] and [ErrorWidget.builder]
/// handlers, and restores them when the last one unmounts.
class RuntimeErrorBoundary extends StatefulWidget {
  /// Const constructor.
  const RuntimeErrorBoundary({
    super.key,
    required this.child,
    required this.onError,
    required this.errorReplacement,
    this.onFirstBuildSuccess,
    this.onFirstPaintSuccess,
    this.debugLabel,
  });

  /// The subtree to guard.
  final Widget child;

  /// Called once when the first exception is caught from [child]'s subtree.
  final void Function(Object exception, StackTrace stack) onError;

  /// Called by [build] when an exception has been caught, in place of [child].
  /// The default fallback should be benign (e.g. [SizedBox.shrink]).
  final Widget Function(
    BuildContext context,
    Object exception,
    StackTrace stack,
  ) errorReplacement;

  /// Reports the first frame whose descendant build completed without this
  /// boundary catching an error.
  ///
  /// The callback is post-frame so descendant build failures have already
  /// reached the boundary trap. When nested in a first-paint transaction, it is
  /// suppressed unless that transaction committed synchronously during paint.
  final VoidCallback? onFirstBuildSuccess;

  /// Reports the first frame whose descendant paint completed successfully.
  ///
  /// Layout and paint reports structurally owned by the guarded render subtree
  /// terminate this boundary — including independently flushed relayout and
  /// repaint work — whether or not this callback is supplied. Supplying it only
  /// adds the success notification; it does not arm the failure path.
  final VoidCallback? onFirstPaintSuccess;

  /// Names the guarded surface in the debug log line printed on fallback.
  final String? debugLabel;

  @override
  State<RuntimeErrorBoundary> createState() => _RuntimeErrorBoundaryState();
}

class _RuntimeErrorBoundaryState extends State<RuntimeErrorBoundary> {
  static final Set<_RuntimeErrorBoundaryState> _mountedBoundaries =
      <_RuntimeErrorBoundaryState>{};
  static _InstalledErrorHandlers? _installed;
  static bool _materializingInformationCollector = false;
  static int _collectorReentrancyGeneration = 0;

  Object? _caught;
  StackTrace? _stack;
  bool _failurePending = false;
  int _failureCaptureGeneration = 0;
  // Leases this boundary's pending failure blocks until it commits or lapses.
  final Set<FirstPaintLeaseTransaction> _heldLeases =
      HashSet<FirstPaintLeaseTransaction>.identity();
  _RenderRuntimeErrorBoundaryPaintProbe? _paintProbe;
  bool _successScheduled = false;
  bool _successReported = false;
  bool _paintSuccessScheduled = false;
  bool _paintSuccessReported = false;

  @override
  void initState() {
    super.initState();
    _mountedBoundaries.add(this);
    _installed ??= _InstalledErrorHandlers.install();
  }

  static void _restoreHandlersIfIdle() {
    if (_mountedBoundaries.isNotEmpty) return;
    _installed?.uninstall();
    _installed = null;
    _materializingInformationCollector = false;
    _collectorReentrancyGeneration = 0;
  }

  /// Contains a layout or paint failure inside the nearest guarded subtree.
  static void _containStructuralFailure(FlutterErrorDetails details) {
    final boundary = _resolveStructuralOwner(details);
    if (boundary == null) return;
    boundary._holdLease(FirstPaintLeaseScope.maybeOf(boundary.context));
    boundary._captureFirst(details.exception, details.stack);
  }

  void _holdLease(FirstPaintLeaseTransaction? lease) {
    if (lease == null) return;
    if (!holdFrameworkPaintErrorForTransaction(lease, this)) return;
    if (_caught != null) {
      commitFrameworkRenderFailureForTransaction(lease, this);
    } else {
      _heldLeases.add(lease);
    }
  }

  void _settleHeldLeases({required bool commit}) {
    for (final lease in _heldLeases) {
      if (commit) {
        commitFrameworkRenderFailureForTransaction(lease, this);
      } else {
        releaseFrameworkPaintErrorForTransaction(lease, this);
      }
    }
    _heldLeases.clear();
  }

  static _RuntimeErrorBoundaryState? _resolveStructuralOwner(
    FlutterErrorDetails details,
  ) {
    if (_materializingInformationCollector) {
      _collectorReentrancyGeneration += 1;
      return null;
    }
    final collector = details.informationCollector;
    if (collector == null) return null;

    final generation = _collectorReentrancyGeneration;
    late final HashSet<RenderObject> renderObjects;
    _materializingInformationCollector = true;
    try {
      final diagnostics = List<DiagnosticsNode>.of(collector());
      renderObjects = HashSet<RenderObject>.identity();
      for (final diagnostic in diagnostics) {
        final value = diagnostic.value;
        if (diagnostic is DiagnosticsProperty<Object?> &&
            diagnostic.exception != null) {
          continue;
        }
        if (value is RenderObject) renderObjects.add(value);
      }
    } on Object {
      return null;
    } finally {
      _materializingInformationCollector = false;
    }
    if (generation != _collectorReentrancyGeneration) return null;

    final markers = HashSet<_RenderRuntimeErrorBoundaryPaintProbe>.identity();
    for (final renderObject in renderObjects) {
      final marker = _nearestLivePaintProbe(renderObject);
      if (marker != null) markers.add(marker);
    }
    if (markers.isEmpty) return null;

    _RenderRuntimeErrorBoundaryPaintProbe? nearest;
    for (final candidate in markers) {
      final isNearest = markers.every(
        (other) =>
            identical(candidate, other) || _isRenderAncestor(other, candidate),
      );
      if (!isNearest) continue;
      if (nearest != null) return null;
      nearest = candidate;
    }
    return nearest?.boundary;
  }

  static _RenderRuntimeErrorBoundaryPaintProbe? _nearestLivePaintProbe(
    RenderObject renderObject,
  ) {
    RenderObject? current = renderObject;
    while (current != null) {
      if (current is _RenderRuntimeErrorBoundaryPaintProbe && current.isLive) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  static bool _isRenderAncestor(
    RenderObject ancestor,
    RenderObject descendant,
  ) {
    RenderObject? current = descendant.parent;
    while (current != null) {
      if (identical(current, ancestor)) return true;
      current = current.parent;
    }
    return false;
  }

  void _captureFirst(Object exception, StackTrace? stack) {
    // Mark failure synchronously so a success callback already queued for this
    // frame cannot win the post-frame race.
    if (_failurePending || _caught != null) return;
    _failurePending = true;
    _paintProbe?.markNeedsSemanticsUpdate();
    final resolvedStack = stack ?? StackTrace.current;
    final callback = widget.onError;
    final generation = ++_failureCaptureGeneration;
    // Defer setState until after the current build/frame so we don't
    // recurse into ourselves.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _failureCaptureGeneration) return;
      if (_caught != null) return;
      if (!identical(widget.onError, callback)) {
        _failurePending = false;
        _settleHeldLeases(commit: false);
        return;
      }
      _settleHeldLeases(commit: true);
      setState(() {
        _caught = exception;
        _stack = resolvedStack;
      });
      _debugReportFallback(exception);
      callback(exception, resolvedStack);
    });
    // A report can arrive from independently flushed work or while the
    // scheduler is idle/post-frame. Ensure the registered callback cannot be
    // stranded waiting for some unrelated future frame.
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _debugReportFallback(Object exception) {
    if (!kDebugMode) return;
    final label = widget.debugLabel;
    final surface = label == null ? 'a surface' : 'surface "$label"';
    final reason = '$exception'.split('\n').first;
    debugPrint('[restage] $surface fell back after a render error: $reason');
  }

  bool get _pipelineBlocked => _failurePending || _caught != null;

  void _registerPaintProbe(_RenderRuntimeErrorBoundaryPaintProbe probe) {
    _paintProbe = probe;
  }

  @override
  void didUpdateWidget(RuntimeErrorBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.onError, widget.onError)) return;
    if (_caught == null && _failurePending) {
      _settleHeldLeases(commit: false);
      _failureCaptureGeneration += 1;
      _failurePending = false;
      _paintProbe?.markNeedsSemanticsUpdate();
    }
  }

  @override
  void dispose() {
    _settleHeldLeases(commit: false);
    _failureCaptureGeneration += 1;
    _mountedBoundaries.remove(this);
    _restoreHandlersIfIdle();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_caught != null) {
      return widget.errorReplacement(
        context,
        _caught!,
        _stack ?? StackTrace.current,
      );
    }
    _scheduleFirstBuildSuccess();
    final guarded = _RuntimeErrorBoundaryScope(
      boundary: this,
      child: widget.child,
    );
    // The probe is the boundary's only marker in the render tree, so it is
    // mounted unconditionally. Structural failure ownership is a property of
    // guarding a subtree, not of wanting to be told about success: the
    // framework reports a descendant layout or paint exception instead of
    // rethrowing it, so without the marker such a failure is indistinguishable
    // from a clean frame and would be reported as one.
    return _RuntimeErrorBoundaryPaintProbe(boundary: this, child: guarded);
  }

  void _scheduleFirstBuildSuccess() {
    if (widget.onFirstBuildSuccess == null ||
        _successScheduled ||
        _successReported ||
        _pipelineBlocked ||
        _caught != null) {
      return;
    }
    _successScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _successScheduled = false;
      if (!mounted || _successReported || _pipelineBlocked || _caught != null) {
        return;
      }
      // A hosted candidate can finish descendant build even though its outer
      // lease guard rejected the frame before paint. Do not turn that unpainted
      // build into controller readiness. A committed transaction is already
      // pinned synchronously before descendant paint; an unscoped boundary
      // retains the existing success behavior.
      final transaction = FirstPaintLeaseScope.maybeOf(context);
      if (transaction != null &&
          (!transaction.isCommitted ||
              !transaction.canReportFrameworkRenderSuccess)) {
        return;
      }
      _successReported = true;
      widget.onFirstBuildSuccess?.call();
    });
  }

  void _scheduleFirstPaintSuccess() {
    final callback = widget.onFirstPaintSuccess;
    if (callback == null ||
        _paintSuccessScheduled ||
        _paintSuccessReported ||
        _pipelineBlocked ||
        _caught != null) {
      return;
    }
    _paintSuccessScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _paintSuccessScheduled = false;
      if (!mounted ||
          _paintSuccessReported ||
          _pipelineBlocked ||
          _caught != null ||
          !identical(widget.onFirstPaintSuccess, callback)) {
        return;
      }
      final transaction = FirstPaintLeaseScope.maybeOf(context);
      if (transaction != null && !transaction.canReportFrameworkRenderSuccess) {
        return;
      }
      _paintSuccessReported = true;
      callback();
    });
  }
}

/// One installation of the chained handlers, shared by every mounted boundary.
///
/// Each handler captures what it replaced, so a wrapper installed after it
/// keeps a working chain; once uninstalled, both handlers pass straight through.
final class _InstalledErrorHandlers {
  _InstalledErrorHandlers._(this._previousOnError, this._previousErrorBuilder);

  factory _InstalledErrorHandlers.install() {
    final installed = _InstalledErrorHandlers._(
      FlutterError.onError,
      ErrorWidget.builder,
    );
    FlutterError.onError = installed.onError;
    ErrorWidget.builder = installed.errorBuilder;
    return installed;
  }

  final FlutterExceptionHandler? _previousOnError;
  final ErrorWidgetBuilder _previousErrorBuilder;
  bool _active = true;

  late final FlutterExceptionHandler onError = _onError;
  late final ErrorWidgetBuilder errorBuilder = _buildErrorWidget;

  void _onError(FlutterErrorDetails details) {
    try {
      if (_active) {
        _RuntimeErrorBoundaryState._containStructuralFailure(details);
      }
    } finally {
      _previousOnError?.call(details);
    }
  }

  Widget _buildErrorWidget(FlutterErrorDetails details) => _active
      ? _RuntimeErrorBoundaryTrap(
          details: details,
          fallback: _previousErrorBuilder,
        )
      : _previousErrorBuilder(details);

  void uninstall() {
    _active = false;
    if (identical(FlutterError.onError, onError)) {
      FlutterError.onError = _previousOnError;
    }
    if (identical(ErrorWidget.builder, errorBuilder)) {
      ErrorWidget.builder = _previousErrorBuilder;
    }
  }
}

class _RuntimeErrorBoundaryScope extends InheritedWidget {
  const _RuntimeErrorBoundaryScope({
    required this.boundary,
    required super.child,
  });

  final _RuntimeErrorBoundaryState boundary;

  @override
  bool updateShouldNotify(_RuntimeErrorBoundaryScope oldWidget) =>
      boundary != oldWidget.boundary;
}

class _RuntimeErrorBoundaryPaintProbe extends SingleChildRenderObjectWidget {
  const _RuntimeErrorBoundaryPaintProbe({
    required this.boundary,
    required super.child,
  });

  final _RuntimeErrorBoundaryState boundary;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final renderObject = _RenderRuntimeErrorBoundaryPaintProbe(boundary);
    boundary._registerPaintProbe(renderObject);
    return renderObject;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRuntimeErrorBoundaryPaintProbe renderObject,
  ) {
    renderObject.updateBoundary(boundary);
    boundary._registerPaintProbe(renderObject);
  }
}

class _RenderRuntimeErrorBoundaryPaintProbe extends RenderProxyBox {
  _RenderRuntimeErrorBoundaryPaintProbe(this._boundary);

  _RuntimeErrorBoundaryState _boundary;

  _RuntimeErrorBoundaryState get boundary => _boundary;

  bool get isLive =>
      attached && _boundary.mounted && identical(_boundary._paintProbe, this);

  void updateBoundary(_RuntimeErrorBoundaryState value) {
    if (!identical(_boundary, value)) {
      _boundary = value;
      markNeedsLayout();
      markNeedsPaint();
    }
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = _boundary._pipelineBlocked
        ? constraints.constrain(Size.zero)
        : child.size;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_boundary._pipelineBlocked) return;
    super.paint(context, offset);
    _boundary._scheduleFirstPaintSuccess();
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_boundary._pipelineBlocked) return;
    super.visitChildrenForSemantics(visitor);
  }
}

class _RuntimeErrorBoundaryTrap extends StatelessWidget {
  const _RuntimeErrorBoundaryTrap({
    required this.details,
    required this.fallback,
  });

  final FlutterErrorDetails details;
  final ErrorWidgetBuilder fallback;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_RuntimeErrorBoundaryScope>();
    final boundary = scope?.boundary;
    if (boundary != null && boundary.mounted) {
      FirstPaintLeaseScope.maybeOf(context)?.recordBuildFailure();
      boundary._captureFirst(details.exception, details.stack);
      return const SizedBox.shrink();
    }
    return fallback(details);
  }
}
