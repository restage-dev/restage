import 'package:meta/meta.dart';
import 'package:restage_shared/src/entitlements/commerce_wire.dart';
import 'package:restage_shared/src/entitlements/entitlement_summary.dart';
import 'package:restage_shared/src/entitlements/entitlement_sync_response.dart';

/// How purchase-intent evidence affected an accepted transaction report.
enum PurchaseIntentDisposition {
  /// The provider evidence carried no purchase-intent identifier or binding.
  notProvided,

  /// An eligible purchase intent was associated for the first time.
  associated,

  /// The purchase intent already had the same association.
  alreadyAssociated,

  /// Purchase-intent evidence was present, but no eligible association was
  /// applied.
  unmatched;

  /// Parses a known purchase-intent disposition wire value.
  static PurchaseIntentDisposition fromJson(Object? value) {
    if (value is String) {
      for (final disposition in values) {
        if (disposition.name == value) return disposition;
      }
    }
    throw ArgumentError.value(
      value,
      'purchaseIntentDisposition',
      'Expected a known purchase-intent disposition',
    );
  }
}

/// The result of processing store evidence.
@immutable
final class CommerceReportResponse {
  /// Creates a report response.
  factory CommerceReportResponse({
    required String outcome,
    required CommercePurchaserStateResponse purchaserState,
    CommercePurchaserStateResponse? verifiedPurchaseState,
    List<CommerceVerifiedPurchase>? verifiedPurchases,
    bool restoreHistoryTruncated = false,
  }) {
    if (!_reportOutcomes.contains(outcome)) {
      throw ArgumentError.value(outcome, 'outcome', 'Unsupported outcome');
    }
    return CommerceReportResponse._(
      outcome: outcome,
      purchaserState: purchaserState,
      verifiedPurchaseState: verifiedPurchaseState,
      restoreHistoryTruncated: restoreHistoryTruncated,
      verifiedPurchases: verifiedPurchases == null
          ? null
          : List.unmodifiable(verifiedPurchases),
    );
  }

  const CommerceReportResponse._({
    required this.outcome,
    required this.purchaserState,
    required this.verifiedPurchaseState,
    required this.verifiedPurchases,
    required this.restoreHistoryTruncated,
  });

  /// Parses a response while allowing future additive fields.
  factory CommerceReportResponse.fromJson(Map<String, dynamic> json) {
    final rawState = json['purchaserState'];
    if (rawState is! Map) {
      throw ArgumentError.value(
        rawState,
        'purchaserState',
        'Expected an object',
      );
    }
    final rawVerifiedPurchaseState = json['verifiedPurchaseState'];
    final Map<String, dynamic>? verifiedPurchaseStateJson;
    if (rawVerifiedPurchaseState == null) {
      verifiedPurchaseStateJson = null;
    } else if (rawVerifiedPurchaseState is Map) {
      verifiedPurchaseStateJson = rawVerifiedPurchaseState.cast();
    } else {
      throw ArgumentError.value(
        rawVerifiedPurchaseState,
        'verifiedPurchaseState',
        'Expected an object or null',
      );
    }
    final rawTruncated = json['restoreHistoryTruncated'];
    if (json.containsKey('restoreHistoryTruncated') && rawTruncated is! bool) {
      throw ArgumentError.value(
          rawTruncated, 'restoreHistoryTruncated', 'Expected a bool');
    }
    return CommerceReportResponse._(
      restoreHistoryTruncated: rawTruncated == true,
      outcome: normalizeCommerceResponseCode(
        requiredCommerceString(json, 'outcome'),
        _reportOutcomes,
      ),
      purchaserState: CommercePurchaserStateResponse.fromJson(
        rawState.cast<String, dynamic>(),
      ),
      verifiedPurchaseState: verifiedPurchaseStateJson == null
          ? null
          : CommercePurchaserStateResponse.fromJson(
              verifiedPurchaseStateJson,
            ),
      verifiedPurchases: _verifiedPurchasesFromJson(json),
    );
  }

  /// Verification result.
  final String outcome;

  /// Authoritative purchaser state after processing the report.
  final CommercePurchaserStateResponse purchaserState;

  /// Aggregate state from the receipt-proved purchases accepted by this report.
  ///
  /// This is absent when the server cannot prove that the caller submitted the
  /// accepted purchases. When [verifiedPurchases] is present, this reduces those
  /// entries' entitlements and fulfillment lines.
  final CommercePurchaserStateResponse? verifiedPurchaseState;

  /// Current receipt-proved purchases, including explicit empty outcomes.
  ///
  /// Absence supplies no per-purchase update. An entry updates only its exact
  /// store transaction; omitting a sibling does not revoke that sibling.
  final List<CommerceVerifiedPurchase>? verifiedPurchases;

  /// Whether Apple restore history or returned signed proofs are incomplete.
  /// Verified entries remain usable; omitted siblings carry no removal authority.
  final bool restoreHistoryTruncated;

