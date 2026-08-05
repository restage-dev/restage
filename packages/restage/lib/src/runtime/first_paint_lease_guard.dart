import 'dart:async';
import 'dart:collection';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// State of an SDK-internal first-paint transaction.
enum _FirstPaintLeaseState {
  pending,
  committed,
  rejected,
  buildFailed,
  superseded,
}

/// Joins final lease validation to private host ownership at first paint.
///
/// The synchronous callbacks must only inspect and mutate SDK-private state.
/// User callbacks, listener notifications, disposal, and widget updates belong
/// in [afterCommit] or [afterRejection], which run after the paint frame.
final class FirstPaintLeaseTransaction {
  FirstPaintLeaseTransaction({
    bool Function()? isReady,
    bool Function()? isInvalidatedByIdentityReset,
    required bool Function() canCommit,
    required VoidCallback commit,
    VoidCallback? onPainted,
    required VoidCallback afterCommit,
    required VoidCallback afterRejection,
    VoidCallback? onAbandon,
  })  : _isReady = isReady ?? _alwaysReady,
        _isInvalidatedByIdentityReset =
            isInvalidatedByIdentityReset ?? _neverInvalidated,
        _canCommit = canCommit,
        _commit = commit,
        _onPainted = onPainted,
        _afterCommit = afterCommit,
        _afterRejection = afterRejection,
        _onAbandon = onAbandon {
    _pendingTransactions.add(this);
  }

  static final Set<FirstPaintLeaseTransaction> _pendingTransactions =
      <FirstPaintLeaseTransaction>{};
  static final List<FirstPaintLeaseTransaction> _paintingTransactions =
      <FirstPaintLeaseTransaction>[];

  /// Test-only failure injection immediately before guarded descendant paint.
  ///
  /// Production leaves this null. Tests use it to hold the transaction between
  /// synchronous ownership commit and descendant paint acknowledgement.
  static void Function(FirstPaintLeaseTransaction transaction)?
      debugBeforeDescendantPaint;

  final bool Function() _isReady;
  final bool Function() _isInvalidatedByIdentityReset;
  final bool Function() _canCommit;
  final VoidCallback _commit;
  final VoidCallback? _onPainted;
  final VoidCallback _afterCommit;
  final VoidCallback _afterRejection;
  final VoidCallback? _onAbandon;

  _FirstPaintLeaseState _state = _FirstPaintLeaseState.pending;
  bool _followUpScheduled = false;
  bool _rejectionProbeScheduled = false;
  bool _abandonmentReported = false;
  bool _paintReported = false;
  bool _frameworkRenderFailed = false;
  final Set<Object> _frameworkPaintFailureTokens = HashSet<Object>.identity();

  bool get isPending => _state == _FirstPaintLeaseState.pending;
  bool get isCommitted => _state == _FirstPaintLeaseState.committed;

  /// Whether guarded descendant paint returned successfully at least once.
  ///
  /// Commitment is only the synchronous pre-paint ownership mutation. Hosts
  /// must use this acknowledgement before treating that provisional owner as
  /// the accepted presentation.
  bool get isPaintAcknowledged => _paintReported;

  bool get isReady => _isReady();

  /// Whether framework-owned rendering can still acknowledge success.
  bool get canReportFrameworkRenderSuccess =>
      !_frameworkRenderFailed && _frameworkPaintFailureTokens.isEmpty;

  /// Marks a descendant build failure before this frame reaches paint.
  void recordBuildFailure() {
    if (!isPending) return;
    _state = _FirstPaintLeaseState.buildFailed;
    _pendingTransactions.remove(this);
    _reportAbandonment();
  }

  /// Makes an overlapping candidate permanently ineligible to commit.
  void supersede() {
    if (!isPending) return;
    _state = _FirstPaintLeaseState.superseded;
    _pendingTransactions.remove(this);
    _reportAbandonment();
  }

