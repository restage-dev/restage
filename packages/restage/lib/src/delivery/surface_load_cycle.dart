import 'dart:async';

import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

import '../events/restage_event.dart';
import '../measurement/measurement_resolved_publication_provenance.dart'
    show surfaceResolutionSourceFor;
import '../resolver/surface_resolution_report.dart';
import 'render_deadline.dart';

/// One load of a mount: a start, then at most one completion or failure.
///
/// The terminal events are built only from what the mount paints, through
/// `SurfaceLoadPaint`; each method returns null once the load has settled.
@internal
final class SurfaceLoad {
  /// Starts timing a load that waits on [deadline].
  SurfaceLoad({
    required this.surfaceId,
    required this.surface,
    required this.deadline,
  });

  /// The surface or placement identifier the mount loads.
  final String surfaceId;

  /// The category the mount declares.
  final Surface surface;

  /// The waits this load races its content against.
  final RenderDeadline deadline;

  final Stopwatch _sinceStart = Stopwatch()..start();
  void Function(RestageEvent event)? _startEmitter;
  bool _started = false;
  bool _settled = false;

  /// Whether the load already completed or failed.
  bool get isSettled => _settled;

  /// Fires the start event through [emit] after the current frame's work, so
  /// a mount's callback never runs while the mount is being built.
  void start(void Function(RestageEvent event) emit) {
    if (_started) return;
    _started = true;
    _startEmitter = emit;
    scheduleMicrotask(_flushStart);
  }

  void _flushStart() {
    final emit = _startEmitter;
    _startEmitter = null;
    emit?.call(SurfaceLoadStarted(surfaceId: surfaceId, surface: surface));
  }

  /// The completion for the painted [leaf] (or [winner]), or for the original
  /// when both are null.
  SurfaceLoadCompleted? complete(Object? leaf, [Object? winner]) {
    if (!_settle()) return null;
    return SurfaceLoadCompleted(
      surfaceId: surfaceId,
      surface: surface,
      source: surfaceLoadSourceOf(leaf, winner),
      elapsed: _sinceStart.elapsed,
      firstLaunchWaitPassed: deadline.passedWhenSettled,
      freshWindowPassed: deadline.windowPassedWhenSettled,
    );
  }

  /// The failure when the mount paints nothing; [detail] is the mount's code.
  SurfaceLoadFailed? fail(SurfaceLoadFailureReason reason, {String? detail}) {
    if (!_settle()) return null;
    return SurfaceLoadFailed(
      surfaceId: surfaceId,
      surface: surface,
      reason: reason,
      detail: detail,
      elapsed: _sinceStart.elapsed,
    );
  }

  bool _settle() {
    if (_settled) return false;
    _settled = true;
    _flushStart();
    return true;
  }
}

/// Maps the source label delivery attached to [leaf] (else [winner]):
/// fresh is delivered, holdLastGood is saved, and bundled or unlabelled
/// content is the original.
@internal
SurfaceLoadSource surfaceLoadSourceOf(Object? leaf, [Object? winner]) {
  final source = _labelOf(leaf) ?? _labelOf(winner);
  return switch (source) {
    SurfaceResolutionSource.fresh => SurfaceLoadSource.delivered,
    SurfaceResolutionSource.holdLastGood => SurfaceLoadSource.saved,
    SurfaceResolutionSource.bundled || null => SurfaceLoadSource.original,
  };
}

SurfaceResolutionSource? _labelOf(Object? resolved) =>
    resolved == null ? null : surfaceResolutionSourceFor(resolved);

/// The shared failure reason for a mount's own failure [code].
@internal
SurfaceLoadFailureReason surfaceLoadFailureFor(String code) => switch (code) {
      'render_error' || 'render_failed' => SurfaceLoadFailureReason.renderError,
      'delivery_unavailable' ||
      'asset_not_found' ||
      'not_stored' ||
      'placement_expired' ||
      'placement_unavailable' =>
        SurfaceLoadFailureReason.unavailable,
      'unknown' || 'resolve_failed' => SurfaceLoadFailureReason.unknown,
      _ when code.endsWith('_unavailable') =>
        SurfaceLoadFailureReason.unavailable,
      'decode_failed' ||
      'validation_failed' =>
        SurfaceLoadFailureReason.invalid,
      _ when code.endsWith('_mismatch') || code.startsWith('unsupported_') =>
        SurfaceLoadFailureReason.invalid,
      _ => SurfaceLoadFailureReason.unknown,
    };
