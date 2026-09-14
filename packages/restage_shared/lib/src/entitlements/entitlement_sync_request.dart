import 'package:meta/meta.dart';
import 'package:restage_shared/src/entitlements/commerce_wire.dart';

const _purchaserStateRequestFields = {
  'appAnonymousToken',
  'knownStoreTransactionIds',
};

/// A request for the authoritative purchaser state.
@immutable
final class CommercePurchaserStateRequest {
  /// Creates a purchaser-state request.
  factory CommercePurchaserStateRequest({
    required String appAnonymousToken,
    List<String> knownStoreTransactionIds = const [],
  }) {
    requireCommerceUuidV4(
      appAnonymousToken,
      'appAnonymousToken',
      lowercase: false,
    );
    for (final id in knownStoreTransactionIds) {
      if (id.isEmpty) {
        throw ArgumentError.value(
          knownStoreTransactionIds,
          'knownStoreTransactionIds',
          'Expected non-empty transaction identifiers',
        );
      }
    }
    return CommercePurchaserStateRequest._(
      appAnonymousToken: appAnonymousToken,
      knownStoreTransactionIds: List.unmodifiable(knownStoreTransactionIds),
    );
  }

  const CommercePurchaserStateRequest._({
    required this.appAnonymousToken,
    required this.knownStoreTransactionIds,
  });

  /// Parses a purchaser-state request sent by an application.
  factory CommercePurchaserStateRequest.fromJson(Map<String, dynamic> json) {
    rejectUnknownCommerceFields(json, _purchaserStateRequestFields);
    return CommercePurchaserStateRequest(
      appAnonymousToken: requiredCommerceUuidV4(
        json,
        'appAnonymousToken',
        lowercase: false,
      ),
      knownStoreTransactionIds: json.containsKey('knownStoreTransactionIds')
          ? requiredCommerceStringList(json, 'knownStoreTransactionIds')
          : const [],
    );
  }

  /// Anonymous application identity used for purchaser state.
  final String appAnonymousToken;

  /// Store transaction identifiers already known by the application.
  final List<String> knownStoreTransactionIds;

  /// Converts this request to its wire representation.
  Map<String, dynamic> toJson() => {
        'appAnonymousToken': appAnonymousToken,
        'knownStoreTransactionIds': knownStoreTransactionIds,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CommercePurchaserStateRequest ||
        other.appAnonymousToken != appAnonymousToken ||
        other.knownStoreTransactionIds.length !=
            knownStoreTransactionIds.length) {
      return false;
    }
    for (var index = 0; index < knownStoreTransactionIds.length; index += 1) {
      if (other.knownStoreTransactionIds[index] !=
          knownStoreTransactionIds[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        appAnonymousToken,
        Object.hashAll(knownStoreTransactionIds),
      );
}
