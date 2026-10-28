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
    List<CommerceFulfillmentSummary> fulfillments = const [],
    bool? hasProductionPurchaseHistory,
  }) {
    if (!_purchaserStateStatuses.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Unsupported status');
    }
    return CommercePurchaserStateResponse._(
      status: status,
      entitlements: List.unmodifiable(entitlements),
      fulfillments: List.unmodifiable(fulfillments),
      retrievedAt: retrievedAt.toUtc(),
      hasProductionPurchaseHistory: hasProductionPurchaseHistory,
    );
  }

  const CommercePurchaserStateResponse._({
    required this.status,
    required this.entitlements,
    required this.fulfillments,
    required this.retrievedAt,
    required this.hasProductionPurchaseHistory,
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
      fulfillments: _fulfillmentsFromJson(json),
      retrievedAt: requiredCommerceDateTime(json, 'retrievedAt'),
      hasProductionPurchaseHistory: _optionalHistory(json),
    );
  }

  /// Freshness of the returned entitlement state.
  final String status;

  /// Entitlements derived by the server.
  final List<EntitlementSummary> entitlements;

  /// Active fulfillment lines derived by the server.
  final List<CommerceFulfillmentSummary> fulfillments;

  /// Time at which the server read the purchaser state.
  final DateTime retrievedAt;

  /// Production purchase history for this app configuration and purchaser.
  /// Includes inactive purchases and purchases without a current entitlement.
  /// Null is unproven; false means the server checked and found none.
  final bool? hasProductionPurchaseHistory;

  /// Converts this response to its wire representation.
  Map<String, dynamic> toJson() => {
        'status': status,
        'entitlements': [
          for (final entitlement in entitlements) entitlement.toJson(),
        ],
        'fulfillments': [
          for (final fulfillment in fulfillments) fulfillment.toJson(),
        ],
        'retrievedAt': retrievedAt.toIso8601String(),
        if (hasProductionPurchaseHistory != null)
          'hasProductionPurchaseHistory': hasProductionPurchaseHistory,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CommercePurchaserStateResponse ||
        other.status != status ||
        other.retrievedAt != retrievedAt ||
        other.hasProductionPurchaseHistory != hasProductionPurchaseHistory ||
        other.entitlements.length != entitlements.length ||
        other.fulfillments.length != fulfillments.length) {
      return false;
    }
    for (var index = 0; index < entitlements.length; index += 1) {
      if (other.entitlements[index] != entitlements[index]) return false;
    }
    for (var index = 0; index < fulfillments.length; index += 1) {
      if (other.fulfillments[index] != fulfillments[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        status,
        Object.hashAll(entitlements),
        Object.hashAll(fulfillments),
        retrievedAt,
        hasProductionPurchaseHistory,
      );
}

bool? _optionalHistory(Map<String, dynamic> json) {
  final value = json['hasProductionPurchaseHistory'];
  if (value == null || value is bool) return value as bool?;
  throw ArgumentError.value(value, 'hasProductionPurchaseHistory');
}

/// An active, server-verified fulfillment line.
@immutable
final class CommerceFulfillmentSummary {
  /// Creates a fulfillment summary.
  CommerceFulfillmentSummary({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.providerEnvironment,
  }) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    if (productId.isEmpty) throw ArgumentError.value(productId, 'productId');
    if (quantity < 1) throw ArgumentError.value(quantity, 'quantity');
    if (providerEnvironment != 'production' &&
        providerEnvironment != 'sandbox') {
      throw ArgumentError.value(providerEnvironment, 'providerEnvironment');
    }
  }

  /// Parses a summary while allowing future additive fields.
  factory CommerceFulfillmentSummary.fromJson(Map<String, dynamic> json) {
    final quantity = json['quantity'];
    if (quantity is! int) throw ArgumentError.value(quantity, 'quantity');
    return CommerceFulfillmentSummary(
      id: requiredCommerceString(json, 'id'),
      productId: requiredCommerceString(json, 'productId'),
      quantity: quantity,
      providerEnvironment: requiredCommerceString(json, 'providerEnvironment'),
    );
  }

  /// Stable identity of the accepted fulfillment line.
  final String id;

  /// Store product identifier captured when the purchase was accepted.
  final String productId;

  /// Purchased quantity; partial refunds preserve the whole line's access.
  final int quantity;

  /// Verified store environment: production or sandbox.
  final String providerEnvironment;

  /// Converts this summary to its wire representation.
  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'quantity': quantity,
        'providerEnvironment': providerEnvironment,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommerceFulfillmentSummary &&
          other.id == id &&
          other.productId == productId &&
          other.quantity == quantity &&
          other.providerEnvironment == providerEnvironment;

  @override
  int get hashCode => Object.hash(id, productId, quantity, providerEnvironment);
}

List<CommerceFulfillmentSummary> _fulfillmentsFromJson(
    Map<String, dynamic> json) {
  if (!json.containsKey('fulfillments')) return const [];
  final raw = json['fulfillments'];
  if (raw is! List) throw ArgumentError.value(raw, 'fulfillments');
  return List.unmodifiable(raw.map((entry) {
    if (entry is! Map) throw ArgumentError.value(entry, 'fulfillments');
    return CommerceFulfillmentSummary.fromJson(entry.cast<String, dynamic>());
  }));
}
