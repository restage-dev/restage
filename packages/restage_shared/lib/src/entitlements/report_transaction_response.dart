import 'package:meta/meta.dart';
import 'package:restage_shared/src/entitlements/entitlement_summary.dart';

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

/// Explicit durable acceptance returned by a transaction report.
@immutable
final class ReportTransactionResponse {
  /// Creates a transaction-report response.
  ReportTransactionResponse({
    required this.accepted,
    required this.reportId,
    required this.evidence,
    required this.attributionDisposition,
    List<EntitlementSummary> entitlements = const [],
    this.purchaseIntentDisposition,
    this.recoveredAppAnonymousToken,
  }) : entitlements = List.unmodifiable(entitlements) {
    _validatePurchaseIntentRecovery(
      purchaseIntentDisposition,
      recoveredAppAnonymousToken,
    );
  }

  /// Parses a transaction-report response.
  factory ReportTransactionResponse.fromJson(Map<String, dynamic> json) {
    final accepted = json['accepted'];
    if (accepted is! bool) {
      throw ArgumentError.value(
        accepted,
        'accepted',
        'Expected a bool',
      );
    }
    final rawReportId = json['reportId'];
    if (rawReportId != null && rawReportId is! String) {
      throw ArgumentError.value(
        rawReportId,
        'reportId',
        'Expected a string or null',
      );
    }
    final rawEvidence = json['evidence'];
    if (rawEvidence is! Map) {
      throw ArgumentError.value(
        rawEvidence,
        'evidence',
        'Expected an object',
      );
    }
    final rawEntitlements = json['entitlements'];
    if (rawEntitlements is! List) {
      throw ArgumentError.value(
        rawEntitlements,
        'entitlements',
        'Expected a list',
      );
    }
    final entitlements = <EntitlementSummary>[];
    for (final entry in rawEntitlements) {
      if (entry is! Map) {
        throw ArgumentError.value(
          entry,
          'entitlements',
          'Expected each entry to be an object',
        );
      }
      entitlements.add(
        EntitlementSummary.fromJson(entry.cast<String, dynamic>()),
      );
    }
    final rawPurchaseIntentDisposition = json['purchaseIntentDisposition'];
    final purchaseIntentDisposition = rawPurchaseIntentDisposition == null
        ? null
        : PurchaseIntentDisposition.fromJson(rawPurchaseIntentDisposition);
    final rawRecoveredAppAnonymousToken = json['recoveredAppAnonymousToken'];
    if (rawRecoveredAppAnonymousToken != null &&
        rawRecoveredAppAnonymousToken is! String) {
      throw ArgumentError.value(
        rawRecoveredAppAnonymousToken,
        'recoveredAppAnonymousToken',
        'Expected a canonical-form UUIDv4 or null',
      );
    }
    final recoveredAppAnonymousToken = rawRecoveredAppAnonymousToken as String?;
    return ReportTransactionResponse(
      accepted: accepted,
      reportId: rawReportId as String?,
      evidence: AcceptedStoreEvidence.fromJson(
        rawEvidence.cast<String, dynamic>(),
      ),
      attributionDisposition: AttributionDisposition.fromJson(
        json['attributionDisposition'],
      ),
      purchaseIntentDisposition: purchaseIntentDisposition,
      recoveredAppAnonymousToken: recoveredAppAnonymousToken,
      entitlements: entitlements,
    );
  }

  /// Whether the accepted-state transaction committed.
  final bool accepted;

  /// Echoed client correlation ID, or null for a legacy request.
  final String? reportId;

  /// Non-secret evidence binding the accepted state to the store report.
  final AcceptedStoreEvidence evidence;

  /// Actual subscription-level attribution outcome.
  final AttributionDisposition attributionDisposition;

  /// Authoritative entitlement summaries, which may be empty on acceptance.
  final List<EntitlementSummary> entitlements;

  /// Purchase-intent association outcome, when evaluated for this report.
  final PurchaseIntentDisposition? purchaseIntentDisposition;

  /// Authenticated anonymous install token recovered from an associated
  /// purchase intent.
  final String? recoveredAppAnonymousToken;

  /// Converts this response to JSON.
  Map<String, dynamic> toJson() => {
        'accepted': accepted,
        'reportId': reportId,
        'evidence': evidence.toJson(),
        'attributionDisposition': attributionDisposition.name,
        'entitlements': [
          for (final entitlement in entitlements) entitlement.toJson(),
        ],
        if (purchaseIntentDisposition != null)
          'purchaseIntentDisposition': purchaseIntentDisposition!.name,
        if (recoveredAppAnonymousToken != null)
          'recoveredAppAnonymousToken': recoveredAppAnonymousToken,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReportTransactionResponse ||
        other.accepted != accepted ||
        other.reportId != reportId ||
        other.evidence != evidence ||
        other.attributionDisposition != attributionDisposition ||
        other.purchaseIntentDisposition != purchaseIntentDisposition ||
        other.recoveredAppAnonymousToken != recoveredAppAnonymousToken ||
        other.entitlements.length != entitlements.length) {
      return false;
    }
    for (var i = 0; i < entitlements.length; i += 1) {
      if (other.entitlements[i] != entitlements[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        accepted,
        reportId,
        evidence,
        attributionDisposition,
        Object.hashAll(entitlements),
        purchaseIntentDisposition,
        recoveredAppAnonymousToken,
      );
}

void _validatePurchaseIntentRecovery(
  PurchaseIntentDisposition? disposition,
  String? recoveredToken,
) {
  switch (disposition) {
    case PurchaseIntentDisposition.associated:
    case PurchaseIntentDisposition.alreadyAssociated:
      if (recoveredToken == null || !_isCanonicalFormUuidV4(recoveredToken)) {
        throw ArgumentError.value(
          recoveredToken,
          'recoveredAppAnonymousToken',
          'Associated purchase intents require a canonical-form UUIDv4',
        );
      }
      return;
    case PurchaseIntentDisposition.notProvided:
    case PurchaseIntentDisposition.unmatched:
      if (recoveredToken != null) {
        throw ArgumentError.value(
          recoveredToken,
          'recoveredAppAnonymousToken',
          'This purchase-intent disposition does not permit a recovered token',
        );
      }
      return;
    case null:
      if (recoveredToken != null) {
        throw ArgumentError.value(
          recoveredToken,
          'recoveredAppAnonymousToken',
          'A recovered token requires a purchase-intent disposition',
        );
      }
      return;
  }
}

bool _isCanonicalFormUuidV4(String value) {
  if (value.length != 36) return false;
  for (var index = 0; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (index == 8 || index == 13 || index == 18 || index == 23) {
      if (codeUnit != 0x2d) return false;
      continue;
    }
    final isHex = (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x61 && codeUnit <= 0x66) ||
        (codeUnit >= 0x41 && codeUnit <= 0x46);
    if (!isHex) return false;
  }
  if (value.codeUnitAt(14) != 0x34) return false;
  final variant = value.codeUnitAt(19);
  return variant == 0x38 ||
      variant == 0x39 ||
      variant == 0x61 ||
      variant == 0x62 ||
      variant == 0x41 ||
      variant == 0x42;
}

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
