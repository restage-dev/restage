import 'package:meta/meta.dart';

/// Authoritative entitlement state returned by the server.
///
/// Unknown values from a server newer than this SDK parse to `'unknown'` and
/// are treated as not entitled; the contract grows additively.
@immutable
final class EntitlementSummary {
  /// Creates an entitlement summary.
  ///
  /// [status] and [source] are validated against their known sets with an
  /// unconditional throw (not an `assert`), so direct construction with an
  /// out-of-set value fails in release builds too. The wire path
  /// ([EntitlementSummary.fromJson]) instead degrades an unknown value to
  /// `'unknown'`, so a server newer than this SDK stays forward-compatible.
  EntitlementSummary({
    required this.entitlementId,
    required this.status,
    required this.productId,
    required this.source,
    this.expiresAtMs,
  }) {
    if (!_statuses.contains(status)) {
      throw ArgumentError.value(status, 'status', 'must be one of $_statuses');
    }
    if (!_sources.contains(source)) {
      throw ArgumentError.value(source, 'source', 'must be one of $_sources');
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
            other.source == source;
  }

  @override
  int get hashCode {
    return Object.hash(
      entitlementId,
      status,
      expiresAtMs,
      productId,
      source,
    );
  }
}

const _unknown = 'unknown';
const Set<String> _statuses = {'active', 'expired', 'refunded', _unknown};
const Set<String> _sources = {'clientReport', 'storeNotification', _unknown};

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
