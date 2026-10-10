import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import '../runtime/first_paint_lease_guard.dart';
import 'presentation_attempt_summary.dart';

part 'presentation_commit_hook.dart';

/// Receives one successful presentation fact through the bounded capture path.
///
/// Implementations must synchronously perform only their own bounded in-memory
/// update. This hook supplies no event name, callback argument, or widget-tree
/// data to reconstruct.
abstract interface class MeasurementPresentationCaptureSink {
  /// Records one successfully painted mounted publication.
  void recordSuccessfulPresentation(MeasurementSuccessfulPresentationFact fact);
}

/// Exact published context of the root artifact mounted by one presentation.
///
/// [publishedSurfaceRevision] seals the exact artifact graph and complete
/// measurement manifest. The root artifact coordinates are derived from that
/// immutable published authority rather than accepted as independently mutable
/// input.
final class MeasurementMountedPublishedContext {
  /// Creates a mounted context from its published revision authority.
  const MeasurementMountedPublishedContext(this.publishedSurfaceRevision);

  /// Immutable authority sealing this mounted publication.
  final PublishedSurfaceRevisionV1 publishedSurfaceRevision;

  /// Exact mounted root artifact.
  ArtifactId get rootArtifactId => publishedSurfaceRevision.rootArtifactId;

  /// Exact mounted root occurrence in the sealed artifact graph.
  ArtifactOccurrenceEdgeToken get rootArtifactOccurrenceEdgeToken =>
      publishedSurfaceRevision.rootArtifactOccurrenceEdgeToken;

  /// Exact graph sealed by [publishedSurfaceRevision].
  CanonicalDigest get artifactGraphHash =>
      publishedSurfaceRevision.artifactGraphHash;

  /// Exact complete manifest sealed by [publishedSurfaceRevision].
  CanonicalDigest get measurementManifestHash =>
      publishedSurfaceRevision.measurementManifestHash;
}

/// One successful first-paint fact for an exact mounted publication.
///
/// This fact intentionally carries only the sealed mounted context. It has no
/// event carrier, author callback name, arguments, runtime-tree data, subject,
/// finality mutation, or missingness mutation.
final class MeasurementSuccessfulPresentationFact {
  const MeasurementSuccessfulPresentationFact._(this.context);

  /// Immutable context for the presentation that painted successfully.
  final MeasurementMountedPublishedContext context;
}

/// The first-paint route a [MeasurementPresentationCommitHook] reports to.
sealed class MeasurementPresentationRoute {
  bool get _canCommitAfterSuccessfulPaint;
  void _rejectFailedPaint();
  void _recordGenuineRootPresentation();
  void _recordSuccessfulFirstPaint();
  void _abortForUnmount();
}

/// Holds one mount's first-paint outcome until its session opens.
///
/// [bind] replays the held outcome onto the session's route; later reports
/// go straight to it.
final class MeasurementPendingPresentationRoute
    implements MeasurementPresentationRoute {
  MeasurementPresentationRouteHandle? _bound;
  var _painted = false;
  var _paintFailed = false;
  var _unmounted = false;
  var _genuineRootPresentations = 0;

  /// Replays the held outcome onto [handle] and forwards from now on.
  void bind(MeasurementPresentationRouteHandle handle) {
    if (_bound != null) return;
    _bound = handle;
    for (var i = 0; i < _genuineRootPresentations; i += 1) {
      handle._recordGenuineRootPresentation();
    }
    if (_painted) {
      handle._recordSuccessfulFirstPaint();
    } else if (_paintFailed) {
      handle._rejectFailedPaint();
    }
    if (_unmounted) handle.abandon();
  }

  bool get _held => !_painted && !_paintFailed && !_unmounted;

  @override
  bool get _canCommitAfterSuccessfulPaint =>
      _bound?._canCommitAfterSuccessfulPaint ?? _held;

  @override
  void _rejectFailedPaint() {
    final bound = _bound;
    if (bound != null) return bound._rejectFailedPaint();
    if (_held) _paintFailed = true;
  }

  @override
  void _recordGenuineRootPresentation() {
    final bound = _bound;
    if (bound != null) return bound._recordGenuineRootPresentation();
    _genuineRootPresentations += 1;
  }

  @override
  void _recordSuccessfulFirstPaint() {
    final bound = _bound;
    if (bound != null) return bound._recordSuccessfulFirstPaint();
    if (_held) _painted = true;
  }

  @override
  void _abortForUnmount() {
    final bound = _bound;
    if (bound != null) return bound._abortForUnmount();
    _unmounted = true;
  }
}