  /// Converts this response to its wire representation.
  Map<String, dynamic> toJson() => {
        'outcome': outcome,
        if (restoreHistoryTruncated) 'restoreHistoryTruncated': true,
        'purchaserState': purchaserState.toJson(),
        if (verifiedPurchaseState != null)
          'verifiedPurchaseState': verifiedPurchaseState!.toJson(),
        if (verifiedPurchases != null)
          'verifiedPurchases': [
            for (final purchase in verifiedPurchases!) purchase.toJson(),
          ],
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommerceReportResponse &&
          other.outcome == outcome &&
          other.purchaserState == purchaserState &&
          other.verifiedPurchaseState == verifiedPurchaseState &&
          other.restoreHistoryTruncated == restoreHistoryTruncated &&
          _sameList(other.verifiedPurchases, verifiedPurchases);

  @override
  int get hashCode => Object.hash(
        outcome,
        purchaserState,
        verifiedPurchaseState,
        restoreHistoryTruncated,
        verifiedPurchases == null ? null : Object.hashAll(verifiedPurchases!),
      );
}

/// The current result of one verified store transaction.
///
/// Subscription entries retain the existing current chain summaries. One-time
/// entries describe only this accepted occurrence and its fulfillment lines.
@immutable
final class CommerceVerifiedPurchase {
  /// Creates one immutable receipt-proved purchase result.
  CommerceVerifiedPurchase({
    required this.storeTransactionId,
    required this.productId,
    required this.providerEnvironment,
    required this.kind,
    required this.outcome,
    this.outcomeOrder,
    int catalogRevision = 0,
    this.includedInPurchaserState = false,
    this.requiresHistoryRecovery = false,
    this.storeVerificationData,
    required List<EntitlementSummary> entitlements,
    List<CommerceFulfillmentSummary> fulfillments = const [],
    this.expiresAtMs,
  })  : catalogRevision = commerceCatalogRevision(catalogRevision),
        entitlements = List.unmodifiable(entitlements),
        fulfillments = List.unmodifiable(fulfillments) {
    if (storeTransactionId.isEmpty) {
      throw ArgumentError.value(storeTransactionId, 'storeTransactionId');
    }
    if (productId.isEmpty) throw ArgumentError.value(productId, 'productId');
    if (storeVerificationData != null && storeVerificationData!.isEmpty) {
      throw ArgumentError.value(storeVerificationData, 'storeVerificationData');
    }
    if (providerEnvironment != 'production' &&
        providerEnvironment != 'sandbox') {
      throw ArgumentError.value(providerEnvironment, 'providerEnvironment');
    }
    if (!_verifiedPurchaseKinds.contains(kind)) {
      throw ArgumentError.value(kind, 'kind');
    }
    if (kind == 'oneTimePurchase'
        ? (outcomeOrder ?? 0) <= 0
        : outcomeOrder != null) {
      throw ArgumentError.value(outcomeOrder, 'outcomeOrder');
    }
    if (!_verifiedPurchaseOutcomes.contains(outcome) ||
        (kind == 'oneTimePurchase' && outcome == 'unknown')) {
      throw ArgumentError.value(outcome, 'outcome');
    }
    if (outcome != 'granted' &&
        (entitlements.any((entry) => entry.isEntitled) ||
            fulfillments.isNotEmpty)) {
      throw ArgumentError('An inactive purchase cannot carry active grants.');
    }
    if (kind == 'subscription' && fulfillments.isNotEmpty) {
      throw ArgumentError('Subscriptions do not carry fulfillment inventory.');
    }
    if (entitlements.any(
          (entry) => entry.providerEnvironment != providerEnvironment,
        ) ||
        fulfillments.any(
          (entry) =>
              entry.providerEnvironment != providerEnvironment ||
              entry.productId != productId,
        ) ||
        (kind == 'oneTimePurchase' &&
            entitlements.any((entry) => entry.productId != productId))) {
      throw ArgumentError('Purchase grants must match their verified scope.');
    }
  }

  /// Parses a purchase while allowing future additive fields.
  factory CommerceVerifiedPurchase.fromJson(Map<String, dynamic> json) =>
      CommerceVerifiedPurchase(
        storeTransactionId: requiredCommerceString(json, 'storeTransactionId'),
        productId: requiredCommerceString(json, 'productId'),
        providerEnvironment:
            requiredCommerceString(json, 'providerEnvironment'),
        kind: requiredCommerceString(json, 'kind'),
        outcome: requiredCommerceString(json, 'outcome'),
        outcomeOrder: optionalCommerceInt(json, 'outcomeOrder'),
        catalogRevision: commerceCatalogRevision(json['catalogRevision']),
        includedInPurchaserState:
            _requiredBool(json, 'includedInPurchaserState'),
        storeVerificationData:
            optionalCommerceString(json, 'storeVerificationData'),
        requiresHistoryRecovery: json.containsKey('requiresHistoryRecovery')
            ? _requiredBool(json, 'requiresHistoryRecovery')
            : false,
        entitlements: _purchaseEntries(
          json,
          'entitlements',
          EntitlementSummary.fromJson,
        ),
        fulfillments: _purchaseEntries(
          json,
          'fulfillments',
          CommerceFulfillmentSummary.fromJson,
        ),
        expiresAtMs: optionalCommerceInt(json, 'expiresAtMs'),
      );

