import 'package:meta/meta.dart';
import 'package:restage_shared/src/entitlements/commerce_wire.dart';
import 'package:restage_shared/src/offers/offer_signature_response.dart';

const _intentRequestFields = {
  'intentId',
  'offerId',
  'store',
  'appAnonymousToken',
  'surfaceId',
  'surfaceKind',
  'variantSlug',
  'publishedVersion',
};

/// A request to resolve one logical offer for a store purchase.
@immutable
final class CommerceIntentRequest {
  /// Creates an intent request.
  factory CommerceIntentRequest({
    required String intentId,
    required String offerId,
    required String store,
    required String appAnonymousToken,
    String? surfaceId,
    String? surfaceKind,
    String? variantSlug,
    int? publishedVersion,
  }) {
    requireCommerceUuidV4(intentId, 'intentId');
    requireCommerceOfferId(offerId, 'offerId');
    if (!commerceStoreValues.contains(store)) {
      throw ArgumentError.value(store, 'store', 'Unsupported store');
    }
    requireCommerceUuidV4(
      appAnonymousToken,
      'appAnonymousToken',
      lowercase: false,
    );
    _requireOptionalString(surfaceId, 'surfaceId');
    _requireOptionalString(surfaceKind, 'surfaceKind');
    _requireOptionalString(variantSlug, 'variantSlug');
    if (variantSlug != null && surfaceId == null) {
      throw ArgumentError.value(
        variantSlug,
        'variantSlug',
        'surfaceId is required when variantSlug is provided',
      );
    }
    if (publishedVersion != null && publishedVersion < 1) {
      throw ArgumentError.value(
        publishedVersion,
        'publishedVersion',
        'Expected a positive int',
      );
    }
    if (publishedVersion != null && surfaceId == null) {
      throw ArgumentError.value(
        publishedVersion,
        'publishedVersion',
        'surfaceId is required when publishedVersion is provided',
      );
    }
    return CommerceIntentRequest._(
      intentId: intentId,
      offerId: offerId,
      store: store,
      appAnonymousToken: appAnonymousToken,
      surfaceId: surfaceId,
      surfaceKind: surfaceKind,
      variantSlug: variantSlug,
      publishedVersion: publishedVersion,
    );
  }

  const CommerceIntentRequest._({
    required this.intentId,
    required this.offerId,
    required this.store,
    required this.appAnonymousToken,
    required this.surfaceId,
    required this.surfaceKind,
    required this.variantSlug,
    required this.publishedVersion,
  });

  /// Parses the request sent by an application.
  factory CommerceIntentRequest.fromJson(Map<String, dynamic> json) {
    rejectUnknownCommerceFields(json, _intentRequestFields);
    return CommerceIntentRequest(
      intentId: requiredCommerceUuidV4(json, 'intentId'),
      offerId: requiredCommerceString(json, 'offerId'),
      store: requiredCommerceString(json, 'store'),
      appAnonymousToken: requiredCommerceUuidV4(
        json,
        'appAnonymousToken',
        lowercase: false,
      ),
      surfaceId: optionalCommerceString(json, 'surfaceId'),
      surfaceKind: optionalCommerceString(json, 'surfaceKind'),
      variantSlug: optionalCommerceString(json, 'variantSlug'),
      publishedVersion: optionalCommerceInt(json, 'publishedVersion'),
    );
  }

  /// Client-generated idempotency identity.
  final String intentId;

  /// Logical offer selected by the application.
  final String offerId;

  /// Store where the application will present the purchase.
  final String store;

  /// Anonymous application identity used for purchaser state.
  final String appAnonymousToken;

  /// Surface identifier, when the purchase originated from a surface.
  final String? surfaceId;

  /// Surface kind, when the purchase originated from a surface.
  final String? surfaceKind;

  /// Surface variant, when one was selected.
  final String? variantSlug;

  /// Published surface version, when one was presented.
  final int? publishedVersion;

  /// Converts this request to its wire representation.
  Map<String, dynamic> toJson() => {
        'intentId': intentId,
        'offerId': offerId,
        'store': store,
        'appAnonymousToken': appAnonymousToken,
        if (surfaceId != null) 'surfaceId': surfaceId,
        if (surfaceKind != null) 'surfaceKind': surfaceKind,
        if (variantSlug != null) 'variantSlug': variantSlug,
        if (publishedVersion != null) 'publishedVersion': publishedVersion,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommerceIntentRequest &&
          other.intentId == intentId &&
          other.offerId == offerId &&
          other.store == store &&
          other.appAnonymousToken == appAnonymousToken &&
          other.surfaceId == surfaceId &&
          other.surfaceKind == surfaceKind &&
          other.variantSlug == variantSlug &&
          other.publishedVersion == publishedVersion;

  @override
  int get hashCode => Object.hash(
        intentId,
        offerId,
        store,
        appAnonymousToken,
        surfaceId,
        surfaceKind,
        variantSlug,
        publishedVersion,
      );
}

/// A store purchasable resolved from a logical offer.
@immutable
final class CommerceResolvedPurchasable {
  /// Creates a resolved purchasable.
  factory CommerceResolvedPurchasable({
    required String storeProductId,
    required String productKind,
    required String appAccountToken,
    String? basePlanId,
    String? storeOfferIdentifier,
    OfferSignatureResponse? offerSignature,
  }) {
    _requireString(storeProductId, 'storeProductId');
    _requireString(productKind, 'productKind');
    requireCommerceUuidV4(
      appAccountToken,
      'appAccountToken',
      lowercase: false,
    );
    _requireOptionalString(basePlanId, 'basePlanId');
    _requireOptionalString(storeOfferIdentifier, 'storeOfferIdentifier');
    return CommerceResolvedPurchasable._(
      storeProductId: storeProductId,
      productKind: productKind,
      basePlanId: basePlanId,
      storeOfferIdentifier: storeOfferIdentifier,
      offerSignature: offerSignature,
      appAccountToken: appAccountToken,
    );
  }

