import 'package:meta/meta.dart';
import 'package:restage_shared/src/entitlements/commerce_wire.dart';
import 'package:restage_shared/src/entitlements/entitlement_summary.dart';

const _purchaserStateStatuses = {'current', 'stale', 'unknown'};

/// Authoritative purchaser state returned by the server.
@immutable
final class CommercePurchaserStateResponse {
  /// Creates a purchaser-state response.
  factory CommercePurchaserStateResponse({
    required String status,
    required List<EntitlementSummary> entitlements,
    required DateTime retrievedAt,
  }) {
    if (!_purchaserStateStatuses.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Unsupported status');
    }
    return CommercePurchaserStateResponse._(
      status: status,
      entitlements: List.unmodifiable(entitlements),
      retrievedAt: retrievedAt.toUtc(),
    );
  }

  const CommercePurchaserStateResponse._({
    required this.status,
    required this.entitlements,
    required this.retrievedAt,
  });

  /// Parses a response while allowing future additive fields.
  factory CommercePurchaserStateResponse.fromJson(Map<String, dynamic> json) {
    final rawEntitlements = json['entitlements'];
    if (rawEntitlements is! List) {
      throw ArgumentError.value(
        rawEntitlements,
        'entitlements',
        'Expected a list of entitlement objects',
      );
    }
    final entitlements = <EntitlementSummary>[];
    for (final entry in rawEntitlements) {
      if (entry is! Map) {
        throw ArgumentError.value(
          entry,
          'entitlements',
          'Expected each entry to be an object',
        );
      }
      entitlements
          .add(EntitlementSummary.fromJson(entry.cast<String, dynamic>()));
    }
    return CommercePurchaserStateResponse._(
      status: normalizeCommerceResponseCode(
        requiredCommerceString(json, 'status'),
        _purchaserStateStatuses,
      ),
      entitlements: List.unmodifiable(entitlements),
      retrievedAt: requiredCommerceDateTime(json, 'retrievedAt'),
    );
  }

  /// Freshness of the returned entitlement state.
  final String status;

  /// Entitlements derived by the server.
  final List<EntitlementSummary> entitlements;

  /// Time at which the server read the purchaser state.
  final DateTime retrievedAt;

  /// Converts this response to its wire representation.
  Map<String, dynamic> toJson() => {
        'status': status,
        'entitlements': [
          for (final entitlement in entitlements) entitlement.toJson(),
        ],
        'retrievedAt': retrievedAt.toIso8601String(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CommercePurchaserStateResponse ||
        other.status != status ||
        other.retrievedAt != retrievedAt ||
        other.entitlements.length != entitlements.length) {
      return false;
    }
    for (var index = 0; index < entitlements.length; index += 1) {
      if (other.entitlements[index] != entitlements[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        status,
        Object.hashAll(entitlements),
        retrievedAt,
      );
}
