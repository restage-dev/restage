import 'package:meta/meta.dart';

const _maxStringLength = 1024;
// Compare the exact signed-int64 ceiling as two web-safe decimal chunks. The
// single `9223372036854775807` int literal cannot be represented exactly by
// dart2js and makes every web consumer of this public library fail to compile.
const _signedInt64ChunkBase = 1000000;
const _maxSignedInt64HighChunk = 9223372036854;
const _maxSignedInt64LowChunk = 775807;
const _stores = {'appStore', 'playStore'};
const _requestFields = {
  'purchaseIntentId',
  'store',
  'appAnonymousToken',
  'storeProductId',
  'basePlanId',
  'offerId',
  'paywallId',
  'paywallVariantSlug',
  'paywallPublishedVersion',
  'experimentId',
  'experimentVariantId',
  'experimentEpoch',
};
const _responseFields = {'purchaseIntentId', 'created'};

/// Public request to durably create an immutable purchase intent.
@immutable
final class CreatePurchaseIntentRequest {
  /// Creates a purchase-intent request.
  const CreatePurchaseIntentRequest({
    required this.purchaseIntentId,
    required this.store,
    required this.appAnonymousToken,
    required this.storeProductId,
    this.basePlanId,
    this.offerId,
    this.paywallId,
    this.paywallVariantSlug,
    this.paywallPublishedVersion,
    this.experimentId,
    this.experimentVariantId,
    this.experimentEpoch,
  })  : assert(
          store == 'appStore' || store == 'playStore',
          'store must be appStore or playStore',
        ),
        assert(
          storeProductId.length > 0 &&
              storeProductId.length <= _maxStringLength,
          'storeProductId must contain 1 to 1024 characters',
        ),
        assert(
          basePlanId == null ||
              (basePlanId.length > 0 && basePlanId.length <= _maxStringLength),
          'basePlanId must contain 1 to 1024 characters',
        ),
        assert(
          basePlanId == null || store == 'playStore',
          'basePlanId is supported only for playStore',
        ),
        assert(
          offerId == null ||
              (offerId.length > 0 && offerId.length <= _maxStringLength),
          'offerId must contain 1 to 1024 characters',
        ),
        assert(
          paywallId == null ||
              (paywallId.length > 0 && paywallId.length <= _maxStringLength),
          'paywallId must contain 1 to 1024 characters',
        ),
        assert(
          paywallVariantSlug == null ||
              (paywallVariantSlug.length > 0 &&
                  paywallVariantSlug.length <= _maxStringLength),
          'paywallVariantSlug must contain 1 to 1024 characters',
        ),
        assert(
          paywallVariantSlug == null || paywallId != null,
          'paywallVariantSlug requires paywallId',
        ),
        assert(
          paywallPublishedVersion == null || paywallId != null,
          'paywallPublishedVersion requires paywallId',
        ),
        assert(
          paywallPublishedVersion == null ||
              (paywallPublishedVersion >= 1 &&
                  (paywallPublishedVersion ~/ _signedInt64ChunkBase <
                          _maxSignedInt64HighChunk ||
                      (paywallPublishedVersion ~/ _signedInt64ChunkBase ==
                              _maxSignedInt64HighChunk &&
                          paywallPublishedVersion % _signedInt64ChunkBase <=
                              _maxSignedInt64LowChunk))),
          'paywallPublishedVersion must be an int from '
          '1 to 9223372036854775807',
        ),
        assert(
          experimentId == null ||
              (experimentId.length > 0 &&
                  experimentId.length <= _maxStringLength),
          'experimentId must contain 1 to 1024 characters',
        ),
        assert(
          experimentVariantId == null ||
              (experimentVariantId.length > 0 &&
                  experimentVariantId.length <= _maxStringLength),
          'experimentVariantId must contain 1 to 1024 characters',
        ),
        assert(
          (experimentId == null &&
                  experimentVariantId == null &&
                  experimentEpoch == null) ||
              (experimentId != null &&
                  experimentVariantId != null &&
                  experimentEpoch != null),
          'experimentId, experimentVariantId, and experimentEpoch must be '
          'provided together',
        ),
        assert(
          experimentId == null || paywallId != null,
          'experiment metadata requires paywallId',
        ),
        assert(
          experimentEpoch == null ||
              (experimentEpoch >= 1 &&
                  (experimentEpoch ~/ _signedInt64ChunkBase <
                          _maxSignedInt64HighChunk ||
                      (experimentEpoch ~/ _signedInt64ChunkBase ==
                              _maxSignedInt64HighChunk &&
                          experimentEpoch % _signedInt64ChunkBase <=
                              _maxSignedInt64LowChunk))),
          'experimentEpoch must be an int from 1 to 9223372036854775807',
        );

