import 'package:meta/meta.dart';
import 'package:restage_shared/src/entitlements/commerce_wire.dart';
import 'package:restage_shared/src/entitlements/entitlement_sync_response.dart';

/// How a report's subscription-level attribution affected accepted state.
enum AttributionDisposition {
  /// The report carried no attribution fields.
  notProvided,

  /// At least one previously-empty attribution field was applied, with no
  /// conflicting field.
  applied,

  /// Every supplied attribution field already held the same value.
  alreadyApplied,

  /// At least one supplied value conflicted with an existing value, which was
  /// retained. Other previously-empty fields may still have been applied
  /// because attribution is field-wise first-non-null.
  conflictRetained;

  /// Parses the strict completion-safety wire value.
  static AttributionDisposition fromJson(Object? value) {
    if (value is String) {
      for (final disposition in values) {
        if (disposition.name == value) return disposition;
      }
    }
    throw ArgumentError.value(
      value,
      'attributionDisposition',
      'Expected a known attribution disposition',
    );
  }
}

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

/// Non-secret store evidence committed for an accepted transaction report.
@immutable
sealed class AcceptedStoreEvidence {
  const AcceptedStoreEvidence();

  /// Parses store-specific accepted evidence.
  factory AcceptedStoreEvidence.fromJson(Map<String, dynamic> json) {
    return switch (_requiredString(json, 'store')) {
      'appStore' => AppleAcceptedStoreEvidence.fromJson(json),
      'playStore' => GoogleAcceptedStoreEvidence.fromJson(json),
      final value => throw ArgumentError.value(
          value,
          'store',
          'Unsupported accepted-evidence store',
        ),
    };
  }

  /// Store wire name.
  String get store;

  /// Converts this evidence to JSON.
  Map<String, dynamic> toJson();
}

/// Accepted App Store evidence.
@immutable
final class AppleAcceptedStoreEvidence extends AcceptedStoreEvidence {
  /// Creates accepted App Store evidence.
  const AppleAcceptedStoreEvidence({
    required this.submittedTransactionId,
    required this.acceptedTransactionId,
    required this.originalTransactionId,
  });

  /// Parses accepted App Store evidence.
  factory AppleAcceptedStoreEvidence.fromJson(Map<String, dynamic> json) {
    return AppleAcceptedStoreEvidence(
      submittedTransactionId: _requiredString(
        json,
        'submittedTransactionId',
      ),
      acceptedTransactionId: _requiredString(json, 'acceptedTransactionId'),
      originalTransactionId: _requiredString(json, 'originalTransactionId'),
    );
  }

  @override
  String get store => 'appStore';

  /// Transaction ID submitted by the SDK and proven in signed history.
  final String submittedTransactionId;

  /// Transaction ID whose authoritative state drove the response.
  final String acceptedTransactionId;

  /// Original transaction ID shared by the accepted subscription history.
  final String originalTransactionId;

  @override
  Map<String, dynamic> toJson() => {
        'store': store,
        'submittedTransactionId': submittedTransactionId,
        'acceptedTransactionId': acceptedTransactionId,
        'originalTransactionId': originalTransactionId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppleAcceptedStoreEvidence &&
          other.submittedTransactionId == submittedTransactionId &&
          other.acceptedTransactionId == acceptedTransactionId &&
          other.originalTransactionId == originalTransactionId;

  @override
  int get hashCode => Object.hash(
        submittedTransactionId,
        acceptedTransactionId,
        originalTransactionId,
      );
}

/// Accepted Google Play evidence.
@immutable
final class GoogleAcceptedStoreEvidence extends AcceptedStoreEvidence {
  /// Creates accepted Google Play evidence.
  const GoogleAcceptedStoreEvidence({
    required this.submittedOrderId,
    required this.acceptedOrderId,
    required this.orderLineageId,
    required this.acceptedPurchaseTokenDigest,
  });

  /// Parses accepted Google Play evidence.
  factory GoogleAcceptedStoreEvidence.fromJson(Map<String, dynamic> json) {
    final submittedOrderId = _optionalString(json, 'submittedOrderId');
    final acceptedOrderId = _optionalString(json, 'acceptedOrderId');
    final orderLineageId = _optionalString(json, 'orderLineageId');
    if (submittedOrderId != null &&
        acceptedOrderId != null &&
        orderLineageId != null) {
      if (_googleOrderLineageId(submittedOrderId) != orderLineageId ||
          _googleOrderLineageId(acceptedOrderId) != orderLineageId) {
        throw ArgumentError(
          'submittedOrderId and acceptedOrderId must share orderLineageId',
        );
      }
    } else if (submittedOrderId != null ||
        acceptedOrderId != null ||
        orderLineageId != null) {
      throw ArgumentError(
        'Google order evidence must provide all three order fields or none',
      );
    }
    return GoogleAcceptedStoreEvidence(
      submittedOrderId: submittedOrderId,
      acceptedOrderId: acceptedOrderId,
      orderLineageId: orderLineageId,
      acceptedPurchaseTokenDigest: _requiredString(
        json,
        'acceptedPurchaseTokenDigest',
      ),
    );
  }

