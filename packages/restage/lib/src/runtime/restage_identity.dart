import 'package:meta/meta.dart';

/// Optional identity payload supplied by the host via
/// `Restage.configure(identity:)`.
///
/// **Reserved, not yet active.** This type is a forward-declared hook: the
/// `identity` callback is accepted by [Restage.configure] but is not currently
/// invoked, and the values carried here are not yet attached to resolver
/// requests or analytics. It is published now so the shape can stabilize, and
/// is marked [experimental] because the contract may still change before it
/// becomes active. Do not depend on any runtime effect today.
@immutable
@experimental
final class RestageIdentity {
  /// Creates a [RestageIdentity] for [userId] with optional [attributes].
  /// The attributes map is wrapped in an unmodifiable view at construction.
  RestageIdentity({
    required this.userId,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) : attributes = Map.unmodifiable(attributes);

  /// Stable user identifier (e.g., the host app's auth user id).
  final String userId;

  /// Free-form attributes the host wants to attach (tier, signup date, etc).
  /// Unmodifiable.
  final Map<String, Object?> attributes;
}
