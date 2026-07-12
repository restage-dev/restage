import 'package:flutter/foundation.dart' show immutable;

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