  /// Stable provider transaction identity; never a raw purchase token.
  final String storeTransactionId;

  /// Store product accepted for this transaction.
  final String productId;

  /// Verified store environment, including for an empty result.
  final String providerEnvironment;

  /// Either `subscription` or `oneTimePurchase`.
  final String kind;

  /// Current granted, revoked, refunded, expired, or unknown outcome.
  /// Unknown is reserved for subscriptions without an effective mapped state.
  final String outcome;

  /// Orders retained outcomes only within this same store transaction.
  /// Does not order response arrival. Required and positive for one-time
  /// purchases; null for subscriptions.
  final int? outcomeOrder;

  /// Current association revision, independent of the signed outcome order.
  final int catalogRevision;

  /// Whether this purchase contributes to state for the report subject and configuration.
  final bool includedInPurchaserState;

  /// Provider-signed evidence retained for this exact accepted transaction.
  final String? storeVerificationData;

  /// Whether refreshing this purchase may require signed transaction history.
  final bool requiresHistoryRecovery;

  /// Existing effective entitlement summaries proved by this purchase.
  final List<EntitlementSummary> entitlements;

  /// Current fulfillment lines; each retains its own purchased quantity.
  final List<CommerceFulfillmentSummary> fulfillments;

  /// Verified access-window end, including a verified subscription grace end.
  /// Null supplies no verified deadline.
  final int? expiresAtMs;

  /// Converts this purchase to its wire representation.
  Map<String, dynamic> toJson() => {
        'storeTransactionId': storeTransactionId,
        'productId': productId,
        'providerEnvironment': providerEnvironment,
        'kind': kind,
        'outcome': outcome,
        if (outcomeOrder != null) 'outcomeOrder': outcomeOrder,
        'catalogRevision': catalogRevision,
        'includedInPurchaserState': includedInPurchaserState,
        if (storeVerificationData != null)
          'storeVerificationData': storeVerificationData,
        if (requiresHistoryRecovery) 'requiresHistoryRecovery': true,
        'entitlements': [for (final entry in entitlements) entry.toJson()],
        'fulfillments': [for (final entry in fulfillments) entry.toJson()],
        if (expiresAtMs != null) 'expiresAtMs': expiresAtMs,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommerceVerifiedPurchase &&
          other.storeTransactionId == storeTransactionId &&
          other.productId == productId &&
          other.providerEnvironment == providerEnvironment &&
          other.kind == kind &&
          other.outcome == outcome &&
          other.outcomeOrder == outcomeOrder &&
          other.catalogRevision == catalogRevision &&
          other.includedInPurchaserState == includedInPurchaserState &&
          other.storeVerificationData == storeVerificationData &&
          other.requiresHistoryRecovery == requiresHistoryRecovery &&
          other.expiresAtMs == expiresAtMs &&
          _sameList(other.entitlements, entitlements) &&
          _sameList(other.fulfillments, fulfillments);

  @override
  int get hashCode => Object.hash(
        storeTransactionId,
        productId,
        providerEnvironment,
        kind,
        outcome,
        outcomeOrder,
        catalogRevision,
        includedInPurchaserState,
        storeVerificationData,
        requiresHistoryRecovery,
        expiresAtMs,
        Object.hashAll(entitlements),
        Object.hashAll(fulfillments),
      );
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw ArgumentError.value(value, key, 'Expected a bool');
}

List<CommerceVerifiedPurchase>? _verifiedPurchasesFromJson(
  Map<String, dynamic> json,
) {
  if (json['verifiedPurchases'] == null) return null;
  return List.unmodifiable(
    _purchaseEntries(
        json, 'verifiedPurchases', CommerceVerifiedPurchase.fromJson),
  );
}

List<T> _purchaseEntries<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) decode,
) {
  final raw = json[key];
  if (raw is! List) throw ArgumentError.value(raw, key, 'Expected a list');
  return [
    for (final entry in raw)
      if (entry is Map)
        decode(entry.cast<String, dynamic>())
      else
        throw ArgumentError.value(entry, key, 'Expected an object'),
  ];
}

bool _sameList<T>(List<T>? left, List<T>? right) {
  if (left == null || right == null) return left == right;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

const _reportOutcomes = {'verified', 'pending', 'rejected'};
const _verifiedPurchaseKinds = {'subscription', 'oneTimePurchase'};
const _verifiedPurchaseOutcomes = {
  'granted',
  'revoked',
  'refunded',
  'expired',
  'unknown',
};
