import 'package:restage_shared/src/offers/offers.dart';
import 'package:test/test.dart';

const _purchaseIntentId = '550e8400-e29b-41d4-a716-446655440000';
const _legacyJson = <String, dynamic>{
  'productId': 'com.example.app.pro_monthly',
  'offerId': 'winback_3mo',
  'appAccountToken': 'a3f1c2d4-0000-4000-8000-000000000001',
};
const _intentJson = <String, dynamic>{
  'purchaseIntentId': _purchaseIntentId,
};

void main() {
  group('SECURITY — disjoint offer-signature request variants', () {
    test('legacy constructor and exact three-key wire stay unchanged', () {
      const request = OfferSignatureRequest(
        productId: 'com.example.app.pro_monthly',
        offerId: 'winback_3mo',
        appAccountToken: 'a3f1c2d4-0000-4000-8000-000000000001',
      );

      expect(request.toJson(), _legacyJson);
      expect(request.toJson().keys.toSet(), {
        'productId',
        'offerId',
        'appAccountToken',
      });
      expect(OfferSignatureRequest.fromJson(_legacyJson), request);
    });

    test('intent-bound request is exactly one canonical purchaseIntentId key',
        () {
      final request = IntentBoundOfferSignatureRequest(
        purchaseIntentId: _purchaseIntentId,
      );

      expect(request.toJson(), _intentJson);
      expect(request.toJson().keys.toSet(), {'purchaseIntentId'});
      expect(IntentBoundOfferSignatureRequest.fromJson(_intentJson), request);
    });

    test('legacy decoder rejects unknown, missing, partial, and null fields',
        () {
      for (final key in _legacyJson.keys) {
        final missing = Map<String, dynamic>.from(_legacyJson)..remove(key);
        final nullValue = Map<String, dynamic>.from(_legacyJson)..[key] = null;

        expect(
          () => OfferSignatureRequest.fromJson(missing),
          throwsArgumentError,
          reason: 'missing $key must map to boundary 400',
        );
        expect(
          () => OfferSignatureRequest.fromJson(nullValue),
          throwsArgumentError,
          reason: 'null $key must map to boundary 400',
        );
      }

      expect(
        () => OfferSignatureRequest.fromJson({
          ..._legacyJson,
          'unexpected': true,
        }),
        throwsArgumentError,
        reason: 'unknown legacy keys must map to boundary 400',
      );
    });

    test('intent decoder rejects unknown, missing, and null fields', () {
      for (final invalid in <Map<String, dynamic>>[
        const {},
        const {'purchaseIntentId': null},
        const {
          'purchaseIntentId': _purchaseIntentId,
          'unexpected': true,
        },
      ]) {
        expect(
          () => IntentBoundOfferSignatureRequest.fromJson(invalid),
          throwsArgumentError,
          reason: '$invalid must map to boundary 400',
        );
      }
    });

    test('intent decoder rejects every noncanonical or non-v4 UUID', () {
      for (final value in const [
        '',
        '550E8400-E29B-41D4-A716-446655440000',
        '550e8400-e29b-11d4-a716-446655440000',
        '550e8400-e29b-41d4-c716-446655440000',
        '{550e8400-e29b-41d4-a716-446655440000}',
        '550e8400e29b41d4a716446655440000',
        ' 550e8400-e29b-41d4-a716-446655440000',
        '550e8400-e29b-41d4-a716-446655440000 ',
      ]) {
        expect(
          () => IntentBoundOfferSignatureRequest.fromJson({
            'purchaseIntentId': value,
          }),
          throwsArgumentError,
          reason:
              'noncanonical purchaseIntentId $value must map to boundary 400',
        );
      }
    });

    test('mixed legacy-plus-intent shapes are never partially accepted', () {
      final mixed = <String, dynamic>{..._legacyJson, ..._intentJson};

      expect(
        () => OfferSignatureRequest.fromJson(mixed),
        throwsArgumentError,
      );
      expect(
        () => IntentBoundOfferSignatureRequest.fromJson(mixed),
        throwsArgumentError,
      );
      expect(_boundaryStatus(mixed), 400);
    });

    test('the boundary accepts only either exact known key set', () {
      expect(_boundaryStatus(_legacyJson), 200);
      expect(_boundaryStatus(_intentJson), 200);

      for (final invalid in <Map<String, dynamic>>[
        const {},
        const {'variant': 'future', 'payload': <String, dynamic>{}},
        const {'purchaseIntentId': null},
        const {
          'purchaseIntentId': _purchaseIntentId,
          'futureUnionKey': 'unsupported',
        },
        const {'productId': 'p', 'offerId': 'o'},
      ]) {
        expect(
          _boundaryStatus(invalid),
          400,
          reason: 'missing, partial, null, unknown, and future variants fail '
              'closed at the HTTP boundary',
        );
      }
    });
  });
}

int _boundaryStatus(Map<String, dynamic> json) {
  try {
    _decodeExactBoundaryVariant(json);
    return 200;
  } on ArgumentError {
    return 400;
  } on FormatException {
    return 400;
  }
}

Object _decodeExactBoundaryVariant(Map<String, dynamic> json) {
  final keys = json.keys.toSet();
  if (_sameKeys(keys, _legacyJson.keys.toSet())) {
    return OfferSignatureRequest.fromJson(json);
  }
  if (_sameKeys(keys, _intentJson.keys.toSet())) {
    return IntentBoundOfferSignatureRequest.fromJson(json);
  }
  throw const FormatException('Unsupported offer-signature request shape');
}

bool _sameKeys(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
