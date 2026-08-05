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
    this.reportId,
    this.purchaseIntentId,
    this.appAnonymousToken,
    this.paywallId,
    this.paywallVariantSlug,
    this.paywallPublishedVersion,
  })  : assert(
          store == 'appStore' || store == 'playStore',
          'store must be appStore or playStore',
        ),
        // `!= ''` rather than `.isNotEmpty`: a property access is not
        // const-evaluable, and this constructor is invoked as `const`.
        assert(
          storeVerificationData != '',
          'storeVerificationData must be non-empty',
        ),
        assert(
          storeTransactionId == null || storeTransactionId != '',
          'storeTransactionId must be non-empty when present',
        ),
        assert(
          store != 'appStore' || storeTransactionId != null,
          'appStore requires storeTransactionId',
        );

  /// Parses a request from JSON.
  factory ReportTransactionRequest.fromJson(Map<String, dynamic> json) {
    final store = _requiredString(json, 'store');
    _checkAllowed(store, _stores, 'store');
    final reportId = _optionalString(json, 'reportId');
    if (reportId != null && !_isUuidV4(reportId)) {
      throw ArgumentError.value(
        reportId,
        'reportId',
        'Expected a canonical UUID v4',
      );
    }
    final purchaseIntentId = _optionalString(json, 'purchaseIntentId');
    if (purchaseIntentId != null &&
        (!_isUuidV4(purchaseIntentId) ||
            purchaseIntentId != purchaseIntentId.toLowerCase())) {
      throw ArgumentError.value(
        purchaseIntentId,
        'purchaseIntentId',
        'Expected a canonical lowercase UUID v4',
      );
    }
    final storeTransactionId = _optionalString(json, 'storeTransactionId');
    if (store == 'appStore' && storeTransactionId == null) {
      throw ArgumentError.value(
        storeTransactionId,
        'storeTransactionId',
        'appStore requires a non-empty transaction identifier',
      );
    }
    return ReportTransactionRequest(
      reportId: reportId,
      purchaseIntentId: purchaseIntentId,
      store: store,
      storeVerificationData: _requiredString(json, 'storeVerificationData'),
      storeProductId: _requiredString(json, 'storeProductId'),
      storeTransactionId: storeTransactionId,
      appAnonymousToken: _optionalString(json, 'appAnonymousToken'),
      paywallId: _optionalString(json, 'paywallId'),
      paywallVariantSlug: _optionalString(json, 'paywallVariantSlug'),
      paywallPublishedVersion: _optionalInt(json, 'paywallPublishedVersion'),
    );
  }

  /// Client-generated report correlation UUID.
  ///
  /// This is correlation-only. Store identity remains the authoritative
  /// idempotency boundary. It is nullable so servers remain compatible with
  /// requests from SDK versions published before report correlation existed.
  final String? reportId;

  /// Client-observed purchase-intent UUID, when present in store evidence.
  ///
  /// This is a routing and consistency hint only. The server associates an
  /// intent only from provider-verified store evidence. It remains nullable so
  /// request shapes from earlier SDK versions remain valid.
  final String? purchaseIntentId;

  /// Store that produced the transaction.
  final String store;

  /// Store-specific verification payload for this transport.
  final String storeVerificationData;

  /// Store product identifier.
  final String storeProductId;

  /// Store transaction identifier.
  final String? storeTransactionId;

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
      if (reportId != null) 'reportId': reportId,
      if (purchaseIntentId != null) 'purchaseIntentId': purchaseIntentId,
      'store': store,
      'storeVerificationData': storeVerificationData,
      'storeProductId': storeProductId,
      if (storeTransactionId != null) 'storeTransactionId': storeTransactionId,
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
            other.reportId == reportId &&
            other.purchaseIntentId == purchaseIntentId &&
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
      reportId,
      purchaseIntentId,
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

bool _isUuidV4(String value) {
  if (value.length != 36) return false;
  for (var i = 0; i < value.length; i += 1) {
    final codeUnit = value.codeUnitAt(i);
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (codeUnit != 0x2d) return false;
      continue;
    }
    final isHex = (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x46) ||
        (codeUnit >= 0x61 && codeUnit <= 0x66);
    if (!isHex) return false;
  }
  if (value.codeUnitAt(14) != 0x34) return false;
  final variant = value.codeUnitAt(19);
  return variant == 0x38 ||
      variant == 0x39 ||
      variant == 0x41 ||
      variant == 0x42 ||
      variant == 0x61 ||
      variant == 0x62;
}
