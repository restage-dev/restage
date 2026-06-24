part of 'restage_event.dart';

/// Fired when a paywall begins loading its `.rfw` blob.
final class PaywallLoadStarted extends RestageEvent {
  /// Const constructor.
  const PaywallLoadStarted({
    required String super.paywallId,
    super.firedAt,
  });

  @override
  String get name => 'paywall_load_started';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
      };
}

/// Fired when a paywall finishes loading and is ready to render.
final class PaywallLoadCompleted extends RestageEvent {
  /// Const constructor.
  const PaywallLoadCompleted({
    required String super.paywallId,
    required this.loadDuration,
    required this.cacheHit,
    super.firedAt,
  });

  /// How long the load took (network + decode).
  final Duration loadDuration;

  /// Whether the blob was served from cache.
  final bool cacheHit;

  @override
  String get name => 'paywall_load_completed';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'loadDurationMs': loadDuration.inMilliseconds,
        'cacheHit': cacheHit,
      };
}

/// Fired when a paywall fails to load (network, decode, asset missing).
final class PaywallLoadFailed extends RestageEvent {
  /// Const constructor.
  const PaywallLoadFailed({
    required String super.paywallId,
    required this.errorCode,
    required this.message,
    required this.retryable,
    super.firedAt,
  });

  /// Stable machine-readable error code.
  final String errorCode;

  /// Human-readable message (logged but not user-visible).
  final String message;

  /// Whether the host should retry (transient network) or surface a fallback.
  final bool retryable;

  @override
  String get name => 'paywall_load_failed';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'errorCode': errorCode,
        'message': message,
        'retryable': retryable,
      };
}

/// Fired when a paywall first becomes visible to the user.
final class PaywallViewed extends RestageEvent {
  /// Const constructor.
  const PaywallViewed({
    required String super.paywallId,
    required this.productIds,
    this.variantId,
    this.experimentId,
    super.firedAt,
  });

  /// Product IDs configured on the paywall (snapshot at view time).
  final List<String> productIds;

  /// A/B variant identifier; null if not part of an experiment.
  final String? variantId;

  /// Experiment identifier; null if not part of an experiment.
  final String? experimentId;

  @override
  String get name => 'paywall_viewed';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'productIds': productIds,
        if (variantId != null) 'variantId': variantId,
        if (experimentId != null) 'experimentId': experimentId,
      };
}

/// Fired when a paywall is dismissed.
final class PaywallDismissed extends RestageEvent {
  /// Const constructor.
  const PaywallDismissed({
    required String super.paywallId,
    required this.reason,
    required this.timeOnPaywall,
    super.firedAt,
  });

  /// Why the paywall was dismissed.
  final DismissReason reason;

  /// How long the user spent on the paywall before dismissal.
  final Duration timeOnPaywall;

  @override
  String get name => 'paywall_dismissed';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'reason': reason.wireName,
        'timeOnPaywallMs': timeOnPaywall.inMilliseconds,
      };
}