  /// Strictly parses the frozen public request shape.
  factory CreatePurchaseIntentRequest.fromJson(Map<String, dynamic> json) {
    _rejectUnknownFields(json, _requestFields);

    final purchaseIntentId = _requiredBoundedString(json, 'purchaseIntentId');
    _requireCanonicalLowercaseUuidV4(purchaseIntentId, 'purchaseIntentId');

    final store = _requiredBoundedString(json, 'store');
    if (!_stores.contains(store)) {
      throw ArgumentError.value(store, 'store', 'Unsupported value');
    }

    final appAnonymousToken = _requiredBoundedString(
      json,
      'appAnonymousToken',
    );
    _requireCanonicalFormUuidV4(appAnonymousToken, 'appAnonymousToken');

    final paywallId = _optionalBoundedString(json, 'paywallId');
    final paywallVariantSlug = _optionalBoundedString(
      json,
      'paywallVariantSlug',
    );
    final paywallPublishedVersion = _optionalPositiveSignedInt64(
      json,
      'paywallPublishedVersion',
    );

    final experimentId = _optionalBoundedString(json, 'experimentId');
    final experimentVariantId = _optionalBoundedString(
      json,
      'experimentVariantId',
    );
    final experimentEpoch = _optionalPositiveSignedInt64(
      json,
      'experimentEpoch',
    );

    final hasAnyExperimentMetadata = experimentId != null ||
        experimentVariantId != null ||
        experimentEpoch != null;
    final hasCompleteExperimentMetadata = experimentId != null &&
        experimentVariantId != null &&
        experimentEpoch != null;
    if (hasAnyExperimentMetadata && !hasCompleteExperimentMetadata) {
      throw ArgumentError.value(
        {
          'experimentId': experimentId,
          'experimentVariantId': experimentVariantId,
          'experimentEpoch': experimentEpoch,
        },
        'json',
        'experimentId, experimentVariantId, and experimentEpoch must be '
            'provided together',
      );
    }

    if (paywallVariantSlug != null && paywallId == null) {
      throw ArgumentError.value(
        paywallVariantSlug,
        'paywallVariantSlug',
        'paywallId is required when paywallVariantSlug is provided',
      );
    }
    if (paywallPublishedVersion != null && paywallId == null) {
      throw ArgumentError.value(
        paywallPublishedVersion,
        'paywallPublishedVersion',
        'paywallId is required when paywallPublishedVersion is provided',
      );
    }
    if (hasCompleteExperimentMetadata && paywallId == null) {
      throw ArgumentError.value(
        experimentId,
        'experimentId',
        'paywallId is required when experiment metadata is provided',
      );
    }

    final basePlanId = _optionalBoundedString(json, 'basePlanId');
    if (basePlanId != null && store != 'playStore') {
      throw ArgumentError.value(
        basePlanId,
        'basePlanId',
        'basePlanId is supported only for playStore',
      );
    }

    return CreatePurchaseIntentRequest(
      purchaseIntentId: purchaseIntentId,
      store: store,
      appAnonymousToken: appAnonymousToken,
      storeProductId: _requiredBoundedString(json, 'storeProductId'),
      basePlanId: basePlanId,
      offerId: _optionalBoundedString(json, 'offerId'),
      paywallId: paywallId,
      paywallVariantSlug: paywallVariantSlug,
      paywallPublishedVersion: paywallPublishedVersion,
      experimentId: experimentId,
      experimentVariantId: experimentVariantId,
      experimentEpoch: experimentEpoch,
    );
  }