  bool _admitPaint() {
    if (isCommitted) return true;
    if (!isPending) return false;
    // A hosted flow loading builder is outside the transaction. It can paint
    // normally until a concrete screen entry exists.
    if (!isReady) return true;
    if (!_canCommit()) {
      _state = _FirstPaintLeaseState.rejected;
      _pendingTransactions.remove(this);
      _reportAbandonment();
      _scheduleRejectionFollowUp();
      return false;
    }

    // No asynchronous work, widget mutation, disposal, listener notification,
    // or host callback may be inserted between this final check and ownership
    // mutation. The transaction becomes pinned before descendant paint.
    _commit();
    _state = _FirstPaintLeaseState.committed;
    _pendingTransactions.remove(this);
    return true;
  }

  /// Registers the deferred host acknowledgement only after descendant paint
  /// returned normally. A paint exception therefore cannot report commitment.
  void _didPaint() {
    if (!isCommitted || !canReportFrameworkRenderSuccess) return;
    if (!_paintReported) {
      _paintReported = true;
      _onPainted?.call();
    }
    _scheduleFollowUp(_afterCommit);
  }

  /// Rejects stale work after descendant build/layout, without accepting it.
  /// A candidate that is still valid is always checked again at paint.
  void _rejectBeforePaintIfInvalid() {
    if (!isPending || !isReady || _canCommit()) return;
    _state = _FirstPaintLeaseState.rejected;
    _pendingTransactions.remove(this);
    _reportAbandonment();
    _scheduleRejectionFollowUp();
  }

  /// Revalidates all pending render work after an SDK actor reset.
  ///
  /// This can only reject. Cleanup remains post-frame, and successful ownership
  /// can still move only through [_admitPaint].
  static void revalidatePendingAfterIdentityReset() {
    for (final transaction in List<FirstPaintLeaseTransaction>.of(
      _pendingTransactions,
    )) {
      transaction._rejectAfterIdentityResetIfInvalid();
    }
  }

  bool _holdFrameworkPaintError(Object token) {
    if (!isPending && !isCommitted) return false;
    _frameworkPaintFailureTokens.add(token);
    return true;
  }

  void _releaseFrameworkPaintError(Object token) {
    _frameworkPaintFailureTokens.remove(token);
  }

  void _commitFrameworkRenderFailure(Object token) {
    if (!_frameworkPaintFailureTokens.contains(token)) return;
    _frameworkRenderFailed = true;
    _frameworkPaintFailureTokens.remove(token);
  }

  void _beginPaintObservation() {
    _paintingTransactions.add(this);
  }

  bool _endPaintObservation() {
    final index = _paintingTransactions.lastIndexWhere(
      (transaction) => identical(transaction, this),
    );
    if (index != -1) _paintingTransactions.removeAt(index);
    return canReportFrameworkRenderSuccess;
  }

  void _rejectAfterIdentityResetIfInvalid() {
    if (!isPending || !_isInvalidatedByIdentityReset()) return;
    _state = _FirstPaintLeaseState.rejected;
    _pendingTransactions.remove(this);
    _reportAbandonment();
    _scheduleRejectionFollowUp();
  }

  /// Arms one post-frame stale probe for descendants that can build before the
  /// guarded render subtree is laid out or painted. A valid candidate is never
  /// accepted here; successful authority still moves only in [_admitPaint].
  void _scheduleRejectionProbe() {
    if (!isPending || _rejectionProbeScheduled) return;
    _rejectionProbeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rejectionProbeScheduled = false;
      _rejectBeforePaintIfInvalid();
    });
  }

  void _scheduleFollowUp(VoidCallback callback) {
    if (_followUpScheduled) return;
    _followUpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_frameworkRenderFailed) return;
      callback();
    });
  }

  void _scheduleRejectionFollowUp() {
    if (_followUpScheduled) return;
    _followUpScheduled = true;
    scheduleMicrotask(_afterRejection);
  }

  void _reportAbandonment() {
    if (_abandonmentReported) return;
    _abandonmentReported = true;
    _onAbandon?.call();
  }

  static bool _alwaysReady() => true;
  static bool _neverInvalidated() => false;
}

