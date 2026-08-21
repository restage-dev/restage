import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import '../runtime/first_paint_lease_guard.dart';

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

/// Opaque route-lifetime handle consumed by [MeasurementPresentationCommitHook].
///
/// A host creates one handle after it has resolved the mounted published
/// context. Lifecycle transitions can only invalidate it; a handle never moves
/// to another publication or reopens after a terminal transition.
final class MeasurementPresentationRouteHandle {
  MeasurementPresentationRouteHandle._({
    required PublishedSurfaceRevisionV1 publishedSurfaceRevision,
    required MeasurementPresentationCaptureSink captureSink,
    required void Function()? onUncommittedAbort,
  })  : _captureSink = captureSink,
        _onUncommittedAbort = onUncommittedAbort,
        _fact = MeasurementSuccessfulPresentationFact._(
          MeasurementMountedPublishedContext(publishedSurfaceRevision),
        );

  /// Opens an opaque route handle for one mounted published revision.
  factory MeasurementPresentationRouteHandle.open({
    required PublishedSurfaceRevisionV1 publishedSurfaceRevision,
    required MeasurementPresentationCaptureSink captureSink,
    void Function()? onUncommittedAbort,
  }) =>
      MeasurementPresentationRouteHandle._(
        publishedSurfaceRevision: publishedSurfaceRevision,
        captureSink: captureSink,
        onUncommittedAbort: onUncommittedAbort,
      );

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

  bool get _canCommitAfterSuccessfulPaint =>
      _state == _MeasurementPresentationRouteState.active;

  void _abortForUnmount() =>
      _invalidate(_MeasurementPresentationRouteState.aborted);

  void _rejectFailedPaint() {
    if (!_canCommitAfterSuccessfulPaint) return;
    _state = _MeasurementPresentationRouteState.paintFailed;
    _notifyUncommittedAbort();
  }

  void _recordSuccessfulFirstPaint() {
    if (!_canCommitAfterSuccessfulPaint) return;
    _state = _MeasurementPresentationRouteState.delivering;
    try {
      _captureSink.recordSuccessfulPresentation(_fact);
    } on Object {
      _state = _MeasurementPresentationRouteState.captureRejected;
      _notifyUncommittedAbort();
      return;
    }
    if (_state == _MeasurementPresentationRouteState.delivering) {
      _state = _MeasurementPresentationRouteState.committed;
    }
  }

  void _invalidate(_MeasurementPresentationRouteState state) {
    if (_state != _MeasurementPresentationRouteState.active &&
        _state != _MeasurementPresentationRouteState.delivering) {
      return;
    }
    _state = state;
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
