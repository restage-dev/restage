part of 'restage_event.dart';

/// App-wide event: an entitlement was granted (paywallId is null).
final class EntitlementGranted extends RestageEvent {
  /// Const constructor. App-wide event — no [paywallId].
  const EntitlementGranted({
    required this.entitlementId,
    required this.productId,
    required this.source,
    this.expiresAtMs,
    super.firedAt,
  });

  /// Entitlement key (e.g. `'pro'`).
  final String entitlementId;

  /// Platform product identifier that drove the grant.
  final String productId;

  /// How the entitlement was obtained.
  final EntitlementSource source;

  /// Unix timestamp (ms) when the entitlement expires; null if non-expiring.
  final int? expiresAtMs;

  @override
  String get name => 'entitlement_granted';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'entitlementId': entitlementId,
        'productId': productId,
        'source': source.name,
        if (expiresAtMs != null) 'expiresAtMs': expiresAtMs,
      };
}

/// App-wide event: an entitlement was revoked (paywallId is null).
final class EntitlementRevoked extends RestageEvent {
  /// Const constructor. App-wide event — no [paywallId].
  const EntitlementRevoked({
    required this.entitlementId,
    required this.reason,
    super.firedAt,
  });

  /// Entitlement key.
  final String entitlementId;

  /// Why the entitlement was revoked.
  final RevokeReason reason;

  @override
  String get name => 'entitlement_revoked';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'entitlementId': entitlementId,
        'reason': reason.wireName,
      };
}

/// App-wide event: a subscription auto-renewed (paywallId is null).
///
/// Reserved type defined now to lock the API; not emitted by the SDK.
final class SubscriptionRenewed extends RestageEvent {
  /// Const constructor. App-wide event — no [paywallId].
  const SubscriptionRenewed({
    required this.entitlementId,
    required this.productId,
    super.firedAt,
  });

  /// Entitlement key.
  final String entitlementId;

  /// Platform product identifier.
  final String productId;

  @override
  String get name => 'subscription_renewed';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'entitlementId': entitlementId,
        'productId': productId,
      };
}

/// App-wide event: a subscription lapsed (paywallId is null).
///
/// Reserved type defined now to lock the API; not emitted by the SDK.
final class SubscriptionLapsed extends RestageEvent {
  /// Const constructor. App-wide event — no [paywallId].
  const SubscriptionLapsed({
    required this.entitlementId,
    required this.productId,
    super.firedAt,
  });

  /// Entitlement key.
  final String entitlementId;

  /// Platform product identifier.
  final String productId;

  @override
  String get name => 'subscription_lapsed';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'entitlementId': entitlementId,
        'productId': productId,
      };
}
