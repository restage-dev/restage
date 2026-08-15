import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'first_paint_lease_guard.dart';

/// Catches exceptions thrown by [child]'s subtree and routes them to [onError].
///
/// Scoped build-error shim. [ErrorWidget.builder] and [FlutterError.onError]
/// are global state, so this boundary installs process-wide handlers while at
/// least one instance is mounted. The replacement [ErrorWidget] then resolves
/// the nearest boundary from widget ancestry, which keeps concurrent mounted
/// runtimes from attributing a build failure to the last-mounted instance.
/// Flutter errors that no boundary trap claims are delegated to the previous
/// [FlutterError.onError] handler.
class RuntimeErrorBoundary extends StatefulWidget {
  /// Const constructor.
  const RuntimeErrorBoundary({
    super.key,
    required this.child,
    required this.onError,
    required this.errorReplacement,
    this.onFirstBuildSuccess,
    this.onFirstPaintSuccess,
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

  @override
  State<RuntimeErrorBoundary> createState() => _RuntimeErrorBoundaryState();
}

class _RuntimeErrorBoundaryState extends State<RuntimeErrorBoundary> {
  static final Set<_RuntimeErrorBoundaryState> _mountedBoundaries =
      <_RuntimeErrorBoundaryState>{};
  static ErrorWidgetBuilder? _previousErrorBuilder;
  static FlutterExceptionHandler? _previousOnError;
  static ErrorWidgetBuilder? _installedErrorBuilder;
  static FlutterExceptionHandler? _installedOnError;
  static final List<_PendingFlutterErrorReport> _pendingReports =
      <_PendingFlutterErrorReport>[];
  // Trap builds whose claim arrived before the matching reporter call, keyed by
  // the exact [FlutterErrorDetails] instance. Drained by [_consumeUnmatchedClaim]
  // and cleared when the last boundary unmounts so this static state cannot grow
  // across the process lifetime.
  static final List<FlutterErrorDetails> _unmatchedClaimedDetails =
      <FlutterErrorDetails>[];
  static bool _materializingInformationCollector = false;
  static int _collectorReentrancyGeneration = 0;

  Object? _caught;
  StackTrace? _stack;
  bool _failurePending = false;
  int _failureCaptureGeneration = 0;
  final Set<_PendingFlutterErrorReport> _provisionalReports =
      HashSet<_PendingFlutterErrorReport>.identity();
  _RenderRuntimeErrorBoundaryPaintProbe? _paintProbe;
  bool _successScheduled = false;
  bool _successReported = false;
  bool _paintSuccessScheduled = false;
  bool _paintSuccessReported = false;

  @override
  void initState() {
    super.initState();
    _mountedBoundaries.add(this);
    _installHandlers();
  }

  static void _installHandlers() {
    if (_installedErrorBuilder != null || _installedOnError != null) {
      return;
    }
    _previousErrorBuilder = ErrorWidget.builder;
    _previousOnError = FlutterError.onError;

    _installedOnError = (FlutterErrorDetails details) {
      final claimed = _consumeUnmatchedClaim(details);
      final ownership = claimed ? null : _resolveStructuralOwnership(details);
      final report = _PendingFlutterErrorReport(
        details: details,
        previousOnError: _previousOnError,
        ownership: ownership,
        claimed: claimed,
      );
      ownership?.boundary._holdProvisionalReport(report);
      _pendingReports.add(report);
      scheduleMicrotask(() {
        _pendingReports.remove(report);
        if (report.claimed) return;
        final ownership = report.ownership;
        if (ownership != null) {
          if (ownership.isCurrent) {
            ownership.boundary._commitProvisionalReport(report);
          } else {
            ownership.boundary._cancelProvisionalReport(report);
          }
          return;
        }
        report.previousOnError?.call(report.details);
      });
    };
    FlutterError.onError = _installedOnError;

    // Replace the global ErrorWidget.builder so the build-time error widget
    // resolves the nearest boundary from the insertion point of the failing
    // subtree instead of using whichever boundary mounted last.
    _installedErrorBuilder = (FlutterErrorDetails details) =>
        _RuntimeErrorBoundaryTrap(details: details);
    ErrorWidget.builder = _installedErrorBuilder!;
  }

  static void _restoreHandlersIfIdle() {
    if (_mountedBoundaries.isNotEmpty) return;
    final installedErrorBuilder = _installedErrorBuilder;
    if (installedErrorBuilder != null &&
        ErrorWidget.builder == installedErrorBuilder) {
      ErrorWidget.builder = _previousErrorBuilder!;
    }
    final installedOnError = _installedOnError;
    if (installedOnError != null && FlutterError.onError == installedOnError) {
      FlutterError.onError = _previousOnError;
    }
    _previousErrorBuilder = null;
    _previousOnError = null;
    _installedErrorBuilder = null;
    _installedOnError = null;
    // No boundary is mounted, so nothing can drain these. Clear them rather
    // than retaining unmatched entries for the rest of the process.
    for (final report in _pendingReports) {
      report.ownership?.boundary._cancelProvisionalReport(report);
    }
    _pendingReports.clear();
    _unmatchedClaimedDetails.clear();
    _materializingInformationCollector = false;
    _collectorReentrancyGeneration = 0;
  }

  static _StructuralErrorOwnership? _resolveStructuralOwnership(
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
    if (nearest == null) return null;

    final boundary = nearest.boundary;
    return _StructuralErrorOwnership(
      boundary: boundary,
      marker: nearest,
      markerIncarnation: nearest.incarnation,
      onError: boundary.widget.onError,
      lease: FirstPaintLeaseScope.maybeOf(boundary.context),
    );
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

  static void _claim(FlutterErrorDetails details) {
    final report = _findPendingReport(details);
    if (report != null) {
      report.claimed = true;
      report.ownership?.boundary._cancelProvisionalReport(report);
      return;
    }
    _unmatchedClaimedDetails.add(details);
  }

  static _PendingFlutterErrorReport? _findPendingReport(
    FlutterErrorDetails details,
  ) {
    // Match on the exact details instance only. Flutter passes the same
    // [FlutterErrorDetails] to the reporter and to [ErrorWidget.builder] for a
    // given build failure, so identity is the precise key. Matching on the
    // exception object instead would risk claiming (and suppressing) an
    // unrelated report that happens to carry the same exception instance.
    for (final report in _pendingReports) {
      if (identical(report.details, details)) {
        return report;
      }
    }
    return null;
  }

  static bool _consumeUnmatchedClaim(FlutterErrorDetails details) {
    final index = _unmatchedClaimedDetails.indexWhere(
      (claimed) => identical(claimed, details),
    );
    if (index == -1) {
      return false;
    }
    _unmatchedClaimedDetails.removeAt(index);
    return true;
  }

  void _captureFirst(Object exception, StackTrace? stack) {
    // This runs from the descendant's ErrorWidget during the same build frame.
    // Mark failure synchronously so the success callback already queued by the
    // ancestor boundary cannot win the post-frame race.
    if (_failurePending || _caught != null) return;
    _failurePending = true;
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
        return;
      }
      setState(() {
        _caught = exception;
        _stack = resolvedStack;
      });
      callback(exception, resolvedStack);
    });
    // A report can arrive from independently flushed work or while the
    // scheduler is idle/post-frame. Ensure the registered callback cannot be
    // stranded waiting for some unrelated future frame.
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _holdProvisionalReport(_PendingFlutterErrorReport report) {
    _provisionalReports.add(report);
    final lease = report.ownership?.lease;
    if (lease != null) {
      report.leaseHeld = holdFrameworkPaintErrorForTransaction(lease, report);
    }
  }

  void _cancelProvisionalReport(_PendingFlutterErrorReport report) {
    _provisionalReports.remove(report);
    if (report.leaseHeld) {
      final lease = report.ownership?.lease;
      if (lease != null) {
        releaseFrameworkPaintErrorForTransaction(lease, report);
      }
      report.leaseHeld = false;
    }
  }

  void _commitProvisionalReport(_PendingFlutterErrorReport report) {
    _provisionalReports.remove(report);
    if (report.leaseHeld) {
      final lease = report.ownership?.lease;
      if (lease != null) {
        commitFrameworkRenderFailureForTransaction(lease, report);
      }
      report.leaseHeld = false;
    }
    _captureFirst(report.details.exception, report.details.stack);
  }

  bool get _pipelineBlocked =>
      _failurePending || _provisionalReports.isNotEmpty || _caught != null;

  void _registerPaintProbe(_RenderRuntimeErrorBoundaryPaintProbe probe) {
    _paintProbe = probe;
  }

  @override
  void didUpdateWidget(RuntimeErrorBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.onError, widget.onError)) return;
    for (final report in List<_PendingFlutterErrorReport>.of(
      _provisionalReports,
    )) {
      _cancelProvisionalReport(report);
    }
    if (_caught == null && _failurePending) {
      _failureCaptureGeneration += 1;
      _failurePending = false;
    }
  }

  @override
  void dispose() {
    for (final report in List<_PendingFlutterErrorReport>.of(
      _provisionalReports,
    )) {
      _cancelProvisionalReport(report);
    }
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

class _PendingFlutterErrorReport {
  _PendingFlutterErrorReport({
    required this.details,
    required this.previousOnError,
    required this.ownership,
    required this.claimed,
  });

  final FlutterErrorDetails details;
  final FlutterExceptionHandler? previousOnError;
  final _StructuralErrorOwnership? ownership;
  bool claimed;
  bool leaseHeld = false;
}

class _StructuralErrorOwnership {
  const _StructuralErrorOwnership({
    required this.boundary,
    required this.marker,
    required this.markerIncarnation,
    required this.onError,
    required this.lease,
  });

  final _RuntimeErrorBoundaryState boundary;
  final _RenderRuntimeErrorBoundaryPaintProbe marker;
  final int markerIncarnation;
  final void Function(Object exception, StackTrace stack) onError;
  final FirstPaintLeaseTransaction? lease;

  bool get isCurrent =>
      boundary.mounted &&
      marker.isLive &&
      identical(boundary._paintProbe, marker) &&
      marker.incarnation == markerIncarnation &&
      identical(boundary.widget.onError, onError);
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
  int _incarnation = 0;

  _RuntimeErrorBoundaryState get boundary => _boundary;
  int get incarnation => _incarnation;

  bool get isLive =>
      attached && _boundary.mounted && identical(_boundary._paintProbe, this);

  void updateBoundary(_RuntimeErrorBoundaryState value) {
    _incarnation += 1;
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
}

class _RuntimeErrorBoundaryTrap extends StatelessWidget {
  const _RuntimeErrorBoundaryTrap({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_RuntimeErrorBoundaryScope>();
    final boundary = scope?.boundary;
    if (boundary != null && boundary.mounted) {
      _RuntimeErrorBoundaryState._claim(details);
      FirstPaintLeaseScope.maybeOf(context)?.recordBuildFailure();
      boundary._captureFirst(details.exception, details.stack);
      return const SizedBox.shrink();
    }
    final previous = _RuntimeErrorBoundaryState._previousErrorBuilder;
    if (previous != null) {
      return previous(details);
    }
    return ErrorWidget.withDetails(message: details.exceptionAsString());
  }
}