  @override
  String get store => 'playStore';

  /// Non-secret Play order ID submitted as the plugin purchase ID.
  final String? submittedOrderId;

  /// Authoritative order ID returned for the validated purchase token.
  final String? acceptedOrderId;

  /// Stable base order ID for the authoritative order chain.
  final String? orderLineageId;

  /// Digest of the purchase token the server validated, so a client can
  /// correlate an acceptance to the exact submitted purchase without the
  /// purchase token itself ever appearing in a response.
  ///
  /// This is a cross-implementation contract: a client recomputes it locally
  /// from the token it already holds, so the definition below is normative and
  /// must not be restated by reference to any one implementation.
  ///
  /// SHA-256 over the UTF-8 bytes of the purchase-token string exactly as
  /// received from the store — no trimming, no normalization, and no
  /// case-folding of the token — rendered as lowercase hexadecimal, 64
  /// characters. There is no salt, prefix, or key derivation: a digest that
  /// could not be recomputed from the token alone would be useless here.
  ///
  /// A Google purchase may carry no order identity at all (promotional-code
  /// redemptions), which is why this, and not an order id, is the one field
  /// present on every accepted Google evidence.
  final String acceptedPurchaseTokenDigest;

  @override
  Map<String, dynamic> toJson() => {
        'store': store,
        if (submittedOrderId != null) 'submittedOrderId': submittedOrderId,
        if (acceptedOrderId != null) 'acceptedOrderId': acceptedOrderId,
        if (orderLineageId != null) 'orderLineageId': orderLineageId,
        'acceptedPurchaseTokenDigest': acceptedPurchaseTokenDigest,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoogleAcceptedStoreEvidence &&
          other.submittedOrderId == submittedOrderId &&
          other.acceptedOrderId == acceptedOrderId &&
          other.orderLineageId == orderLineageId &&
          other.acceptedPurchaseTokenDigest == acceptedPurchaseTokenDigest;

  @override
  int get hashCode => Object.hash(
        submittedOrderId,
        acceptedOrderId,
        orderLineageId,
        acceptedPurchaseTokenDigest,
      );
}

/// The result of processing store evidence.
@immutable
final class CommerceReportResponse {
  /// Creates a report response.
  factory CommerceReportResponse({
    required String outcome,
    required CommercePurchaserStateResponse purchaserState,
  }) {
    if (!_reportOutcomes.contains(outcome)) {
      throw ArgumentError.value(outcome, 'outcome', 'Unsupported outcome');
    }
    return CommerceReportResponse._(
      outcome: outcome,
      purchaserState: purchaserState,
    );
  }

  const CommerceReportResponse._({
    required this.outcome,
    required this.purchaserState,
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
    return CommerceReportResponse._(
      outcome: normalizeCommerceResponseCode(
        requiredCommerceString(json, 'outcome'),
        _reportOutcomes,
      ),
      purchaserState: CommercePurchaserStateResponse.fromJson(
        rawState.cast<String, dynamic>(),
      ),
    );
  }

  /// Verification result.
  final String outcome;

  /// Authoritative purchaser state after processing the report.
  final CommercePurchaserStateResponse purchaserState;

  /// Converts this response to its wire representation.
  Map<String, dynamic> toJson() => {
        'outcome': outcome,
        'purchaserState': purchaserState.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommerceReportResponse &&
          other.outcome == outcome &&
          other.purchaserState == purchaserState;

  @override
  int get hashCode => Object.hash(outcome, purchaserState);
}

const _reportOutcomes = {'verified', 'pending', 'rejected'};

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw ArgumentError.value(value, key, 'Expected a non-empty string');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw ArgumentError.value(value, key, 'Expected a non-empty string or null');
}

String _googleOrderLineageId(String orderId) {
  final renewalSeparator = orderId.indexOf('..');
  return renewalSeparator < 0
      ? orderId
      : orderId.substring(0, renewalSeparator);
}
