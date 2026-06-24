import 'package:meta/meta.dart';

/// How an entitlement was obtained.
enum EntitlementSource {
  /// Newly purchased in the current session.
  purchase,

  /// Restored from prior purchases (e.g. user re-installs the app).
  restore,

  /// Auto-renewed by the platform store.
  renewal,

  /// Granted promotionally (e.g. server-side comp, free-trial grant).
  promotional,
}

/// An abstract feature gate the user has access to (e.g. `'pro'`).
@immutable
final class RestageEntitlement {
  /// Const constructor.
  const RestageEntitlement({
    required this.id,
    required this.source,
    this.expiresAtMs,
  });

  /// Entitlement key referenced by `RestageProduct.entitlement` and by
  /// app code performing access checks.
  final String id;

  /// How this entitlement was obtained.
  final EntitlementSource source;

  /// Unix timestamp in milliseconds when the entitlement expires, or
  /// `null` for non-expiring entitlements.
  final int? expiresAtMs;

  @override
  bool operator ==(Object other) =>
      other is RestageEntitlement &&
      other.id == id &&
      other.source == source &&
      other.expiresAtMs == expiresAtMs;

  @override
  int get hashCode => Object.hash(id, source, expiresAtMs);
}
