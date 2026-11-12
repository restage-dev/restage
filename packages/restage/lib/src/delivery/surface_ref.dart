/// A generated reference to one published surface.
///
/// Pass a list of them to `Restage.configure(surfaces:)` to fetch their
/// latest content in the background at startup.
abstract interface class RestageSurfaceRef {}

/// A reference to a paywall by its id.
final class PaywallRef implements RestageSurfaceRef {
  /// Creates a reference to the paywall [id].
  const PaywallRef(this.id, {this.surfaceWidget, this.completesOn = const {}});

  /// The paywall id, as passed to `RestagePaywall`.
  final String id;

  /// The name of the widget generated for this paywall, when there is one.
  /// Error messages use it to name the widget to switch to.
  final String? surfaceWidget;

  /// The ids of the events that complete this paywall for measurement.
  final Set<String> completesOn;
}
