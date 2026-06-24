import 'package:meta/meta.dart';

/// A product the SDK can purchase.
///
/// Configured at app startup via `Restage.configure(products:)`.
@immutable
final class RestageProduct {
  /// Const constructor.
  ///
  /// Asserts: [id], [slot], and [entitlement] are all non-empty.
  const RestageProduct({
    required this.id,
    required this.slot,
    required this.entitlement,
  })  : assert(id.length > 0, 'id must not be empty'),
        assert(slot.length > 0, 'slot must not be empty'),
        assert(entitlement.length > 0, 'entitlement must not be empty');

  /// Platform store identifier (e.g. App Store Connect product ID).
  final String id;

  /// Author-named slot referenced from paywalls (`'primary'`, `'secondary'`,
  /// `'tertiary'`, or any other string).
  final String slot;

  /// The entitlement granted by purchasing this product.
  final String entitlement;

  @override
  bool operator ==(Object other) =>
      other is RestageProduct &&
      other.id == id &&
      other.slot == slot &&
      other.entitlement == entitlement;

  @override
  int get hashCode => Object.hash(id, slot, entitlement);
}
