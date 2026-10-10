import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

/// Where a resolved surface's content came from.
enum SurfaceResolutionSource {
  /// A fresh decision from the service.
  fresh,

  /// The last good decision this install already held.
  holdLastGood,

  /// The content bundled in the app.
  bundled,
}

/// One resolution, reported to a host that opted in.
@immutable
final class SurfaceResolutionReport {
  /// Creates one resolution report.
  const SurfaceResolutionReport({
    required this.surface,
    required this.source,
    this.surfaceType,
    this.reason,
    this.selectedRouteId,
    this.audienceRevisionRef,
    this.routingRevisionOrdinal,
    this.rolloutAllocationId,
    this.rolloutBranch,
    this.defaultSelectionReason,
  });

  /// The resolved surface slug.
  final String surface;

  /// The exact closed category of the resolved surface.
  ///
  /// SDK-produced reports always carry this value. It remains optional so
  /// existing hosts that construct this public DTO directly remain source
  /// compatible; consumers must not infer a category when it is absent.
  final Surface? surfaceType;

  /// Where its content came from.
  final SurfaceResolutionSource source;

  /// A short reason, when the client has one.
  final String? reason;

  /// The selected route identifier.
  final String? selectedRouteId;

  /// The audience revision reference.
  final String? audienceRevisionRef;

  /// The non-negative routing revision ordinal.
  final int? routingRevisionOrdinal;

  /// The rollout allocation identifier.
  final String? rolloutAllocationId;

  /// The rollout branch.
  final String? rolloutBranch;

  /// The bounded reason for a default selection.
  final String? defaultSelectionReason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SurfaceResolutionReport &&
          surface == other.surface &&
          surfaceType == other.surfaceType &&
          source == other.source &&
          reason == other.reason &&
          selectedRouteId == other.selectedRouteId &&
          audienceRevisionRef == other.audienceRevisionRef &&
          routingRevisionOrdinal == other.routingRevisionOrdinal &&
          rolloutAllocationId == other.rolloutAllocationId &&
          rolloutBranch == other.rolloutBranch &&
          defaultSelectionReason == other.defaultSelectionReason;

  @override
  int get hashCode => Object.hash(
      surface,
      surfaceType,
      source,
      reason,
      selectedRouteId,
      audienceRevisionRef,
      routingRevisionOrdinal,
      rolloutAllocationId,
      rolloutBranch,
      defaultSelectionReason);

  @override
  String toString() =>
      'SurfaceResolutionReport(surface: $surface, surfaceType: $surfaceType, source: $source, reason: $reason, selectedRouteId: $selectedRouteId, audienceRevisionRef: $audienceRevisionRef, routingRevisionOrdinal: $routingRevisionOrdinal, rolloutAllocationId: $rolloutAllocationId, rolloutBranch: $rolloutBranch, defaultSelectionReason: $defaultSelectionReason)';
}
