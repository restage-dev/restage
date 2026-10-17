import 'package:meta/meta.dart';
import 'package:restage_shared/src/entitlements/commerce_wire.dart';
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
  }) {
    if (!_reportOutcomes.contains(outcome)) {
      throw ArgumentError.value(outcome, 'outcome', 'Unsupported outcome');
    }
    return CommerceReportResponse._(
      outcome: outcome,
      purchaserState: purchaserState,
      verifiedPurchaseState: verifiedPurchaseState,
    );
  }

  const CommerceReportResponse._({
    required this.outcome,
    required this.purchaserState,
    required this.verifiedPurchaseState,
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
    return CommerceReportResponse._(
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
    );
  }

  /// Verification result.
  final String outcome;

  /// Authoritative purchaser state after processing the report.
  final CommercePurchaserStateResponse purchaserState;

  /// State derived from the exact purchase accepted by this report.
  ///
  /// This is absent when the server cannot prove that the caller submitted the
  /// accepted purchase. It contains only that purchase's entitlement grants.
  final CommercePurchaserStateResponse? verifiedPurchaseState;

  /// Converts this response to its wire representation.
  Map<String, dynamic> toJson() => {
        'outcome': outcome,
        'purchaserState': purchaserState.toJson(),
        if (verifiedPurchaseState != null)
          'verifiedPurchaseState': verifiedPurchaseState!.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommerceReportResponse &&
          other.outcome == outcome &&
          other.purchaserState == purchaserState &&
          other.verifiedPurchaseState == verifiedPurchaseState;

  @override
  int get hashCode => Object.hash(
        outcome,
        purchaserState,
        verifiedPurchaseState,
      );
}

const _reportOutcomes = {'verified', 'pending', 'rejected'};
