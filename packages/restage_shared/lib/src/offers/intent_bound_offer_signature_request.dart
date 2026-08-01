import 'package:meta/meta.dart';

/// Request to mint an offer signature for a durable purchase intent.
@immutable
final class IntentBoundOfferSignatureRequest {
  /// Creates an intent-bound offer-signature request.
  IntentBoundOfferSignatureRequest({
    required this.purchaseIntentId,
  }) {
    _requireCanonicalLowercaseUuidV4(purchaseIntentId);
  }

  /// Parses the exact intent-bound request shape.
  factory IntentBoundOfferSignatureRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    if (json.length != 1 || !json.containsKey('purchaseIntentId')) {
      throw ArgumentError('Expected exactly purchaseIntentId');
    }
    final purchaseIntentId = json['purchaseIntentId'];
    if (purchaseIntentId is! String) {
      throw ArgumentError(
        'purchaseIntentId must be a canonical lowercase UUIDv4',
      );
    }
    return IntentBoundOfferSignatureRequest(
      purchaseIntentId: purchaseIntentId,
    );
  }

  /// Canonical lowercase UUIDv4 identifying the durable purchase intent.
  final String purchaseIntentId;

  /// Converts this request to its JSON wire form.
  Map<String, dynamic> toJson() => {
        'purchaseIntentId': purchaseIntentId,
      };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is IntentBoundOfferSignatureRequest &&
            other.purchaseIntentId == purchaseIntentId;
  }

  @override
  int get hashCode => purchaseIntentId.hashCode;
}

void _requireCanonicalLowercaseUuidV4(String value) {
  if (_isCanonicalLowercaseUuidV4(value)) return;
  throw ArgumentError(
    'purchaseIntentId must be a canonical lowercase UUIDv4',
  );
}

bool _isCanonicalLowercaseUuidV4(String value) {
  if (value.length != 36) return false;
  for (var index = 0; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (index == 8 || index == 13 || index == 18 || index == 23) {
      if (codeUnit != 0x2d) return false;
      continue;
    }
    final isLowercaseHex = (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x61 && codeUnit <= 0x66);
    if (!isLowercaseHex) return false;
  }
  if (value.codeUnitAt(14) != 0x34) return false;
  final variant = value.codeUnitAt(19);
  return variant == 0x38 ||
      variant == 0x39 ||
      variant == 0x61 ||
      variant == 0x62;
}