/// Opaque route-lifetime handle consumed by [MeasurementPresentationCommitHook].
///
/// A host creates one handle after it has resolved the mounted published
/// context. Lifecycle transitions can only invalidate it; a handle never moves
/// to another publication or reopens after a terminal transition.
final class MeasurementPresentationRouteHandle
    implements MeasurementPresentationRoute {
  MeasurementPresentationRouteHandle._({
    required PublishedSurfaceRevisionV1 publishedSurfaceRevision,
    required MeasurementPresentationCaptureSink captureSink,
    required void Function()? onUncommittedAbort,
    required MeasurementPresentationAttemptObserver? observer,
  })  : _captureSink = captureSink,
        _onUncommittedAbort = onUncommittedAbort,
        _observer = observer,
        _fact = MeasurementSuccessfulPresentationFact._(
          MeasurementMountedPublishedContext(publishedSurfaceRevision),
        );

  /// Opens an opaque route handle for one mounted published revision.
  factory MeasurementPresentationRouteHandle.open({
    required PublishedSurfaceRevisionV1 publishedSurfaceRevision,
    required MeasurementPresentationCaptureSink captureSink,
    void Function()? onUncommittedAbort,
    MeasurementPresentationAttemptObserver? observer,
  }) =>
      MeasurementPresentationRouteHandle._(
        publishedSurfaceRevision: publishedSurfaceRevision,
        captureSink: captureSink,
        onUncommittedAbort: onUncommittedAbort,
        observer: observer,
      );

  final MeasurementPresentationAttemptObserver? _observer;
  final MeasurementPresentationCaptureSink _captureSink;
  final void Function()? _onUncommittedAbort;
  final MeasurementSuccessfulPresentationFact _fact;

  _MeasurementPresentationRouteState _state =
      _MeasurementPresentationRouteState.active;

  /// Invalidates this handle because a newer route now owns the mount.
  void supersede() =>
      _invalidate(_MeasurementPresentationRouteState.superseded);

  /// Invalidates this handle because the capture lifecycle has rolled over.
  void rollover() => _invalidate(_MeasurementPresentationRouteState.rolledOver);

  @override
  bool get _canCommitAfterSuccessfulPaint =>
      _state == _MeasurementPresentationRouteState.active;

  /// Invalidates this handle because the host abandoned the presentation.
  void abandon() => _invalidate(_MeasurementPresentationRouteState.aborted);

  @override
  void _abortForUnmount() => abandon();

  /// Drives the failed-paint transition for a test.
  @visibleForTesting
  void rejectFailedPaintForTest() => _rejectFailedPaint();

  @override
  void _rejectFailedPaint() {
    if (!_canCommitAfterSuccessfulPaint) return;
    _state = _MeasurementPresentationRouteState.paintFailed;
    _observer?.recordFinish(MeasurementPresentationFinishReasonV1.paintFailed);
    _notifyUncommittedAbort();
  }

  /// Counts one genuine root paint report, whatever the route can still do.
  @override
  void _recordGenuineRootPresentation() => _observer?.recordRootPresentation();

  @override
  void _recordSuccessfulFirstPaint() {
    if (!_canCommitAfterSuccessfulPaint) return;
    _state = _MeasurementPresentationRouteState.delivering;
    try {
      _captureSink.recordSuccessfulPresentation(_fact);
    } on Object {
      _state = _MeasurementPresentationRouteState.captureRejected;
      _observer?.recordCaptureIncomplete();
      _observer
          ?.recordFinish(MeasurementPresentationFinishReasonV1.captureRejected);
      _notifyUncommittedAbort();
      return;
    }
    if (_state == _MeasurementPresentationRouteState.delivering) {
      _state = _MeasurementPresentationRouteState.committed;
      _observer?.recordFinish(MeasurementPresentationFinishReasonV1.committed);
    }
  }

  void _invalidate(_MeasurementPresentationRouteState state) {
    if (_state != _MeasurementPresentationRouteState.active &&
        _state != _MeasurementPresentationRouteState.delivering) {
      return;
    }
    _state = state;
    final reason = switch (state) {
      _MeasurementPresentationRouteState.aborted =>
        MeasurementPresentationFinishReasonV1.abandoned,
      _MeasurementPresentationRouteState.superseded =>
        MeasurementPresentationFinishReasonV1.superseded,
      _ => null,
    };
    if (reason != null) _observer?.recordFinish(reason);
    _notifyUncommittedAbort();
  }

  void _notifyUncommittedAbort() {
    try {
      _onUncommittedAbort?.call();
    } on Object {
      // A construction-plane abort cannot affect the mounted host subtree.
    }
  }
}

enum _MeasurementPresentationRouteState {
  active,
  delivering,
  committed,
  aborted,
  superseded,
  rolledOver,
  paintFailed,
  captureRejected,
}
