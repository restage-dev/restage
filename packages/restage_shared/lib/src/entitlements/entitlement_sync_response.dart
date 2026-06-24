import 'package:restage_shared/src/entitlements/entitlement_summary.dart';
import 'package:meta/meta.dart';

/// Authoritative entitlement set returned by the server.
///
/// Unknown enum values in individual entitlements degrade gracefully via
/// [EntitlementSummary.fromJson]; the SDK treats `'unknown'` status as
/// not-entitled.
@immutable
final class EntitlementSyncResponse {
  /// Creates a sync response.
  ///
  /// [entitlements] is wrapped unmodifiable so the stored list cannot be
  /// mutated after construction — the same guarantee
  /// [EntitlementSyncResponse.fromJson] provides.
  EntitlementSyncResponse({List<EntitlementSummary> entitlements = const []})
      : entitlements = List.unmodifiable(entitlements);

  /// Parses a sync response from JSON.
  factory EntitlementSyncResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['entitlements'];
    final List<EntitlementSummary> entitlements;
    if (raw == null) {
      entitlements = const [];
    } else if (raw is List) {
      entitlements = <EntitlementSummary>[];
      for (final entry in raw) {
        if (entry is! Map) {
          throw ArgumentError.value(
            raw,
            'entitlements',
            'Expected each entry to be an object',
          );
        }
        entitlements.add(
          EntitlementSummary.fromJson(entry.cast<String, dynamic>()),
        );
      }
    } else {
      throw ArgumentError.value(
        raw,
        'entitlements',
        'Expected a list of entitlement objects',
      );
    }
    return EntitlementSyncResponse(entitlements: entitlements);
  }

  /// Authoritative entitlement summaries from the server.
  final List<EntitlementSummary> entitlements;

  /// Converts this response to JSON.
  Map<String, dynamic> toJson() {
    return {
      'entitlements': [for (final e in entitlements) e.toJson()],
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EntitlementSyncResponse) return false;
    final a = other.entitlements;
    final b = entitlements;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(entitlements);
}
