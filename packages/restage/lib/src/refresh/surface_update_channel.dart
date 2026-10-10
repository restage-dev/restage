import 'package:flutter/foundation.dart' show immutable;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

/// Wire identity of a deliverable surface: its type + slug.
@immutable
class SurfaceRef {
  /// Const constructor.
  const SurfaceRef({required this.surfaceType, required this.slug});

  /// Surface type wire name (e.g. `'paywall'`, `'onboarding'`).
  final String surfaceType;

  /// Stable surface identifier (e.g. `'pro_upgrade'`).
  final String slug;

  @override
  bool operator ==(Object other) =>
      other is SurfaceRef &&
      other.surfaceType == surfaceType &&
      other.slug == slug;

  @override
  int get hashCode => Object.hash(surfaceType, slug);

  @override
  String toString() => 'SurfaceRef($surfaceType/$slug)';
}

/// Signal that [surface]'s published content may have changed.
@immutable
class SurfaceUpdate {
  /// Const constructor.
  const SurfaceUpdate(this.surface);

  /// The surface whose content may have changed.
  final SurfaceRef surface;
}

/// A source of "this surface's content may have changed" signals.
///
/// The SDK subscribes while a surface is mounted, foregrounded, and has
/// live updates enabled for it, and cancels the subscription on
/// dispose/background. On each emission the SDK re-resolves the surface
/// through its normal delivery path, skips unchanged content, and applies
/// changes through the swap-safety gate — a channel signals opportunity, it
/// can never force a swap.
///
/// Implement this to drive live refresh from your own infrastructure (your
/// push provider, your own socket, etc.) and pass it to
/// `Restage.configure(updateChannel: ...)`.
abstract interface class SurfaceUpdateChannel {
  /// A broadcast-safe stream of change signals for [surface].
  Stream<SurfaceUpdate> watch(SurfaceRef surface);
}

/// Optional change signals for complete placement decision dependencies.
abstract interface class DeliveryUpdateChannel implements SurfaceUpdateChannel {
  /// Watches one exact policy scope, including its target and family.
  Stream<DeliveryPolicyScopeV1> watchDelivery(
    DeliveryPolicyScopeV1 scope, {
    PlacementDeliveryWatchV1? watch,
    Future<PlacementRefreshProbeV1> Function()? reconnectProbe,
  });
}

/// The immutable decision accepted by a placement host.
typedef PlacementRefreshStateV1 = ({
  PlacementMountDescriptorV1 mount,
  CanonicalDigest decisionIdentityDigest,
  DeliveryDependencyClosureV1 dependencies,
});

/// The result of checking an accepted decision without mounting content.
sealed class PlacementRefreshProbeV1 {
  const PlacementRefreshProbeV1();

  /// An authoritative exact decision digest.
  const factory PlacementRefreshProbeV1.unchanged(CanonicalDigest digest,
      {PlacementDeliveryWatchV1? watch}) = PlacementRefreshUnchangedV1;

  /// The decision must be resolved through normal delivery.
  const factory PlacementRefreshProbeV1.requiresResolution() =
      PlacementRefreshRequiresResolutionV1;

  /// A throttled probe retains the current presentation.
  const factory PlacementRefreshProbeV1.rateLimited(Duration retryAfter) =
      PlacementRefreshRateLimitedV1;

  /// Missing authority requires normal delivery resolution.
  const factory PlacementRefreshProbeV1.unavailable() =
      PlacementRefreshUnavailableV1;
}

final class PlacementRefreshUnchangedV1 extends PlacementRefreshProbeV1 {
  const PlacementRefreshUnchangedV1(this.decisionIdentityDigest, {this.watch});

  final CanonicalDigest decisionIdentityDigest;
  final PlacementDeliveryWatchV1? watch;
}

final class PlacementRefreshRequiresResolutionV1
    extends PlacementRefreshProbeV1 {
  const PlacementRefreshRequiresResolutionV1();
}

final class PlacementRefreshRateLimitedV1 extends PlacementRefreshProbeV1 {
  const PlacementRefreshRateLimitedV1(this.retryAfter);

  final Duration retryAfter;
}

final class PlacementRefreshUnavailableV1 extends PlacementRefreshProbeV1 {
  const PlacementRefreshUnavailableV1();
}
