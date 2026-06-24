import 'package:meta/meta.dart';

/// Purchase transaction reported by the SDK to the server.
///
/// Note: server-bound fields are strict-validated (an unknown `store` value is
/// a client bug), while server-to-client fields like
/// `EntitlementSummary.status` are graceful-unknown so the server can add new
/// values without breaking older SDKs.
@immutable
final class ReportTransactionRequest {
  /// Creates a report-transaction request.
  const ReportTransactionRequest({
    required this.store,
    required this.storeVerificationData,
    required this.storeProductId,
    required this.storeTransactionId,
    this.appAnonymousToken,
    this.paywallId,
    this.paywallVariantSlug,
    this.paywallPublishedVersion,
  }) : assert(
          store == 'appStore' || store == 'playStore',
          'store must be appStore or playStore',
        );

  /// Parses a request from JSON.
  factory ReportTransactionRequest.fromJson(Map<String, dynamic> json) {
    final store = _requiredString(json, 'store');
    _checkAllowed(store, _stores, 'store');
    return ReportTransactionRequest(
      store: store,
      storeVerificationData: _requiredString(json, 'storeVerificationData'),
      storeProductId: _requiredString(json, 'storeProductId'),
      storeTransactionId: _requiredString(json, 'storeTransactionId'),
      appAnonymousToken: _optionalString(json, 'appAnonymousToken'),
      paywallId: _optionalString(json, 'paywallId'),
      paywallVariantSlug: _optionalString(json, 'paywallVariantSlug'),
      paywallPublishedVersion: _optionalInt(json, 'paywallPublishedVersion'),
    );
  }

  /// Store that produced the transaction.
  final String store;

  /// Store-specific verification payload for this transport.
  final String storeVerificationData;

  /// Store product identifier.
  final String storeProductId;

  /// Store transaction identifier.
  final String storeTransactionId;

  /// Stable anonymous app-user token, when available.
  final String? appAnonymousToken;

  /// Paywall identifier associated with the purchase, when available.
  final String? paywallId;

  /// Paywall variant slug associated with the purchase, when available.
  final String? paywallVariantSlug;

  /// Published paywall version associated with the purchase, when available.
  final int? paywallPublishedVersion;

  /// Converts this request to JSON.
  Map<String, dynamic> toJson() {
    return {
      'store': store,
      'storeVerificationData': storeVerificationData,
      'storeProductId': storeProductId,
      'storeTransactionId': storeTransactionId,
      if (appAnonymousToken != null) 'appAnonymousToken': appAnonymousToken,
      if (paywallId != null) 'paywallId': paywallId,
      if (paywallVariantSlug != null) 'paywallVariantSlug': paywallVariantSlug,
      if (paywallPublishedVersion != null)
        'paywallPublishedVersion': paywallPublishedVersion,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ReportTransactionRequest &&
            other.store == store &&
            other.storeVerificationData == storeVerificationData &&
            other.storeProductId == storeProductId &&
            other.storeTransactionId == storeTransactionId &&
            other.appAnonymousToken == appAnonymousToken &&
            other.paywallId == paywallId &&
            other.paywallVariantSlug == paywallVariantSlug &&
            other.paywallPublishedVersion == paywallPublishedVersion;
  }

  @override
  int get hashCode {
    return Object.hash(
      store,
      storeVerificationData,
      storeProductId,
      storeTransactionId,
      appAnonymousToken,
      paywallId,
      paywallVariantSlug,
      paywallPublishedVersion,
    );
  }
}

const _stores = {'appStore', 'playStore'};

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw ArgumentError.value(value, key, 'Expected a non-empty string');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw ArgumentError.value(value, key, 'Expected a non-empty string or null');
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || value is int) {
    return value as int?;
  }
  throw ArgumentError.value(value, key, 'Expected an int or null');
}

void _checkAllowed(String value, Set<String> allowed, String key) {
  if (!allowed.contains(value)) {
    throw ArgumentError.value(value, key, 'Unsupported value');
  }
}
