/// A generated reference to one published surface.
///
/// Pass a list of them to `Restage.configure(surfaces:)` to fetch their
/// latest content in the background at startup.
abstract interface class RestageSurfaceRef {}

/// A reference to a paywall by its id.
final class PaywallRef implements RestageSurfaceRef {
  /// Creates a reference to the paywall [id].
  const PaywallRef(this.id);

  /// The paywall id, as passed to `RestagePaywall`.
  final String id;
}
