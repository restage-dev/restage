import 'package:meta/meta.dart';

import '../flow/flow_descriptors.dart' show SurfaceEvent;
import '../runtime/placement_mount.dart' show SurfacePresentationRequirement;

/// Marks a Flutter widget class as a specialized paywall source.
///
/// A paywall is independently published under [Surface.paywall] and may also
/// appear inside a flow of any supported category. Its specialized runtime
/// behavior is selected by source kind, not by the containing flow's category.
@immutable
final class Paywall {
  /// Creates a paywall annotation.
  const Paywall({
    this.id,
    this.completesOn = const [],
    this.presentation = SurfacePresentationRequirement.infer,
  });

  /// Optional stable source identity.
  final String? id;

  /// Declared events whose taps mark the paywall interaction as completed for
  /// measurement rather than dismissed.
  ///
  /// The host still handles purchases and navigation. This does not close a
  /// route or advance a flow.
  final List<SurfaceEvent<Object?>> completesOn;

  /// Narrows the presentation modes the complete compiled paywall must prove.
  final SurfacePresentationRequirement presentation;
}

/// Legacy source annotation for a specialized paywall.
///
/// New source should use [Paywall]. This annotation retains its legacy
/// required-ID shape while the generator continues to support it.
@Deprecated('Use @Paywall(...) instead.')
@immutable
final class PaywallSource {
  /// Creates a legacy paywall source annotation.
  const PaywallSource({
    required this.id,
    this.presentation = SurfacePresentationRequirement.infer,
  });

  /// Stable paywall identifier.
  final String id;

  /// Narrows the presentation modes the complete compiled paywall must prove.
  final SurfacePresentationRequirement presentation;
}
