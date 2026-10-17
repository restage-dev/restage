import 'package:meta/meta.dart';

/// Authoritative entitlement state returned by the server.
///
/// Unknown status and source values parse to `'unknown'`; unknown statuses
/// grant no access. Store environments must be production or sandbox.
@immutable
final class EntitlementSummary {
  /// Creates an entitlement summary.
  ///
  /// [status] and [source] validate known values and decode future values as
  /// `'unknown'`. [providerEnvironment] requires production or sandbox for
  /// construction and decoding.
  EntitlementSummary({
    required this.entitlementId,
    required this.status,
    required this.productId,
    required this.source,
    required this.providerEnvironment,
    this.expiresAtMs,
  }) {
    if (!_statuses.contains(status)) {
      throw ArgumentError.value(status, 'status', 'must be one of $_statuses');
    }
    if (!_sources.contains(source)) {
      throw ArgumentError.value(source, 'source', 'must be one of $_sources');
    }
    if (!_providerEnvironments.contains(providerEnvironment)) {
      throw ArgumentError.value(providerEnvironment, 'providerEnvironment');
    }
  }

  /// Parses a summary from JSON.
  factory EntitlementSummary.fromJson(Map<String, dynamic> json) {
    final status = _normalizeKnown(_requiredString(json, 'status'), _statuses);
    final source = _normalizeKnown(_requiredString(json, 'source'), _sources);
    return EntitlementSummary(
      entitlementId: _requiredString(json, 'entitlementId'),
      status: status,
      productId: _requiredString(json, 'productId'),
      source: source,
      expiresAtMs: _optionalInt(json, 'expiresAtMs'),
      providerEnvironment: _requiredString(json, 'providerEnvironment'),
    );
  }

  /// Entitlement identifier granted by this purchase.
  final String entitlementId;

  /// Entitlement status.
  final String status;

  /// Expiry timestamp in milliseconds since epoch, when expiring.
  final int? expiresAtMs;

  /// Product identifier backing this entitlement.
  final String productId;

  /// Signal source that produced this state.
  final String source;

  /// Verified store environment: production or sandbox.
  final String providerEnvironment;

  /// Whether this summary grants access.
  bool get isEntitled => status == 'active';

  /// Converts this summary to JSON.
  Map<String, dynamic> toJson() {
    return {
      'entitlementId': entitlementId,
      'status': status,
      if (expiresAtMs != null) 'expiresAtMs': expiresAtMs,
      'productId': productId,
      'source': source,
      'providerEnvironment': providerEnvironment,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is EntitlementSummary &&
            other.entitlementId == entitlementId &&
            other.status == status &&
            other.expiresAtMs == expiresAtMs &&
            other.productId == productId &&
            other.source == source &&
            other.providerEnvironment == providerEnvironment;
  }

  @override
  int get hashCode {
    return Object.hash(
      entitlementId,
      status,
      expiresAtMs,
      productId,
      source,
      providerEnvironment,
    );
  }
}

const _unknown = 'unknown';
const Set<String> _statuses = {'active', 'expired', 'refunded', _unknown};
const Set<String> _sources = {'clientReport', 'storeNotification', _unknown};
const Set<String> _providerEnvironments = {'production', 'sandbox'};

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw ArgumentError.value(value, key, 'Expected a non-empty string');
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || value is int) {
    return value as int?;
  }
  throw ArgumentError.value(value, key, 'Expected an int or null');
}

String _normalizeKnown(String value, Set<String> allowed) =>
    allowed.contains(value) ? value : _unknown;