  /// Client-generated canonical lowercase UUIDv4 for this intent.
  final String purchaseIntentId;

  /// Store whose purchase UI will be opened.
  final String store;

  /// Canonical-form anonymous install token used for entitlement recovery.
  ///
  /// Hexadecimal casing is preserved exactly as submitted.
  final String appAnonymousToken;

  /// Store product identifier selected by the SDK.
  final String storeProductId;

  /// Google Play base-plan identifier, when known.
  final String? basePlanId;

  /// Store offer identifier, when known.
  final String? offerId;

  /// Client-known paywall identifier, when known.
  ///
  /// This is the public identifier carried by `ResolvedVariant` and
  /// `FlowPaywallPayload`, not a numeric persistence identifier.
  final String? paywallId;

  /// Client-known paywall variant slug, when known.
  ///
  /// This identifies a paywall variant. It is distinct from
  /// [experimentVariantId], which identifies an experiment arm.
  final String? paywallVariantSlug;

  /// Client-known published paywall version, when known.
  ///
  /// This is the published-version counter carried by `ResolvedVariant` and
  /// `FlowPaywallPayload`, not a numeric persistence identifier.
  final int? paywallPublishedVersion;

  /// Client-known experiment identifier, when known.
  ///
  /// This is assignment metadata carried by `ResolvedVariant` and
  /// `FlowPaywallPayload`, not a numeric persistence identifier.
  final String? experimentId;

  /// Client-known experiment arm identifier, when known.
  ///
  /// This is the resolver's experiment `variantId`, not
  /// [paywallVariantSlug] and not a numeric persistence identifier.
  final String? experimentVariantId;

  /// Client-known experiment epoch, when known.
  ///
  /// This is assignment metadata carried by `ResolvedVariant` and
  /// `FlowPaywallPayload`, not a numeric persistence identifier.
  final int? experimentEpoch;

  /// Converts this request to the frozen public JSON shape.
  Map<String, dynamic> toJson() {
    return {
      'purchaseIntentId': purchaseIntentId,
      'store': store,
      'appAnonymousToken': appAnonymousToken,
      'storeProductId': storeProductId,
      if (basePlanId != null) 'basePlanId': basePlanId,
      if (offerId != null) 'offerId': offerId,
      if (paywallId != null) 'paywallId': paywallId,
      if (paywallVariantSlug != null) 'paywallVariantSlug': paywallVariantSlug,
      if (paywallPublishedVersion != null)
        'paywallPublishedVersion': paywallPublishedVersion,
      if (experimentId != null) 'experimentId': experimentId,
      if (experimentVariantId != null)
        'experimentVariantId': experimentVariantId,
      if (experimentEpoch != null) 'experimentEpoch': experimentEpoch,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CreatePurchaseIntentRequest &&
            other.purchaseIntentId == purchaseIntentId &&
            other.store == store &&
            other.appAnonymousToken == appAnonymousToken &&
            other.storeProductId == storeProductId &&
            other.basePlanId == basePlanId &&
            other.offerId == offerId &&
            other.paywallId == paywallId &&
            other.paywallVariantSlug == paywallVariantSlug &&
            other.paywallPublishedVersion == paywallPublishedVersion &&
            other.experimentId == experimentId &&
            other.experimentVariantId == experimentVariantId &&
            other.experimentEpoch == experimentEpoch;
  }

  @override
  int get hashCode => Object.hash(
        purchaseIntentId,
        store,
        appAnonymousToken,
        storeProductId,
        basePlanId,
        offerId,
        paywallId,
        paywallVariantSlug,
        paywallPublishedVersion,
        experimentId,
        experimentVariantId,
        experimentEpoch,
      );
}

/// Public result of durably creating or exactly replaying a purchase intent.
@immutable
final class CreatePurchaseIntentResponse {
  /// Creates a purchase-intent response.
  const CreatePurchaseIntentResponse({
    required this.purchaseIntentId,
    required this.created,
  });