  const CommerceResolvedPurchasable._({
    required this.storeProductId,
    required this.productKind,
    required this.basePlanId,
    required this.storeOfferIdentifier,
    required this.offerSignature,
    required this.appAccountToken,
  });

  /// Parses a resolved purchasable from a response.
  factory CommerceResolvedPurchasable.fromJson(Map<String, dynamic> json) {
    final rawSignature = json['offerSignature'];
    if (rawSignature != null && rawSignature is! Map<String, dynamic>) {
      throw ArgumentError.value(
        rawSignature,
        'offerSignature',
        'Expected an object or null',
      );
    }
    final signature = rawSignature as Map<String, dynamic>?;
    return CommerceResolvedPurchasable(
      storeProductId: requiredCommerceString(json, 'storeProductId'),
      productKind: requiredCommerceString(json, 'productKind'),
      basePlanId: optionalCommerceString(json, 'basePlanId'),
      storeOfferIdentifier:
          optionalCommerceString(json, 'storeOfferIdentifier'),
      offerSignature:
          signature == null ? null : OfferSignatureResponse.fromJson(signature),
      appAccountToken: requiredCommerceUuidV4(
        json,
        'appAccountToken',
        lowercase: false,
      ),
    );
  }

  /// Provider product identifier selected by the server.
  final String storeProductId;

  /// Product kind selected by the server.
  final String productKind;

  /// Google Play base-plan identifier, when applicable.
  final String? basePlanId;

  /// Store offer identifier, when applicable.
  final String? storeOfferIdentifier;

  /// Signed store offer material, when applicable.
  final OfferSignatureResponse? offerSignature;

  /// Store-account token supplied with the purchase.
  final String appAccountToken;

  /// Converts this purchasable to its wire representation.
  Map<String, dynamic> toJson() => {
        'storeProductId': storeProductId,
        'productKind': productKind,
        if (basePlanId != null) 'basePlanId': basePlanId,
        if (storeOfferIdentifier != null)
          'storeOfferIdentifier': storeOfferIdentifier,
        if (offerSignature != null) 'offerSignature': offerSignature!.toJson(),
        'appAccountToken': appAccountToken,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommerceResolvedPurchasable &&
          other.storeProductId == storeProductId &&
          other.productKind == productKind &&
          other.basePlanId == basePlanId &&
          other.storeOfferIdentifier == storeOfferIdentifier &&
          other.offerSignature == offerSignature &&
          other.appAccountToken == appAccountToken;

  @override
  int get hashCode => Object.hash(
        storeProductId,
        productKind,
        basePlanId,
        storeOfferIdentifier,
        offerSignature,
        appAccountToken,
      );
}

/// The server result of resolving an intent.
@immutable
final class CommerceIntentResponse {
  /// Creates an intent response.
  factory CommerceIntentResponse({
    required String intentId,
    required CommerceResolvedPurchasable resolved,
    required String status,
  }) {
    requireCommerceUuidV4(intentId, 'intentId');
    _requireString(status, 'status');
    return CommerceIntentResponse._(
      intentId: intentId,
      resolved: resolved,
      status: status,
    );
  }

  const CommerceIntentResponse._({
    required this.intentId,
    required this.resolved,
    required this.status,
  });

  /// Parses a response while allowing future additive fields.
  factory CommerceIntentResponse.fromJson(Map<String, dynamic> json) {
    final rawResolved = json['resolved'];
    if (rawResolved is! Map) {
      throw ArgumentError.value(rawResolved, 'resolved', 'Expected an object');
    }
    return CommerceIntentResponse(
      intentId: requiredCommerceUuidV4(json, 'intentId'),
      resolved: CommerceResolvedPurchasable.fromJson(
        rawResolved.cast<String, dynamic>(),
      ),
      status: requiredCommerceString(json, 'status'),
    );
  }

  /// Client-generated idempotency identity.
  final String intentId;

  /// Provider purchasable selected by the server.
  final CommerceResolvedPurchasable resolved;

  /// Resolution status.
  final String status;

  /// Converts this response to its wire representation.
  Map<String, dynamic> toJson() => {
        'intentId': intentId,
        'resolved': resolved.toJson(),
        'status': status,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommerceIntentResponse &&
          other.intentId == intentId &&
          other.resolved == resolved &&
          other.status == status;

  @override
  int get hashCode => Object.hash(intentId, resolved, status);
}

void _requireString(String value, String key) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, key, 'Expected a non-empty string');
  }
}

void _requireOptionalString(String? value, String key) {
  if (value != null) _requireString(value, key);
}