/// Provisionally marks [transaction] when a structurally owned framework
/// report occurs before or during its descendant paint.
bool holdFrameworkPaintErrorForTransaction(
  FirstPaintLeaseTransaction transaction,
  Object token,
) =>
    transaction._holdFrameworkPaintError(token);

/// Reverses a provisional framework-paint mark when the exact report is later
/// claimed as a nested build failure or its captured owner becomes stale.
void releaseFrameworkPaintErrorForTransaction(
  FirstPaintLeaseTransaction transaction,
  Object token,
) {
  transaction._releaseFrameworkPaintError(token);
}

/// Permanently prevents render success after definitive structural ownership.
///
/// The exact provisional [token] must still be held, so build claims and stale
/// ownership cancellation cannot poison the transaction.
void commitFrameworkRenderFailureForTransaction(
  FirstPaintLeaseTransaction transaction,
  Object token,
) {
  transaction._commitFrameworkRenderFailure(token);
}

/// Exposes [transaction] to nested runtime error boundaries without registering
/// a dependency on it.
final class FirstPaintLeaseScope extends InheritedWidget {
  const FirstPaintLeaseScope({
    super.key,
    required this.transaction,
    required super.child,
  });

  final FirstPaintLeaseTransaction transaction;

  static FirstPaintLeaseTransaction? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<FirstPaintLeaseScope>()
      ?.transaction;

  @override
  bool updateShouldNotify(FirstPaintLeaseScope oldWidget) =>
      !identical(transaction, oldWidget.transaction);
}

/// Paints a candidate only after its transaction synchronously commits.
final class FirstPaintLeaseGuard extends SingleChildRenderObjectWidget {
  const FirstPaintLeaseGuard({
    super.key,
    required this.transaction,
    required this.armed,
    required super.child,
  });

  final FirstPaintLeaseTransaction transaction;
  final bool armed;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderFirstPaintLeaseGuard(transaction, armed).._scheduleProbeIfArmed();

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFirstPaintLeaseGuard renderObject,
  ) {
    renderObject
      ..transaction = transaction
      ..armed = armed
      .._scheduleProbeIfArmed();
  }
}

final class RenderFirstPaintLeaseGuard extends RenderProxyBox {
  RenderFirstPaintLeaseGuard(this._transaction, this._armed);

  FirstPaintLeaseTransaction _transaction;
  bool _armed;

  set transaction(FirstPaintLeaseTransaction value) {
    if (identical(_transaction, value)) return;
    _transaction = value;
    _scheduleProbeIfArmed();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  set armed(bool value) {
    if (_armed == value) return;
    _armed = value;
    _scheduleProbeIfArmed();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  bool get _admitsInteraction =>
      !_armed || !_transaction.isReady || _transaction.isCommitted;

  void _scheduleProbeIfArmed() {
    if (_armed) _transaction._scheduleRejectionProbe();
  }

  @override
  void performLayout() {
    super.performLayout();
    if (_armed) _transaction._rejectBeforePaintIfInvalid();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_admitsInteraction) return false;
    return super.hitTest(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_armed) {
      super.paint(context, offset);
      return;
    }
    if (!_transaction._admitPaint()) return;
    var returnedNormally = false;
    _transaction._beginPaintObservation();
    try {
      FirstPaintLeaseTransaction.debugBeforeDescendantPaint?.call(
        _transaction,
      );
      super.paint(context, offset);
      returnedNormally = true;
    } finally {
      final paintSucceeded = _transaction._endPaintObservation();
      if (returnedNormally && paintSucceeded) {
        _transaction._didPaint();
      }
    }
  }
}