  /// Strictly parses the frozen public response shape.
  factory CreatePurchaseIntentResponse.fromJson(Map<String, dynamic> json) {
    _rejectUnknownFields(json, _responseFields);

    final purchaseIntentId = _requiredBoundedString(json, 'purchaseIntentId');
    _requireCanonicalLowercaseUuidV4(purchaseIntentId, 'purchaseIntentId');

    final created = json['created'];
    if (created is! bool) {
      throw ArgumentError.value(created, 'created', 'Expected a bool');
    }

    return CreatePurchaseIntentResponse(
      purchaseIntentId: purchaseIntentId,
      created: created,
    );
  }

  /// Echoed canonical purchase-intent UUID.
  final String purchaseIntentId;

  /// Whether this request created the durable row.
  final bool created;

  /// Converts this response to the frozen public JSON shape.
  Map<String, dynamic> toJson() => {
        'purchaseIntentId': purchaseIntentId,
        'created': created,
      };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CreatePurchaseIntentResponse &&
            other.purchaseIntentId == purchaseIntentId &&
            other.created == created;
  }

  @override
  int get hashCode => Object.hash(purchaseIntentId, created);
}

void _rejectUnknownFields(
  Map<String, dynamic> json,
  Set<String> allowedFields,
) {
  final unknownFields = json.keys.where(
    (field) => !allowedFields.contains(field),
  );
  if (unknownFields.isEmpty) return;
  throw ArgumentError.value(
    unknownFields.first,
    'json',
    'Unsupported field',
  );
}

String _requiredBoundedString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty && value.length <= _maxStringLength) {
    return value;
  }
  throw ArgumentError.value(
    value,
    key,
    'Expected a string containing 1 to 1024 characters',
  );
}

String? _optionalBoundedString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String && value.isNotEmpty && value.length <= _maxStringLength) {
    return value;
  }
  throw ArgumentError.value(
    value,
    key,
    'Expected a string containing 1 to 1024 characters or null',
  );
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || value is int) {
    return value as int?;
  }
  throw ArgumentError.value(value, key, 'Expected an int or null');
}

int? _optionalPositiveSignedInt64(
  Map<String, dynamic> json,
  String key,
) {
  final value = _optionalInt(json, key);
  if (value == null || _isPositiveSignedInt64(value)) {
    return value;
  }
  throw ArgumentError.value(
    value,
    key,
    'Expected an int from 1 to 9223372036854775807 or null',
  );
}

bool _isPositiveSignedInt64(int value) {
  if (value < 1) return false;
  final highChunk = value ~/ _signedInt64ChunkBase;
  return highChunk < _maxSignedInt64HighChunk ||
      (highChunk == _maxSignedInt64HighChunk &&
          value % _signedInt64ChunkBase <= _maxSignedInt64LowChunk);
}

void _requireCanonicalLowercaseUuidV4(String value, String key) {
  if (_isCanonicalUuidV4(value, acceptUppercaseHex: false)) return;
  throw ArgumentError.value(
    value,
    key,
    'Expected a canonical lowercase UUIDv4',
  );
}

void _requireCanonicalFormUuidV4(String value, String key) {
  if (_isCanonicalUuidV4(value, acceptUppercaseHex: true)) return;
  throw ArgumentError.value(
    value,
    key,
    'Expected a canonical-form UUIDv4',
  );
}

bool _isCanonicalUuidV4(
  String value, {
  required bool acceptUppercaseHex,
}) {
  if (value.length != 36) return false;
  for (var index = 0; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (index == 8 || index == 13 || index == 18 || index == 23) {
      if (codeUnit != 0x2d) return false;
      continue;
    }
    final isHex = (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x61 && codeUnit <= 0x66) ||
        (acceptUppercaseHex && codeUnit >= 0x41 && codeUnit <= 0x46);
    if (!isHex) return false;
  }
  if (value.codeUnitAt(14) != 0x34) return false;
  final variant = value.codeUnitAt(19);
  return variant == 0x38 ||
      variant == 0x39 ||
      variant == 0x61 ||
      variant == 0x62 ||
      (acceptUppercaseHex && (variant == 0x41 || variant == 0x42));
}
