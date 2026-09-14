import 'package:meta/meta.dart';
import 'package:restage_shared/src/entitlements/commerce_wire.dart';

const _reportRequestFields = {
  'reportId',
  'intentId',
  'store',
  'storeVerificationData',
  'storeProductId',
  'storeTransactionId',
  'appAnonymousToken',
  'paywallId',
  'paywallVariantSlug',
  'paywallPublishedVersion',
};

/// Store evidence submitted for verification.
@immutable
final class CommerceReportRequest {
  /// Creates a report request.
  factory CommerceReportRequest({
    required String reportId,
    required String store,
    required String storeVerificationData,
    required String storeProductId,
    required String appAnonymousToken,
    String? intentId,
    String? storeTransactionId,
    String? paywallId,
    String? paywallVariantSlug,
    int? paywallPublishedVersion,
  }) {
    requireCommerceUuidV4(reportId, 'reportId', lowercase: false);
    if (!commerceStoreValues.contains(store)) {
      throw ArgumentError.value(store, 'store', 'Unsupported store');
    }
    _requireString(storeVerificationData, 'storeVerificationData');
    _requireString(storeProductId, 'storeProductId');
    requireCommerceUuidV4(
      appAnonymousToken,
      'appAnonymousToken',
      lowercase: false,
    );
    if (intentId != null) requireCommerceUuidV4(intentId, 'intentId');
    _requireOptionalString(storeTransactionId, 'storeTransactionId');
    if (store == commerceAppStoreValue && storeTransactionId == null) {
      throw ArgumentError.value(
        storeTransactionId,
        'storeTransactionId',
        'app_store requires a non-empty transaction identifier',
      );
    }
    _requireOptionalString(paywallId, 'paywallId');
    _requireOptionalString(paywallVariantSlug, 'paywallVariantSlug');
    return CommerceReportRequest._(
      reportId: reportId,
      intentId: intentId,
      store: store,
      storeVerificationData: storeVerificationData,
      storeProductId: storeProductId,
      storeTransactionId: storeTransactionId,
      appAnonymousToken: appAnonymousToken,
      paywallId: paywallId,
      paywallVariantSlug: paywallVariantSlug,
      paywallPublishedVersion: paywallPublishedVersion,
    );
  }

  const CommerceReportRequest._({
    required this.reportId,
    required this.intentId,
    required this.store,
    required this.storeVerificationData,
    required this.storeProductId,
    required this.storeTransactionId,
    required this.appAnonymousToken,
    required this.paywallId,
    required this.paywallVariantSlug,
    required this.paywallPublishedVersion,
  });

  /// Parses the report sent by an application.
  factory CommerceReportRequest.fromJson(Map<String, dynamic> json) {
    rejectUnknownCommerceFields(json, _reportRequestFields);
    final intentId = optionalCommerceString(json, 'intentId');
    if (intentId != null) requireCommerceUuidV4(intentId, 'intentId');
    return CommerceReportRequest(
      reportId: requiredCommerceUuidV4(
        json,
        'reportId',
        lowercase: false,
      ),
      intentId: intentId,
      store: requiredCommerceString(json, 'store'),
      storeVerificationData: requiredCommerceString(
        json,
        'storeVerificationData',
      ),
      storeProductId: requiredCommerceString(json, 'storeProductId'),
      storeTransactionId: optionalCommerceString(json, 'storeTransactionId'),
      appAnonymousToken: requiredCommerceUuidV4(
        json,
        'appAnonymousToken',
        lowercase: false,
      ),
      paywallId: optionalCommerceString(json, 'paywallId'),
      paywallVariantSlug: optionalCommerceString(json, 'paywallVariantSlug'),
      paywallPublishedVersion: optionalCommerceInt(
        json,
        'paywallPublishedVersion',
      ),
    );
  }

  /// Client-generated correlation identity.
  final String reportId;

  /// Intent identity, when the report follows a resolved intent.
  final String? intentId;

  /// Store that produced the evidence.
  final String store;

  /// Store-specific verification payload.
  final String storeVerificationData;

  /// Provider product identifier included with the report.
  final String storeProductId;

  /// Provider transaction identifier, when available.
  final String? storeTransactionId;

  /// Anonymous application identity used for purchaser state.
  final String appAnonymousToken;

  /// Legacy paywall identifier associated with the purchase, when available.
  final String? paywallId;

  /// Legacy paywall variant associated with the purchase, when available.
  final String? paywallVariantSlug;

  /// Published legacy paywall version associated with the purchase.
  final int? paywallPublishedVersion;

  /// Converts this request to its wire representation.
  Map<String, dynamic> toJson() => {
        'reportId': reportId,
        if (intentId != null) 'intentId': intentId,
        'store': store,
        'storeVerificationData': storeVerificationData,
        'storeProductId': storeProductId,
        if (storeTransactionId != null)
          'storeTransactionId': storeTransactionId,
        'appAnonymousToken': appAnonymousToken,
        if (paywallId != null) 'paywallId': paywallId,
        if (paywallVariantSlug != null)
          'paywallVariantSlug': paywallVariantSlug,
        if (paywallPublishedVersion != null)
          'paywallPublishedVersion': paywallPublishedVersion,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommerceReportRequest &&
          other.reportId == reportId &&
          other.intentId == intentId &&
          other.store == store &&
          other.storeVerificationData == storeVerificationData &&
          other.storeProductId == storeProductId &&
          other.storeTransactionId == storeTransactionId &&
          other.appAnonymousToken == appAnonymousToken &&
          other.paywallId == paywallId &&
          other.paywallVariantSlug == paywallVariantSlug &&
          other.paywallPublishedVersion == paywallPublishedVersion;

  @override
  int get hashCode => Object.hash(
        reportId,
        intentId,
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

void _requireString(String value, String key) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, key, 'Expected a non-empty string');
  }
}

void _requireOptionalString(String? value, String key) {
  if (value != null) _requireString(value, key);
}
