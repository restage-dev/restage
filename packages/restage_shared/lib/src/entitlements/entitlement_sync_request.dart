import 'package:meta/meta.dart';

/// Client-known transaction state sent to the server for reconciliation.
///
/// The server uses [knownStoreTransactionIds] to detect transactions the
/// client has not yet reported, and returns the authoritative entitlement
/// set so the client can converge on the server's view.
@immutable
final class EntitlementSyncRequest {
  /// Creates a sync request.
  ///
  /// [knownStoreTransactionIds] is wrapped unmodifiable so the stored list
  /// cannot be mutated after construction — the same guarantee
  /// [EntitlementSyncRequest.fromJson] provides.
  EntitlementSyncRequest({
    this.appAnonymousToken,
    List<String> knownStoreTransactionIds = const [],
  }) : knownStoreTransactionIds = List.unmodifiable(knownStoreTransactionIds);

  /// Parses a sync request from JSON.
  factory EntitlementSyncRequest.fromJson(Map<String, dynamic> json) {
    final raw = json['knownStoreTransactionIds'];
    final List<String> ids;
    if (raw == null) {
      ids = const [];
    } else if (raw is List) {
      ids = <String>[];
      for (final entry in raw) {
        if (entry is! String || entry.isEmpty) {
          throw ArgumentError.value(
            raw,
            'knownStoreTransactionIds',
            'Expected a list of non-empty strings',
          );
        }
        ids.add(entry);
      }
    } else {
      throw ArgumentError.value(
        raw,
        'knownStoreTransactionIds',
        'Expected a list of strings',
      );
    }
    return EntitlementSyncRequest(
      appAnonymousToken: _optionalString(json, 'appAnonymousToken'),
      knownStoreTransactionIds: ids,
    );
  }

  /// Stable anonymous app-user token, when available.
  final String? appAnonymousToken;

  /// Store transaction identifiers the client already knows about.
  final List<String> knownStoreTransactionIds;

  /// Converts this request to JSON.
  Map<String, dynamic> toJson() {
    return {
      if (appAnonymousToken != null) 'appAnonymousToken': appAnonymousToken,
      'knownStoreTransactionIds': knownStoreTransactionIds,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EntitlementSyncRequest) return false;
    if (other.appAnonymousToken != appAnonymousToken) return false;
    final a = other.knownStoreTransactionIds;
    final b = knownStoreTransactionIds;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    return Object.hash(
      appAnonymousToken,
      Object.hashAll(knownStoreTransactionIds),
    );
  }
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw ArgumentError.value(value, key, 'Expected a non-empty string or null');
}
