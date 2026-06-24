import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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
  });

  /// The subtree to guard.
  final Widget child;

  /// Called once when the first exception is caught from [child]'s subtree.
  final void Function(Object exception, StackTrace stack) onError;

  /// Called by [build] when an exception has been caught, in place of [child].
  /// The default fallback should be benign (e.g. [SizedBox.shrink]).
  final Widget Function(
          BuildContext context, Object exception, StackTrace stack)
      errorReplacement;

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

  Object? _caught;
  StackTrace? _stack;

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
      final report = _PendingFlutterErrorReport(
        details: details,
        previousOnError: _previousOnError,
        claimed: _consumeUnmatchedClaim(details),
      );
      _pendingReports.add(report);
      scheduleMicrotask(() {
        _pendingReports.remove(report);
        if (!report.claimed) {
          report.previousOnError?.call(report.details);
        }
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
    _pendingReports.clear();
    _unmatchedClaimedDetails.clear();
  }

  static void _claim(FlutterErrorDetails details) {
    final report = _findPendingReport(details);
    if (report != null) {
      report.claimed = true;
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
    final resolvedStack = stack ?? StackTrace.current;
    // Defer setState until after the current build/frame so we don't
    // recurse into ourselves.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _caught != null) return;
      setState(() {
        _caught = exception;
        _stack = resolvedStack;
      });
      widget.onError(exception, resolvedStack);
    });
  }

  @override
  void dispose() {
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
    return _RuntimeErrorBoundaryScope(
      boundary: this,
      child: widget.child,
    );
  }
}

class _PendingFlutterErrorReport {
  _PendingFlutterErrorReport({
    required this.details,
    required this.previousOnError,
    required this.claimed,
  });

  final FlutterErrorDetails details;
  final FlutterExceptionHandler? previousOnError;
  bool claimed;
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
